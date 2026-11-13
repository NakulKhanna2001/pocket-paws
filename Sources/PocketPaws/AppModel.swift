import AppKit
import Combine
import PawsCore

@MainActor
final class AppModel: ObservableObject {
    let animals: [Animal]
    private let defaults: UserDefaults

    @Published var selectedID: String { didSet { defaults.set(selectedID, forKey: "animal") } }
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var pixelSize: Int { didSet { defaults.set(pixelSize, forKey: "pixelSize") } }
    @Published var napsEnabled: Bool { didSet { defaults.set(napsEnabled, forKey: "naps") } }
    @Published var reducedMotion: Bool { didSet { defaults.set(reducedMotion, forKey: "reducedMotion") } }
    @Published var mappings: [Gesture: Pose] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: mappings.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: "mappings")
        }
    }
    @Published var activePose: Pose = .idle
    @Published var demoPose: Pose = .idle
    @Published var demoUntil: TimeInterval = 0

    var animal: Animal { animals.first { $0.id == selectedID } ?? animals[0] }
    var effectiveReducedMotion: Bool { reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(animals: [Animal], defaults: UserDefaults = .standard) {
        precondition(!animals.isEmpty)
        self.animals = animals
        self.defaults = defaults
        selectedID = defaults.string(forKey: "animal") ?? animals[0].id
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        let savedSize = defaults.integer(forKey: "pixelSize")
        pixelSize = (1...3).contains(savedSize) ? savedSize : 2
        napsEnabled = defaults.object(forKey: "naps") as? Bool ?? true
        reducedMotion = defaults.bool(forKey: "reducedMotion")
        let stored = defaults.dictionary(forKey: "mappings") as? [String: String] ?? [:]
        mappings = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { gesture in
            let saved = stored[gesture.rawValue].flatMap(Pose.init(rawValue:))
            return (gesture, saved.flatMap { Pose.reactions.contains($0) ? $0 : nil } ?? gesture.defaultPose)
        })
    }

    func preview(_ pose: Pose) {
        demoPose = pose
        demoUntil = ProcessInfo.processInfo.systemUptime + 1.2
        if !enabled {
            activePose = pose
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, !self.enabled,
                      ProcessInfo.processInfo.systemUptime >= self.demoUntil else { return }
                self.activePose = .idle
            }
        }
    }

    func resetMappings() {
        mappings = Dictionary(uniqueKeysWithValues: Gesture.allCases.map { ($0, $0.defaultPose) })
    }
}
