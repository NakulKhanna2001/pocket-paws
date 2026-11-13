import Foundation
import CoreGraphics
import PawsCore

// Dependency-free behavioral checks: runs with Apple's command-line tools alone,
// including machines without the full Xcode XCTest/Swift Testing frameworks.
struct CheckFailure: Error, CustomStringConvertible { let description: String }

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Expectation failed",
            line: Int = #line) throws {
    if !condition() { throw CheckFailure(description: "line \(line): \(message)") }
}

func expectInvalid(_ animal: Animal) throws {
    do { try animal.validate() }
    catch { return }
    throw CheckFailure(description: "Malformed animal passed validation")
}

func sample(_ time: Double, x: Double = 100, y: Double = 100, buttons: Int = 0) -> PointerSample {
    PointerSample(x: x, y: y, buttons: buttons, time: time)
}

var passed = 0
var failed = 0
func check(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passed += 1
        print("PASS  \(name)")
    } catch {
        failed += 1
        print("FAIL  \(name): \(error)")
    }
}

check("click → hold → release produces distinct reactions") {
    var engine = GestureEngine()
    try expect(engine.update(sample(0)) == .idle)
    try expect(engine.update(sample(1, buttons: 1)) == .boop)
    try expect(engine.update(sample(1.46, buttons: 1)) == .crouch)
    try expect(engine.update(sample(1.6)) == .hop)
    try expect(engine.update(sample(2.1)) == .idle)
}

check("drag overrides hold, stays latched, and does not hop on release") {
    var engine = GestureEngine()
    _ = engine.update(sample(0))
    _ = engine.update(sample(1, buttons: 1))
    try expect(engine.update(sample(1.1, x: 108, buttons: 1)) == .carry)
    try expect(engine.update(sample(2, buttons: 1)) == .carry)
    try expect(engine.update(sample(2.1)) != .hop)
}

check("pointer jitter does not trigger a drag") {
    var engine = GestureEngine()
    _ = engine.update(sample(0))
    _ = engine.update(sample(1, buttons: 1))
    try expect(engine.update(sample(1.5, x: 102, y: 102, buttons: 1)) == .crouch)
}

check("right click respects its mapping and expires") {
    var engine = GestureEngine()
    engine.mappings[.rightClick] = .hop
    _ = engine.update(sample(0))
    try expect(engine.update(sample(1, buttons: 2)) == .hop)
    try expect(engine.update(sample(1.1)) == .hop)
    try expect(engine.update(sample(1.4)) == .idle)
}

check("brief mouse clicks between polling samples are retained") {
    var engine = GestureEngine()
    _ = engine.update(sample(0))
    engine.react(to: .rightClick, at: 0.005)
    try expect(engine.update(sample(0.016)) == .wink)
}

check("idle nap wakes with motion, facing the travel direction") {
    var engine = GestureEngine()
    _ = engine.update(sample(10))
    try expect(engine.update(sample(16.1)) == .sleep)
    try expect(engine.update(sample(17, x: 90)) == .walk)
    try expect(engine.facingLeft)
    try expect(engine.update(sample(17.1, x: 120)) == .walk)
    try expect(!engine.facingLeft)
}

check("naps can be disabled; held buttons never sleep") {
    var engine = GestureEngine()
    _ = engine.update(sample(0))
    engine.napsEnabled = false
    try expect(engine.update(sample(10)) == .idle)
    engine.napsEnabled = true
    _ = engine.update(sample(11, buttons: 2))
    try expect(engine.update(sample(30, buttons: 2)) == .idle)
}

check("reset while holding does not invent another click or hop") {
    var engine = GestureEngine()
    _ = engine.update(sample(0))
    _ = engine.update(sample(1, buttons: 1))
    engine.reset()
    try expect(engine.update(sample(10, buttons: 1)) == .idle)
    try expect(engine.update(sample(11)) == .idle)
}

check("custom mappings apply to held gestures") {
    var engine = GestureEngine()
    engine.mappings[.longPress] = .wink
    engine.mappings[.drag] = .boop
    _ = engine.update(sample(0))
    _ = engine.update(sample(1, buttons: 1))
    try expect(engine.update(sample(1.5, buttons: 1)) == .wink)
    try expect(engine.update(sample(2, x: 110, buttons: 1)) == .boop)
}

check("all bundled animals are valid with unique IDs") {
    let animals = try Animal.bundled()
    try expect(animals.count == 12)
    try expect(Set(animals.map(\.id)).count == animals.count)
    for animal in animals {
        try animal.validate()
        try expect(animal.sidePixels != nil, "\(animal.name) needs walking side-profile artwork")
        try expect(animal.sidePixels != animal.pixels, "Side profile must be distinct from front artwork")
    }
}

check("malformed sprites are rejected before rendering") {
    let animal = try Animal.bundled()[0]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(animal)) as! [String: Any]
    var rows = animal.pixels
    rows[0] = "..."
    json["pixels"] = rows
    let malformed = try JSONDecoder().decode(Animal.self, from: JSONSerialization.data(withJSONObject: json))
    try expectInvalid(malformed)
}

check("out-of-range eye coordinates are safely rejected") {
    let animal = try Animal.bundled()[0]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(animal)) as! [String: Any]
    json["eyeRow"] = 999
    let malformed = try JSONDecoder().decode(Animal.self, from: JSONSerialization.data(withJSONObject: json))
    try expectInvalid(malformed)
}

check("pet fits all edges on main, left, and upper displays") {
    let screens = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: -1920, y: -200, width: 1920, height: 1080),
        CGRect(x: 300, y: 900, width: 1200, height: 800),
    ]
    for screen in screens {
        for x in [screen.minX, screen.midX, screen.maxX - 1] {
            for y in [screen.minY, screen.midY, screen.maxY - 1] {
                let size = CGSize(width: 96, height: 96)
                let origin = OverlayPlacement.origin(pointer: CGPoint(x: x, y: y), size: size, screen: screen)
                try expect(screen.contains(CGRect(origin: origin, size: size)))
            }
        }
    }
}

check("ordinary placement leaves the click point clear") {
    let pointer = CGPoint(x: 300, y: 400)
    let size = CGSize(width: 64, height: 64)
    let origin = OverlayPlacement.origin(pointer: pointer, size: size,
                                         screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
    try expect(origin == CGPoint(x: 312, y: 328))
    try expect(!CGRect(origin: origin, size: size).contains(pointer))
}

let chaseScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let chaseSize = CGSize(width: 64, height: 64)

check("pet chases from its own position, without teleporting to the pointer") {
    var chaser = PointerChaser()
    _ = chaser.update(pointer: CGPoint(x: 200, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
    let before = chaser.center!
    let frame = chaser.update(pointer: CGPoint(x: 900, y: 400), size: chaseSize, screen: chaseScreen, time: 1.0 / 60)
    let after = chaser.center!
    try expect(frame.isMoving && !frame.facingLeft)
    try expect(after.x > before.x && after.x < 900)
    try expect(hypot(after.x - before.x, after.y - before.y) <= 1000.0 / 60 + 0.001)
}

check("direction aims toward the cursor, rather than copying its last motion") {
    var chaser = PointerChaser()
    _ = chaser.update(pointer: CGPoint(x: 200, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
    _ = chaser.update(pointer: CGPoint(x: 900, y: 400), size: chaseSize, screen: chaseScreen, time: 0.02)
    let returningCursor = chaser.update(pointer: CGPoint(x: 800, y: 400), size: chaseSize, screen: chaseScreen, time: 0.04)
    try expect(returningCursor.isMoving && !returningCursor.facingLeft, "Cursor is still to the pet's right")
    let crossedCursor = chaser.update(pointer: CGPoint(x: 50, y: 400), size: chaseSize, screen: chaseScreen, time: 0.06)
    try expect(crossedCursor.isMoving && crossedCursor.facingLeft)
}

check("pet keeps walking after the cursor stops, then settles facing forward") {
    var chaser = PointerChaser()
    _ = chaser.update(pointer: CGPoint(x: 200, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
    let target = CGPoint(x: 800, y: 400)
    var frame = chaser.update(pointer: target, size: chaseSize, screen: chaseScreen, time: 0.02)
    try expect(frame.pose(for: .idle) == .walk, "Stationary cursor must not stop a pet that is still catching up")
    try expect(frame.pose(for: .wink) == .wink, "Click reactions still take priority")
    for tick in 2...240 {
        frame = chaser.update(pointer: target, size: chaseSize, screen: chaseScreen, time: Double(tick) / 60)
    }
    try expect(!frame.isMoving && frame.pose(for: .walk) == .idle)
    let remaining = hypot(target.x - chaser.center!.x, target.y - chaser.center!.y)
    try expect(remaining >= 40 && remaining <= 41, "Pet stops outside the cursor's click point")
}

check("chasing is frame-rate independent") {
    func position(hz: Int) -> CGPoint {
        var chaser = PointerChaser()
        _ = chaser.update(pointer: CGPoint(x: 500, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
        for tick in 1...hz {
            _ = chaser.update(pointer: CGPoint(x: 650, y: 400), size: chaseSize, screen: chaseScreen, time: Double(tick) / Double(hz))
        }
        return chaser.center!
    }
    let a = position(hz: 30), b = position(hz: 120)
    try expect(hypot(a.x - b.x, a.y - b.y) < 1)
}

check("screen changes and corner targets keep the entire pet visible") {
    var chaser = PointerChaser()
    _ = chaser.update(pointer: CGPoint(x: 500, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
    let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    for (index, pointer) in [CGPoint(x: -1920, y: -200), CGPoint(x: -1, y: 879)].enumerated() {
        for tick in 0...240 {
            let frame = chaser.update(pointer: pointer, size: chaseSize, screen: left, time: Double(index * 300 + tick + 1) / 60)
            try expect(left.contains(CGRect(origin: frame.origin, size: chaseSize)))
        }
    }
}

check("reduced motion follows immediately in a still front-facing pose") {
    var chaser = PointerChaser()
    _ = chaser.update(pointer: CGPoint(x: 200, y: 400), size: chaseSize, screen: chaseScreen, time: 0)
    let frame = chaser.update(pointer: CGPoint(x: 1100, y: 400), size: chaseSize, screen: chaseScreen, time: 0.02, reducedMotion: true)
    try expect(!frame.isMoving && frame.pose(for: .walk) == .idle)
    try expect(hypot(chaser.center!.x - 1100, chaser.center!.y - 400) < 41)
}

check("invalid side-profile artwork is rejected before rendering") {
    let animal = try Animal.bundled()[0]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(animal)) as! [String: Any]
    json["sidePixels"] = ["..."]
    try expectInvalid(JSONDecoder().decode(Animal.self, from: JSONSerialization.data(withJSONObject: json)))
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
