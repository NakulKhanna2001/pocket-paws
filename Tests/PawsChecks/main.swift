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

check("idle nap wakes quietly when the pointer moves") {
    var engine = GestureEngine()
    _ = engine.update(sample(10))
    try expect(engine.update(sample(16.1)) == .sleep)
    try expect(engine.update(sample(17, x: 90)) == .idle)
    try expect(engine.update(sample(17.1, x: 120)) == .idle)
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
    for animal in animals { try animal.validate() }
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

check("invalid side-profile artwork is rejected before rendering") {
    let animal = try Animal.bundled()[0]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(animal)) as! [String: Any]
    json["sidePixels"] = ["..."]
    try expectInvalid(JSONDecoder().decode(Animal.self, from: JSONSerialization.data(withJSONObject: json)))
}

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
