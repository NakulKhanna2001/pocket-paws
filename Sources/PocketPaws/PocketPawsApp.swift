import AppKit
import SwiftUI
import PawsCore
import ImageIO
import UniformTypeIdentifiers

@main
enum PocketPawsApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        do {
            let animals = try Animal.bundled()
            let args = CommandLine.arguments
            if args.count == 3 && args[1] == "--export-icon" {
                try ArtExport.icon(animal: animals[0], to: URL(fileURLWithPath: args[2]))
                return
            }
            if args.count == 3 && args[1] == "--export-walk-preview" {
                try ArtExport.walkingPreview(animals: animals, to: URL(fileURLWithPath: args[2]))
                return
            }
            if args.count == 3 && args[1] == "--export-chase-preview" {
                try ArtExport.chasePreview(animal: animals[0], to: URL(fileURLWithPath: args[2]))
                return
            }
            let delegate = AppDelegate(animals: animals)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        } catch {
            fputs("Pocket Paws: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let animals: [Animal]
    private var model: AppModel!
    private var pet: DesktopPet?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var renderWindow: NSWindow?

    init(animals: [Animal]) { self.animals = animals }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--render-preview" {
            renderPreview(to: URL(fileURLWithPath: args[2]))
            return
        }
        // Launch Services normally prevents duplicates; also handle a direct binary launch.
        if !args.contains("--smoke-test"), let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        model = AppModel(animals: animals)
        pet = DesktopPet(model: model)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pocket Paws")
            button.image?.isTemplate = true
            button.toolTip = "Pocket Paws — your little desktop friend"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 432, height: PawsView.preferredHeight)
        popover.contentViewController = NSHostingController(rootView: PawsView(model: model))

        if args.contains("--smoke-test") {
            // This checks real AppKit window setup without altering saved preferences.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { exit(1) }
                guard self.statusItem?.button != nil, self.pet != nil else { exit(1) }
                print("PASS: native app launched, animals loaded, status item and desktop overlay created")
                NSApp.terminate(nil)
            }
        } else {
            showPopover()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { pet?.stop() }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func renderPreview(to url: URL) {
        let suite = "PocketPaws.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        model = AppModel(animals: animals, defaults: defaults)
        let root = PawsView(model: model, quit: {})
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 432, height: PawsView.preferredHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.center()
        window.orderFrontRegardless()
        renderWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            do {
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    throw AnimalError.invalid("Could not create preview bitmap")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw AnimalError.invalid("Could not encode preview PNG")
                }
                try data.write(to: url)
                defaults.removePersistentDomain(forName: suite)
                print("Preview saved: \(url.path)")
                NSApp.terminate(nil)
            } catch {
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }
    }
}

enum ArtExport {
    /// Exercise the same follower and renderer used on the desktop: move right,
    /// pause, move left, pause. This captures catching up and turning frontward.
    static func chasePreview(animal: Animal, to url: URL) throws {
        let count = 160
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw AnimalError.invalid("Could not create chase preview")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var chaser = PointerChaser()
        let screen = CGRect(x: 0, y: 0, width: 720, height: 180)
        let petSize = CGSize(width: 64, height: 64)
        for frame in 0..<count {
            let time = Double(frame) / 20
            let x: Double
            switch time {
            case ..<0.4: x = 100
            case ..<2.4: x = 100 + (time - 0.4) * 260
            case ..<4: x = 620
            case ..<6: x = 620 - (time - 4) * 260
            default: x = 100
            }
            let pointer = CGPoint(x: x, y: 95)
            let follow = chaser.update(pointer: pointer, size: petSize, screen: screen, time: time)
            let pose = follow.pose(for: .idle)
            let image = NSImage(size: NSSize(width: 720, height: 240))
            image.lockFocusFlipped(true)
            NSColor(hex: "FBFAF5").setFill()
            NSRect(x: 0, y: 0, width: 720, height: 240).fill()
            NSColor(hex: "EFF1E7").setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: 12, width: 696, height: 186), xRadius: 14, yRadius: 14).fill()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.translateBy(x: follow.origin.x, y: 12 + screen.height - follow.origin.y - petSize.height)
                PixelPainter.draw(in: context, size: petSize, animal: animal, pose: pose,
                                  frame: Int(time * 8), facingLeft: follow.facingLeft)
                context.restoreGState()
            }
            let cursor = NSBezierPath()
            let tip = CGPoint(x: pointer.x, y: 12 + screen.height - pointer.y)
            cursor.move(to: tip)
            for point in [CGPoint(x: 0, y: 17), CGPoint(x: 4, y: 13), CGPoint(x: 8, y: 21), CGPoint(x: 11, y: 19), CGPoint(x: 7, y: 12), CGPoint(x: 15, y: 12)] {
                cursor.line(to: CGPoint(x: tip.x + point.x, y: tip.y + point.y))
            }
            cursor.close()
            NSColor.white.setStroke()
            cursor.lineWidth = 3
            cursor.stroke()
            NSColor(hex: "35483E").setFill()
            cursor.fill()
            let label = (follow.isMoving ? "Chasing your cursor · side profile" : "Caught up · facing you") as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor(hex: "557A5B")]
            label.draw(at: NSPoint(x: 360 - label.size(withAttributes: attributes).width / 2, y: 210), withAttributes: attributes)
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let cgImage = bitmap.cgImage else {
                throw AnimalError.invalid("Could not render chase frame")
            }
            CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw AnimalError.invalid("Could not save chase preview") }
        print("Chase preview saved: \(url.path)")
    }

    /// Export the actual desktop renderer's six walking poses as a looping GIF.
    static func walkingPreview(animals: [Animal], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 6, nil) else {
            throw AnimalError.invalid("Could not create walking preview")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let size = NSSize(width: 960, height: ((animals.count + 3) / 4) * 240)
        for frame in 0..<6 {
            let image = NSImage(size: size)
            image.lockFocusFlipped(true)
            NSColor(hex: "FBFAF5").setFill()
            NSRect(origin: .zero, size: size).fill()
            for (index, animal) in animals.enumerated() {
                let x = CGFloat(index % 4) * 240
                let y = CGFloat(index / 4) * 240
                NSColor(hex: "EFF1E7").setFill()
                NSBezierPath(roundedRect: NSRect(x: x + 10, y: y + 8, width: 220, height: 224), xRadius: 16, yRadius: 16).fill()
                if let context = NSGraphicsContext.current?.cgContext {
                    context.saveGState()
                    context.translateBy(x: x + 24, y: y + 4)
                    PixelPainter.draw(in: context, size: CGSize(width: 192, height: 192), animal: animal, pose: .walk, frame: frame)
                    context.restoreGState()
                }
                let label = "\(animal.name) · \(animal.species)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor(hex: "35483E")]
                let labelSize = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: x + 120 - labelSize.width / 2, y: y + 202), withAttributes: attributes)
            }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let cgImage = bitmap.cgImage else {
                throw AnimalError.invalid("Could not render walking preview frame \(frame)")
            }
            let timing = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.125, kCGImagePropertyGIFUnclampedDelayTime: 0.125]]
            CGImageDestinationAddImage(destination, cgImage, timing as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw AnimalError.invalid("Could not save walking preview") }
        print("Walking preview saved: \(url.path)")
    }

    static func icon(animal: Animal, to url: URL) throws {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        NSColor(hex: "E8EDDE").setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            PixelPainter.draw(in: context, size: size, animal: animal, pose: .idle, frame: 0)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AnimalError.invalid("Could not encode app icon")
        }
        try png.write(to: url)
    }
}
