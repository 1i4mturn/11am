import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A design as listed down the side.
struct DesignEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var size: CanvasSize
    var modified: Date
}

/// Robert's designs: canvas documents saved on this Mac, the brand kit they use, and the editor's controller.
@MainActor
final class DesignStudio: ObservableObject {
    @Published private(set) var entries: [DesignEntry] = []
    @Published private(set) var currentID: UUID?
    /// Every design, for the thumbnails down the side.
    @Published private(set) var previews: [UUID: CanvasDocument] = [:]
    @Published var brand: CanvasBrand { didSet { JSONStore.save(brand, to: "canvas-brand") } }
    @Published var notice: String?
    @Published var makeRun: BrainRun?
    @Published var tab: DesignView.DesignTab = .designs

    let root = JSONStore.folder.appendingPathComponent("Designs", isDirectory: true)
    let assets: CanvasAssetStore
    let controller: CanvasController
    private let brain: Brain
    private var saveTask: Task<Void, Never>?

    init(brain: Brain) {
        self.brain = brain
        let assets = CanvasAssetStore(folder: JSONStore.folder.appendingPathComponent("Designs/Assets", isDirectory: true))
        self.assets = assets
        self.brand = JSONStore.load(CanvasBrand.self, from: "canvas-brand") ?? CanvasBrand()
        controller = CanvasController(document: CanvasDocument(name: "Untitled", size: CanvasSize(width: 1080, height: 1080)), assets: assets)
        controller.onChange = { [weak self] document in self?.scheduleSave(document) }
    }

    // MARK: Files

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [DesignEntry] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let document = try? Self.decoder.decode(CanvasDocument.self, from: data) else { continue }
            found.append(DesignEntry(id: document.id, name: document.name, size: document.size, modified: document.modified))
            previews[document.id] = document
        }
        entries = found.sorted { $0.modified > $1.modified }
        if entries.isEmpty && !UserDefaults.standard.bool(forKey: "designs.seeded") {
            UserDefaults.standard.set(true, forKey: "designs.seeded")
            seed()
        }
        if currentID == nil, let first = entries.first { open(first.id) }
    }

    private func seed() {
        let samples: [(CanvasTemplate, String, CanvasTemplate.Copy)] = [
            (.announcement, "instagram", CanvasTemplate.Copy()),
            (.bigNumber, "linkedin", CanvasTemplate.Copy(headline: "people at Acme use 11am every day", number: "40")),
            (.event, "story", CanvasTemplate.Copy(headline: "Founder breakfast", detail: "Thursday 14 November, 7:30am\nLune Croissanterie, Fitzroy", kicker: "You're invited", link: "https://11am.app/breakfast")),
            (.quote, "portrait", CanvasTemplate.Copy(headline: "It gave me back a day a week.", detail: "Priya, Head of Ops at Acme")),
        ]
        for (template, preset, copy) in samples.reversed() {
            guard let size = CanvasPreset.named(preset) else { continue }
            var document = template.document(size, brand: brand, copy: copy)
            document.modified = Date()
            write(document)
        }
        entries.sort { $0.modified > $1.modified }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func url(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json") }

    private func write(_ document: CanvasDocument) {
        if let data = try? Self.encoder.encode(document) { try? data.write(to: url(document.id), options: .atomic) }
        previews[document.id] = document
        let entry = DesignEntry(id: document.id, name: document.name, size: document.size, modified: document.modified)
        if let index = entries.firstIndex(where: { $0.id == document.id }) { entries[index] = entry } else { entries.insert(entry, at: 0) }
    }

    private func scheduleSave(_ document: CanvasDocument) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            self?.write(document)
        }
    }

    func flushSave() {
        saveTask?.cancel()
        if currentID != nil { write(controller.document) }
    }

    func document(_ id: UUID) -> CanvasDocument? {
        guard let data = try? Data(contentsOf: url(id)) else { return nil }
        return try? Self.decoder.decode(CanvasDocument.self, from: data)
    }

    func open(_ id: UUID) {
        flushSave()
        guard let document = self.document(id) else { return }
        currentID = id
        controller.load(document)
    }

    func open(named name: String) {
        if let entry = entries.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { open(entry.id) }
    }

    func create(_ template: CanvasTemplate, preset: CanvasPreset) {
        flushSave()
        var document = template.document(preset, brand: brand)
        document.modified = Date()
        write(document)
        currentID = document.id
        controller.load(document)
    }

    func duplicate(_ id: UUID) {
        guard var document = self.document(id) else { return }
        document.id = UUID()
        document.name += " copy"
        document.modified = Date()
        write(document)
        open(document.id)
    }

    func rename(_ id: UUID, to name: String) {
        let found: CanvasDocument? = id == currentID ? controller.document : self.document(id)
        guard var document = found, !name.isEmpty else { return }
        document.name = name
        if id == currentID {
            controller.change { $0.name = name }
        }
        write(document)
    }

    func delete(_ id: UUID) {
        NSWorkspace.shared.recycle([url(id)]) { _, _ in }
        entries.removeAll { $0.id == id }
        if currentID == id {
            currentID = nil
            if let first = entries.first { open(first.id) }
        }
    }

    /// The current design at another size, as a new design (Canva's magic resize).
    func resize(to preset: CanvasPreset) {
        flushSave()
        let resized = CanvasEdit.resized(controller.document, to: preset.size, name: "\(controller.document.name.components(separatedBy: " · ").first ?? "Design") · \(preset.name)")
        write(resized)
        currentID = resized.id
        controller.load(resized)
        notice = "Made a \(preset.name) version. Check the text still sits well."
    }

    /// Recolours the current design with the brand kit's colours and fonts by what each layer is for.
    func applyBrand() {
        let brand = brand
        controller.change { document in
            for index in document.layers.indices {
                if case .text(let text, var style) = document.layers[index].content {
                    let heading = ["title", "number", "quote", "mark"].contains(document.layers[index].role ?? "")
                    style.font = heading ? brand.headingFont : brand.bodyFont
                    if document.layers[index].role == "number" || document.layers[index].role == "kicker" || document.layers[index].role == "mark" { style.color = brand.accent }
                    document.layers[index].content = .text(text, style)
                }
                if document.layers[index].role == "accent" || document.layers[index].role == "logo" { document.layers[index].fill = .solid(brand.accent) }
            }
        }
    }

    // MARK: Export

    enum Export: String, CaseIterable, Identifiable {
        case png, png2x, jpeg, pdf, svg
        var id: String { rawValue }
        var title: String {
            switch self {
            case .png: return "PNG"
            case .png2x: return "PNG at 2×"
            case .jpeg: return "JPEG"
            case .pdf: return "PDF"
            case .svg: return "SVG"
            }
        }
        var fileExtension: String {
            switch self {
            case .png, .png2x: return "png"
            case .jpeg: return "jpg"
            case .pdf: return "pdf"
            case .svg: return "svg"
            }
        }
    }

    func data(_ kind: Export, for document: CanvasDocument) -> Data? {
        let images: CanvasImages = { [assets] id in assets.image(id) }
        switch kind {
        case .png: return CanvasRenderer.png(document, images: images)
        case .png2x: return CanvasRenderer.png(document, scale: 2, images: images)
        case .jpeg: return CanvasRenderer.jpeg(document, images: images)
        case .pdf: return CanvasRenderer.pdf([document], images: images)
        case .svg: return Data(CanvasRenderer.svg(document, imageData: { [assets] id in assets.data(id) }).utf8)
        }
    }

    func export(_ kind: Export) {
        flushSave()
        let document = controller.document
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.name.replacingOccurrences(of: "/", with: "-") + "." + kind.fileExtension
        if let type = UTType(filenameExtension: kind.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = data(kind, for: document) else {
            notice = "That couldn't be exported."
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent)."
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func addPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) { controller.addImage(data) }
        }
    }

    /// Lifts the subject of the selected picture off its background, on this Mac.
    func removeBackground() {
        guard let layer = controller.single, case .image(let asset, let fit) = layer.content, let image = assets.image(asset) else { return }
        notice = "Robert is cutting out the subject…"
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = try? ImageTools.liftSubject(from: image)
            await MainActor.run {
                guard let self else { return }
                guard let result, let id = self.assets.add(image: result) else {
                    self.notice = "Robert couldn't find a clear subject in that picture."
                    return
                }
                self.controller.update([layer.id]) { $0.content = .image(id, fit) }
                self.notice = "Background removed. Undo brings it back."
            }
        }
    }

    // MARK: Robert

    /// "Make me a graphic for…": Robert writes the words and picks the template; the layout is the canvas's.
    func make(from request: String, preset: CanvasPreset) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let system = """
        You are Robert, the design agent inside 11am. Write the words for one social graphic. Reply with exactly five lines:
        TEMPLATE: one of announcement, quote, bigNumber, event, hiring, launch
        KICKER: two or three words
        HEADLINE: at most nine words
        DETAIL: at most eighteen words (for a quote, who said it)
        NUMBER: a short number if the graphic is about one, otherwise none
        Plain words, no hashtags, no emoji.
        """
        let run = brain.run(BrainRequest(system: system, prompt: "The graphic is for: \(request)", weight: .quick))
        makeRun = run
        Task { [weak self] in
            await run.finished()
            guard let self, case .done = run.status else { return }
            let fields = Self.fields(run.text)
            let template = CanvasTemplate(rawValue: fields["TEMPLATE"] ?? "") ?? .announcement
            var copy = CanvasTemplate.Copy()
            copy.kicker = fields["KICKER"] ?? copy.kicker
            copy.headline = fields["HEADLINE"] ?? request
            copy.detail = fields["DETAIL"] ?? ""
            if let number = fields["NUMBER"], number.lowercased() != "none" { copy.number = number }
            self.flushSave()
            var document = template.document(preset, brand: self.brand, copy: copy)
            document.name = copy.headline
            document.modified = Date()
            self.write(document)
            self.currentID = document.id
            self.controller.load(document)
            self.makeRun = nil
        }
    }

    static func fields(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty { result[key] = value }
        }
        return result
    }
}

extension CanvasColor {
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent), alpha: Double(ns.alphaComponent))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}
