import AppKit
import Combine
import PawsCore

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopPet {
    private let model: AppModel
    private let panel: PetPanel
    private let sprite = SpriteNSView()
    private var engine = GestureEngine()
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var screens: [NSScreen] = NSScreen.screens
    private var suspended = false
    private var stopped = false
    private var lastFrame = -1
    private var lastAnimalID = ""
    private var lastReducedMotion = false

    init(model: AppModel) {
        self.model = model
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.contentView = sprite
        panel.setAccessibilityElement(false)

        model.$enabled.removeDuplicates().sink { [weak self] _ in
            // @Published emits before assignment; defer one turn to read the new value.
            DispatchQueue.main.async { self?.updateRunningState() }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspended = true
                    self?.updateRunningState()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspended = false
                    self?.updateRunningState()
                }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.enabled, !self.suspended else { return }
                self.panel.orderFrontRegardless()
            }
        })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screens = NSScreen.screens }
        }
        updateRunningState()
    }

    private func updateRunningState() {
        guard !stopped else { return }
        if model.enabled && !suspended {
            guard timer == nil else { return }
            engine.reset()
            installMouseMonitors()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.003
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            tick()
            panel.orderFrontRegardless()
        } else {
            stopTracking()
        }
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.mouseDown(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.mouseDown(event)
            return event
        }
    }

    private func mouseDown(_ event: NSEvent) {
        engine.mappings = model.mappings
        engine.react(to: event.type == .rightMouseDown ? .rightClick : .leftClick,
                     at: ProcessInfo.processInfo.systemUptime)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let pointer = NSEvent.mouseLocation
        engine.mappings = model.mappings
        engine.napsEnabled = model.napsEnabled
        var pose = engine.update(PointerSample(x: pointer.x, y: pointer.y,
                                               buttons: NSEvent.pressedMouseButtons, time: now))
        let animal = model.animal
        let size = CGSize(width: (animal.width + 8) * model.pixelSize,
                          height: (animal.height + 8) * model.pixelSize)
        let screen = screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let reduced = model.effectiveReducedMotion
        let origin = OverlayPlacement.origin(pointer: pointer, size: size, screen: screen.frame)
        let rect = NSRect(origin: origin, size: size)
        if panel.frame != rect { panel.setFrame(rect, display: false) }
        if now < model.demoUntil { pose = model.demoPose }
        if model.activePose != pose { model.activePose = pose }
        let frame = reduced ? 0 : Int(now * 8)
        let changed = frame != lastFrame || sprite.pose != pose
            || lastAnimalID != animal.id || lastReducedMotion != reduced
        if changed {
            sprite.animal = animal
            sprite.pose = pose
            sprite.frameIndex = frame
            sprite.facingLeft = false
            sprite.reducedMotion = reduced
            sprite.needsDisplay = true
            lastFrame = frame
            lastAnimalID = animal.id
            lastReducedMotion = reduced
        }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel.orderOut(nil)
        engine.reset()
        model.activePose = .idle
    }

    func stop() {
        stopped = true
        stopTracking()
        subscriptions.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}
