import AppKit
import SwiftUI
import PawsCore

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

enum PixelPainter {
    private struct FootRegion {
        let columns: ClosedRange<Int>
        let rows: ClosedRange<Int>

        func contains(x: Int, y: Int) -> Bool { columns.contains(x) && rows.contains(y) }
    }

    /// The two separated shapes on the bottom occupied row are the feet. Include
    /// the row above and a one-pixel ankle margin, without crossing the midpoint.
    /// This keeps walking available to new animal packs without extra sprite files.
    private static func feet(in pixels: [[Character]]) -> [FootRegion] {
        guard let ground = pixels.lastIndex(where: { $0.contains { $0 != "." } }) else { return [] }
        let row = pixels[ground]
        var spans: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0...row.count {
            if x < row.count && row[x] != "." {
                if start == nil { start = x }
            } else if let first = start {
                spans.append(first...(x - 1))
                start = nil
            }
        }
        guard spans.count == 2 else { return [] }
        let middle = (spans[0].upperBound + spans[1].lowerBound) / 2
        let rows = max(0, ground - 1)...ground
        return [
            FootRegion(columns: max(0, spans[0].lowerBound - 1)...min(middle, spans[0].upperBound + 1), rows: rows),
            FootRegion(columns: max(middle + 1, spans[1].lowerBound - 1)...min(row.count - 1, spans[1].upperBound + 1), rows: rows),
        ]
    }

    /// Draw in a flipped (top-left origin) coordinate system, with integer pixels.
    static func draw(in context: CGContext, size: CGSize, animal: Animal, pose: Pose,
                     frame: Int, facingLeft: Bool = false, reducedMotion: Bool = false) {
        let p = max(1, floor(min(size.width / CGFloat(animal.width + 8), size.height / CGFloat(animal.height + 8))))
        let tick = reducedMotion ? 0 : frame
        let walking = pose == .walk && !reducedMotion
        let pixels = animal.pixels.map(Array.init)
        let feet = walking ? feet(in: pixels) : []
        let bob: CGFloat
        switch pose {
        case .walk: bob = walking ? [0, -1, -1, 0, -1, -1][tick % 6] : 0
        case .hop: bob = [0, -2, -4, -5, -4, -2][tick % 6]
        case .boop: bob = tick % 4 < 2 ? 1 : 0
        default: bob = 0
        }
        let squish: CGFloat = pose == .crouch || pose == .sleep ? 0.79 : 1
        let startX = floor((size.width - CGFloat(animal.width) * p) / 2)
        let startY = floor((size.height - CGFloat(animal.height) * p) / 2 + (1 - squish) * CGFloat(animal.height) * p + bob * p)
        let colors = animal.palette.mapValues { NSColor(hex: $0).cgColor }

        context.saveGState()
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.translateBy(x: startX, y: startY)
        if pose == .walk && facingLeft {
            context.translateBy(x: CGFloat(animal.width) * p, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        func pixel(_ x: Int, _ y: Int, _ color: CGColor, width: Int = 1, height: Int = 1) {
            context.setFillColor(color)
            let top = (CGFloat(y) * p * squish).rounded()
            let bottom = (CGFloat(y + height) * p * squish).rounded()
            context.fill(CGRect(x: CGFloat(x) * p, y: top, width: CGFloat(width) * p, height: max(1, bottom - top)))
        }
        for (y, row) in pixels.enumerated() {
            for (x, character) in row.enumerated() {
                if feet.contains(where: { $0.contains(x: x, y: y) }) { continue }
                if let color = colors[String(character)] { pixel(x, y, color) }
            }
        }

        // Six poses: plant, pass, lift; the opposite foot follows half a cycle
        // later. Cancel body bounce at the ankles so planted feet stay grounded.
        // Small alternating steps on the front-facing sprite.
        let stride = [-1, 0, 1, 1, 0, -1]
        let lift = [0, 0, -1, -1, -1, 0]
        for (index, foot) in feet.enumerated() {
            let phase = (tick + index * 3) % 6
            let dx = stride[phase]
            let dy = lift[phase] - Int(bob)
            // Stretch the ankle when the torso rises above a planted foot.
            // Otherwise a transparent row would disconnect the paw from its leg.
            if dy > 0 {
                for x in foot.columns {
                    if let color = colors[String(pixels[foot.rows.lowerBound][x])] {
                        pixel(x + dx, foot.rows.lowerBound, color, height: dy)
                    }
                }
            }
            for y in foot.rows {
                for x in foot.columns {
                    if let color = colors[String(pixels[y][x])] { pixel(x + dx, y + dy, color) }
                }
            }
        }

        let eye = colors["e"]!
        let body = colors["b"]!
        let outline = colors["o"]!
        let blink = pose == .sleep || (pose == .idle && tick % 40 >= 38)
        if blink || pose == .wink {
            for (index, x) in animal.eyeColumns.enumerated() where blink || index == 1 {
                // Faces can differ from the body (panda patches, penguin cheeks).
                let neighbor = pixels[animal.eyeRow][x - 1]
                let eyelid = colors[String(neighbor)] ?? body
                pixel(x, animal.eyeRow, eyelid)
                pixel(x - 1, animal.eyeRow + 1, eye, width: 2)
            }
        }
        if pose == .boop {
            pixel(animal.width - 7, animal.height - 10, outline, width: 3, height: 3)
            pixel(animal.width - 7, animal.height - 10, body, width: 2, height: 2)
            let sparkle = NSColor(hex: "D9A65F").cgColor
            pixel(animal.width - 2, 7, sparkle)
            pixel(animal.width - 3, 8, sparkle, width: 3)
            pixel(animal.width - 2, 9, sparkle)
        }
        if pose == .carry {
            let middle = animal.width / 2
            pixel(middle - 3, animal.height - 8, outline, width: 6, height: 5)
            pixel(middle - 2, animal.height - 7, NSColor(hex: "D6B477").cgColor, width: 4, height: 3)
            pixel(middle, animal.height - 7, NSColor(hex: "FFF0CE").cgColor, height: 3)
            pixel(middle - 4, animal.height - 7, body, width: 2, height: 2)
            pixel(middle + 2, animal.height - 7, body, width: 2, height: 2)
        }
        if pose == .sleep {
            let x = animal.width - 4
            let y = tick % 12 < 6 ? 0 : -1
            pixel(x, y, outline, width: 3)
            pixel(x + 1, y + 1, outline)
            pixel(x, y + 2, outline, width: 3)
        }
        if pose == .wink {
            let pink = NSColor(hex: "DC929E").cgColor
            pixel(animal.width - 3, 5, pink)
            pixel(animal.width - 1, 5, pink)
            pixel(animal.width - 3, 6, pink, width: 3)
            pixel(animal.width - 2, 7, pink)
        }
        context.restoreGState()
    }

    static func image(animal: Animal, size: Int, pose: Pose = .idle) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocusFlipped(true)
        if let context = NSGraphicsContext.current?.cgContext {
            draw(in: context, size: image.size, animal: animal, pose: pose, frame: 0)
        }
        image.unlockFocus()
        return image
    }
}

final class SpriteNSView: NSView {
    var animal: Animal?
    var pose: Pose = .idle
    var frameIndex = 0
    var facingLeft = false
    var reducedMotion = false
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let animal, let context = NSGraphicsContext.current?.cgContext else { return }
        PixelPainter.draw(in: context, size: bounds.size, animal: animal, pose: pose,
                          frame: frameIndex, facingLeft: facingLeft, reducedMotion: reducedMotion)
    }
}

private struct SpriteRepresentable: NSViewRepresentable {
    let animal: Animal
    let pose: Pose
    let frame: Int
    let facingLeft: Bool
    let reducedMotion: Bool

    func makeNSView(context: Context) -> SpriteNSView { SpriteNSView() }
    func updateNSView(_ view: SpriteNSView, context: Context) {
        view.animal = animal
        view.pose = pose
        view.frameIndex = frame
        view.facingLeft = facingLeft
        view.reducedMotion = reducedMotion
        view.needsDisplay = true
    }
}

struct AnimalSprite: View {
    let animal: Animal
    var pose: Pose = .idle
    var facingLeft = false
    var reducedMotion = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125, paused: reducedMotion)) { timeline in
            SpriteRepresentable(animal: animal, pose: pose,
                                frame: Int(timeline.date.timeIntervalSinceReferenceDate * 8),
                                facingLeft: facingLeft,
                                reducedMotion: reducedMotion)
        }
        .accessibilityLabel("\(animal.name) the \(animal.species), \(pose.title)")
    }
}
