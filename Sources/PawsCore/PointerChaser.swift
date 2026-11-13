import Foundation
import CoreGraphics

public struct ChaseFrame {
    public let origin: CGPoint
    public let isMoving: Bool
    public let facingLeft: Bool

    /// Click/hold reactions take priority. Ordinary locomotion follows the pet's
    /// own movement, including the time it needs to catch a stationary pointer.
    public func pose(for gesture: Pose) -> Pose {
        switch gesture {
        case .idle, .walk, .sleep:
            return isMoving ? .walk : (gesture == .walk ? .idle : gesture)
        default:
            return gesture
        }
    }
}

/// A time-based follower in AppKit coordinates. Position is independent of the
/// pointer: the pet approaches it, slows down, and stops just outside its reach.
public struct PointerChaser {
    public private(set) var center: CGPoint?
    private var lastTime: TimeInterval?
    private var lastScreen: CGRect?
    private var lastSize: CGSize?
    private var moving = false
    private var facingLeft = false

    public init() {}

    public mutating func reset() {
        self = PointerChaser()
    }

    public mutating func update(pointer: CGPoint, size: CGSize, screen: CGRect,
                                time: TimeInterval, reducedMotion: Bool = false) -> ChaseFrame {
        let radius = max(size.width, size.height) / 2 + 8
        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, screen.minX + size.width / 2), max(screen.minX + size.width / 2, screen.maxX - size.width / 2)),
                y: min(max(point.y, screen.minY + size.height / 2), max(screen.minY + size.height / 2, screen.maxY - size.height / 2))
            )
        }
        func restingCenter() -> CGPoint {
            let origin = OverlayPlacement.origin(pointer: pointer, size: size, screen: screen)
            let candidate = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            let dx = candidate.x - pointer.x, dy = candidate.y - pointer.y
            let length = max(1, hypot(dx, dy))
            return clamped(CGPoint(x: pointer.x + dx / length * radius, y: pointer.y + dy / length * radius))
        }

        if center == nil || lastScreen != screen || lastSize != size || reducedMotion {
            // A new display starts beside the pointer; never chase through the
            // empty desktop space between disconnected monitor arrangements.
            center = restingCenter()
            moving = false
        } else if let current = center, let previousTime = lastTime {
            let dt = max(0, min(time - previousTime, 1.0 / 15.0))
            let dx = pointer.x - current.x, dy = pointer.y - current.y
            let distance = hypot(dx, dy)
            let remaining = max(0, distance - radius)
            // Hysteresis avoids walking in place on tiny pointer jitter.
            if remaining <= (moving ? 0.75 : 4) || dt == 0 {
                moving = false
            } else {
                let step = min(remaining * (1 - exp(-7 * dt)), 1000 * dt)
                let next = clamped(CGPoint(x: current.x + dx / distance * step,
                                           y: current.y + dy / distance * step))
                moving = hypot(next.x - current.x, next.y - current.y) > 0.01
                if moving && abs(dx) > 1 { facingLeft = dx < 0 }
                center = next
            }
        }
        lastTime = time
        lastScreen = screen
        lastSize = size
        let position = center ?? restingCenter()
        return ChaseFrame(
            origin: CGPoint(x: (position.x - size.width / 2).rounded(), y: (position.y - size.height / 2).rounded()),
            isMoving: moving,
            facingLeft: facingLeft
        )
    }
}
