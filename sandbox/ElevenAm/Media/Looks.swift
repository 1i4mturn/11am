import Foundation

struct Look: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var settings: GradeSettings
    var builtIn = false
}

/// Looks shared by Photo and Video: built-in ones, ones you save, ones Johnny writes, and imported .cube LUTs.
/// Stored as plain files in Application Support/11am-sandbox/Looks, so they're easy to share or edit.
@MainActor
final class LookLibrary: ObservableObject {
    @Published private(set) var userLooks: [Look] = []
    @Published private(set) var luts: [String] = []

    private var lutCache: [String: CubeLUT] = [:]

    static let builtIns: [Look] = {
        func look(_ name: String, _ change: (inout GradeSettings) -> Void) -> Look {
            var s = GradeSettings()
            change(&s)
            return Look(name: name, settings: s, builtIn: true)
        }
        return [
            look("Natural") { s in
                s.vibrance = 0.15
                s.contrast = 0.1
            },
            look("Vellum") { s in
                s.fade = 0.45
                s.contrast = -0.1
                s.saturation = -0.2
                s.temperature = 0.1
                s.gain = ColorWheel(hue: 40, amount: 0.12, luma: 0)
                s.grain = 0.15
            },
            look("Film") { s in
                s.contrast = 0.2
                s.fade = 0.3
                s.saturation = -0.1
                s.lift = ColorWheel(hue: 190, amount: 0.25, luma: 0)
                s.gain = ColorWheel(hue: 35, amount: 0.2, luma: 0)
                s.grain = 0.3
            },
            look("Teal & orange") { s in
                s.contrast = 0.15
                s.vibrance = 0.2
                s.lift = ColorWheel(hue: 195, amount: 0.35, luma: 0)
                s.gain = ColorWheel(hue: 30, amount: 0.3, luma: 0)
                s.hsl[1] = HSLBand(hue: 0, saturation: 0.15, luminance: 0.1)
                s.hsl[4] = HSLBand(hue: 0.2, saturation: 0.2, luminance: 0)
            },
            look("Moody") { s in
                s.exposure = -0.3
                s.contrast = 0.25
                s.shadows = -0.15
                s.saturation = -0.3
                s.lift = ColorWheel(hue: 220, amount: 0.2, luma: -0.05)
                s.vignette = 0.35
            },
            look("Bright") { s in
                s.exposure = 0.3
                s.shadows = 0.3
                s.highlights = -0.3
                s.vibrance = 0.25
            },
            look("Warm") { s in
                s.temperature = 0.35
                s.tint = 0.05
                s.vibrance = 0.1
            },
            look("Cool") { s in
                s.temperature = -0.3
                s.vibrance = 0.05
            },
            look("Mono") { s in
                s.saturation = -1
                s.contrast = 0.25
                s.grain = 0.2
            },
        ]
    }()

    var all: [Look] { LookLibrary.builtIns + userLooks }

    private var folder: URL { JSONStore.folder.appendingPathComponent("Looks", isDirectory: true) }
    private var lutFolder: URL { folder.appendingPathComponent("LUTs", isDirectory: true) }

    init() {
        load()
    }

    func load() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: lutFolder, withIntermediateDirectories: true)
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        userLooks = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Look? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                if let look = try? JSONDecoder().decode(Look.self, from: data) { return Look(name: look.name, settings: look.settings) }
                // A bare settings file (for example one written by hand) is a look named after the file.
                if let settings = try? JSONDecoder().decode(GradeSettings.self, from: data) {
                    return Look(name: url.deletingPathExtension().lastPathComponent, settings: settings)
                }
                return nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        luts = ((try? fileManager.contentsOfDirectory(at: lutFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "cube" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    @discardableResult
    func save(_ settings: GradeSettings, as name: String) -> Look {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let look = Look(name: clean.isEmpty ? "My look" : clean, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(look) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appendingPathComponent(LookLibrary.fileName(look.name) + ".json"), options: .atomic)
        }
        load()
        return look
    }

    func delete(_ look: Look) {
        guard !look.builtIn else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(LookLibrary.fileName(look.name) + ".json"))
        load()
    }

    /// Copies a .cube file into the library after checking it reads.
    func importLUT(from url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), CubeLUT.parse(text) != nil else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let destination = lutFolder.appendingPathComponent(LookLibrary.fileName(name) + ".cube")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: url, to: destination)
        lutCache[name] = nil
        load()
        return LookLibrary.fileName(name)
    }

    func lut(named name: String?) -> CubeLUT? {
        guard let name else { return nil }
        if let cached = lutCache[name] { return cached }
        let url = lutFolder.appendingPathComponent(name + ".cube")
        guard let text = try? String(contentsOf: url, encoding: .utf8), let lut = CubeLUT.parse(text) else { return nil }
        lutCache[name] = lut
        return lut
    }

    func renderer(for settings: GradeSettings) -> GradeRenderer {
        GradeRenderer(settings: settings, lut: lut(named: settings.lutName))
    }

    private static func fileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_&"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}

/// Copy a grade from one photo or clip, paste it onto another.
@MainActor
enum GradeClipboard {
    static var settings: GradeSettings?
}
