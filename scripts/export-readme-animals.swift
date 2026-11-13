import AppKit
import Foundation

// Run with: swift scripts/export-readme-animals.swift
// Generate crisp 2x README portraits from the same pixel art used in the app.
struct Portrait: Decodable {
    let id: String
    let name: String
    let palette: [String: String]
    let pixels: [String]
}

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex, radix: 16)!
    return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                   green: CGFloat((value >> 8) & 255) / 255,
                   blue: CGFloat(value & 255) / 255, alpha: 1).cgColor
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Sources/PawsCore/Animals")
let output = root.appendingPathComponent("docs/animals")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

for file in files {
    let animal = try JSONDecoder().decode(Portrait.self, from: Data(contentsOf: file))
    precondition(animal.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "Invalid animal ID")
    let width = animal.pixels.first?.count ?? 0
    precondition(width > 0 && animal.pixels.allSatisfy { $0.count == width }, "Invalid sprite grid")

    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
    context.translateBy(x: 0, y: 128)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color("EFF1E7"))
    context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 128, height: 128),
                           cornerWidth: 16, cornerHeight: 16, transform: nil))
    context.fillPath()

    let pixel = floor(128 / CGFloat(max(width, animal.pixels.count) + 8))
    let xOffset = floor((128 - CGFloat(width) * pixel) / 2)
    let yOffset = floor((128 - CGFloat(animal.pixels.count) * pixel) / 2)
    context.setShouldAntialias(false)
    for (y, row) in animal.pixels.enumerated() {
        for (x, character) in row.enumerated() where character != "." {
            context.setFillColor(color(animal.palette[String(character)]!))
            context.fill(CGRect(x: xOffset + CGFloat(x) * pixel, y: yOffset + CGFloat(y) * pixel,
                                width: pixel, height: pixel))
        }
    }
    let path = output.appendingPathComponent("\(animal.id).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    print("Exported \(animal.name): docs/animals/\(animal.id).png")
}
