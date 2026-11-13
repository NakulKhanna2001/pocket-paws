import Foundation

public struct Animal: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let species: String
    public let personality: String
    public let accent: String
    public let palette: [String: String]
    public let pixels: [String]
    /// Optional alternate artwork for forks; the desktop companion uses `pixels`.
    public let sidePixels: [String]?
    public let eyeRow: Int
    public let eyeColumns: [Int]

    public var width: Int { pixels.first?.count ?? 0 }
    public var height: Int { pixels.count }

    public func validate() throws {
        guard !id.isEmpty, !name.isEmpty, !species.isEmpty else {
            throw AnimalError.invalid("Animal identity must not be empty")
        }
        guard (8...48).contains(width), (8...48).contains(height),
              pixels.allSatisfy({ $0.count == width }) else {
            throw AnimalError.invalid("\(id): use an 8–48 pixel rectangular sprite")
        }
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        for color in Array(palette.values) + [accent] {
            guard color.count == 6, color.unicodeScalars.allSatisfy(hex.contains) else {
                throw AnimalError.invalid("\(id): colors must be six-digit RGB hex")
            }
        }
        guard palette.keys.allSatisfy({ $0.count == 1 && $0 != "." }),
              palette["o"] != nil, palette["b"] != nil, palette["e"] != nil else {
            throw AnimalError.invalid("\(id): palette needs o (outline), b (body), and e (eyes)")
        }
        if let sidePixels {
            guard sidePixels.count == height, sidePixels.allSatisfy({ $0.count == width }) else {
                throw AnimalError.invalid("\(id): side profile must match the front sprite dimensions")
            }
        }
        for row in pixels + (sidePixels ?? []) {
            for pixel in row where pixel != "." {
                guard palette[String(pixel)] != nil else {
                    throw AnimalError.invalid("\(id): missing palette color for \(pixel)")
                }
            }
        }
        guard (0..<height).contains(eyeRow), eyeColumns.count == 2,
              Set(eyeColumns).count == 2,
              eyeColumns.allSatisfy({ (1..<(width - 1)).contains($0) }),
              eyeColumns.allSatisfy({ Array(pixels[eyeRow])[$0] == "e" }) else {
            throw AnimalError.invalid("\(id): invalid eye coordinates")
        }
    }

    public static func bundled() throws -> [Animal] {
        // SwiftPM's generated accessor assumes a command-line executable. App
        // bundles must keep resources inside Contents/Resources for code signing.
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("PocketPaws_PawsCore.bundle"),
                  let bundle = Bundle(url: url),
                  let directory = bundle.url(forResource: "Animals", withExtension: nil) else {
                throw AnimalError.invalid("Packaged animal resources are missing")
            }
            return try load(from: directory)
        }
        guard let directory = Bundle.module.url(forResource: "Animals", withExtension: nil) else {
            throw AnimalError.invalid("Bundled animal directory is missing")
        }
        return try load(from: directory)
    }

    public static func load(from directory: URL) throws -> [Animal] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var ids = Set<String>()
        let animals = try urls.map { url -> Animal in
            let animal = try JSONDecoder().decode(Animal.self, from: Data(contentsOf: url))
            try animal.validate()
            guard ids.insert(animal.id).inserted else {
                throw AnimalError.invalid("Duplicate animal ID: \(animal.id)")
            }
            return animal
        }
        guard !animals.isEmpty else { throw AnimalError.invalid("No animals found") }
        return animals
    }
}

public enum AnimalError: LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
