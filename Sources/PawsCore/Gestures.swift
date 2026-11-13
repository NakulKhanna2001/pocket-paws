import Foundation

public enum Pose: String, CaseIterable, Codable, Identifiable {
    case idle, walk, boop, wink, crouch, hop, carry, sleep
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .idle: return "Blink"
        case .walk: return "Walk"
        case .boop: return "Paw tap"
        case .wink: return "Wink"
        case .crouch: return "Crouch"
        case .hop: return "Happy hop"
        case .carry: return "Grab"
        case .sleep: return "Nap"
        }
    }

    public static let reactions: [Pose] = [.boop, .wink, .crouch, .hop, .carry]
}

public enum Gesture: String, CaseIterable, Codable, Identifiable {
    case leftClick, rightClick, longPress, drag
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftClick: return "Left click"
        case .rightClick: return "Right click"
        case .longPress: return "Press & hold"
        case .drag: return "Drag"
        }
    }

    public var detail: String {
        switch self {
        case .leftClick: return "A little hello"
        case .rightClick: return "A cheeky reaction"
        case .longPress: return "Hold for 0.45 seconds"
        case .drag: return "Your tiny helping paw"
        }
    }

    public var defaultPose: Pose {
        switch self {
        case .leftClick: return .boop
        case .rightClick: return .wink
        case .longPress: return .crouch
        case .drag: return .carry
        }
    }
}

public struct PointerSample {
    public var x: Double
    public var y: Double
    public var buttons: Int
    public var time: TimeInterval

    public init(x: Double, y: Double, buttons: Int, time: TimeInterval) {
        self.x = x
        self.y = y
        self.buttons = buttons
        self.time = time
    }
}

/// A deterministic state machine, independent of macOS event delivery and drawing.
/// The tracker polls pointer position and button state; mouse-down monitors also
/// deliver brief clicks that could otherwise fit entirely between two samples.
public struct GestureEngine {
    public var mappings: [Gesture: Pose] = [:]
    public var napsEnabled = true
    public private(set) var facingLeft = false
    private var previous: PointerSample?
    private var lastActivity: TimeInterval = 0
    private var lastMovement: TimeInterval = -.infinity
    private var pressStarted: TimeInterval?
    private var pressOrigin: (Double, Double)?
    private var dragging = false
    private var transient: (Pose, TimeInterval)?

    public init() {}

    public mutating func reset() {
        previous = nil
        pressStarted = nil
        pressOrigin = nil
        transient = nil
        dragging = false
        lastMovement = -.infinity
    }

    public mutating func react(to gesture: Gesture, at time: TimeInterval) {
        transient = (mappings[gesture] ?? gesture.defaultPose, time + 0.30)
        lastActivity = time
    }

    public mutating func update(_ sample: PointerSample) -> Pose {
        guard let old = previous else {
            previous = sample
            lastActivity = sample.time
            // Starting while a button is already held must not invent a click.
            return .idle
        }
        let dx = sample.x - old.x
        let dy = sample.y - old.y
        let moving = hypot(dx, dy) > 0.25
        if moving {
            lastActivity = sample.time
            lastMovement = sample.time
            if abs(dx) > 0.5 { facingLeft = dx < 0 }
        }

        let leftDown = sample.buttons & 1 != 0
        let wasLeftDown = old.buttons & 1 != 0
        if leftDown && !wasLeftDown {
            pressStarted = sample.time
            pressOrigin = (sample.x, sample.y)
            dragging = false
            react(to: .leftClick, at: sample.time)
        }
        if sample.buttons & 2 != 0 && old.buttons & 2 == 0 {
            react(to: .rightClick, at: sample.time)
        }
        if !leftDown && wasLeftDown {
            if let start = pressStarted, !dragging, sample.time - start >= 0.45 {
                transient = (.hop, sample.time + 0.36)
            }
            pressStarted = nil
            pressOrigin = nil
            dragging = false
            lastActivity = sample.time
        }
        previous = sample

        if leftDown, let start = pressStarted, let origin = pressOrigin {
            if hypot(sample.x - origin.0, sample.y - origin.1) >= 4 { dragging = true }
            lastActivity = sample.time
            if dragging { return mappings[.drag] ?? Gesture.drag.defaultPose }
            if sample.time - start >= 0.45 {
                return mappings[.longPress] ?? Gesture.longPress.defaultPose
            }
        }
        if sample.buttons != 0 { lastActivity = sample.time }
        if let reaction = transient, sample.time < reaction.1 { return reaction.0 }
        if sample.time - lastMovement < 0.12 { return .walk }
        if napsEnabled && sample.time - lastActivity >= 6 { return .sleep }
        return .idle
    }
}
