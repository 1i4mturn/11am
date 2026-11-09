import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WriteDocument: Identifiable, Equatable {
    let id: UUID
    var text: String
    var modified: Date

    var title: String {
        let title = MarkdownInfo.title(text)
        return title.isEmpty ? "Untitled" : String(title.prefix(60))
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

/// A saved copy of a document, to look back at or restore.
struct WriteVersion: Identifiable, Equatable {
    let id: String
    let date: Date
    var name: String?
    let url: URL
}

enum WriteExport: String, CaseIterable, Identifiable {
    case pdf, docx, markdown, html, text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF…"
        case .docx: return "Word (.docx)…"
        case .markdown: return "Markdown…"
        case .html: return "Web page (.html)…"
        case .text: return "Plain text…"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .docx: return "docx"
        case .markdown: return "md"
        case .html: return "html"
        case .text: return "txt"
        }
    }
}

enum WriteAction: String, CaseIterable, Identifiable {
    case voice, shorter, clearer, warmer, grammar, expand, continueWriting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "In my voice"
        case .shorter: return "Shorter"
        case .clearer: return "Clearer"
        case .warmer: return "Warmer"
        case .grammar: return "Fix grammar"
        case .expand: return "Expand"
        case .continueWriting: return "Continue"
        }
    }

    var symbol: String {
        switch self {
        case .voice: return "person.wave.2"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .clearer: return "sparkles"
        case .warmer: return "sun.max"
        case .grammar: return "checkmark.circle"
        case .expand: return "text.badge.plus"
        case .continueWriting: return "text.append"
        }
    }

    var instruction: String {
        switch self {
        case .voice: return "Rewrite this so it sounds like the user wrote it. Keep the meaning and every fact."
        case .shorter: return "Rewrite this to be about half as long. Keep every fact and every ask."
        case .clearer: return "Rewrite this to be clearer and easier to scan: plain words, short sentences."
        case .warmer: return "Rewrite this to be warmer and friendlier, without gushing."
        case .grammar: return "Fix spelling, grammar and punctuation only. Change nothing else."
        case .expand: return "Turn these notes or bullet points into clear paragraphs. Keep every fact; add none."
        case .continueWriting: return "Continue this text with one or two paragraphs that follow on naturally."
        }
    }
}

/// A change William proposes. Nothing touches the document until it's accepted.
struct WriteSuggestion: Identifiable {
    let id = UUID()
    let action: WriteAction
    let documentID: UUID
    /// What gets replaced. Length 0 means an insertion (Continue).
    let range: NSRange
    let original: String
    let run: BrainRun
}

/// William's app: documents are Markdown files on this Mac, edited as formatted pages, with suggestions in your voice,
/// versions, templates, and Word, PDF, HTML and Markdown in and out.
@MainActor
final class WriteModel: ObservableObject {
    @Published private(set) var documents: [WriteDocument] = []
    @Published var selectedID: UUID?
    @Published private(set) var suggestion: WriteSuggestion?
    @Published var notice: String?
    /// James brings citations and the reference list up to date before a document leaves 11am.
    var formatCitations: ((String) -> String)?
    @Published var pageSetup: PageSetup { didSet { savePageSetup() } }

    static let williamSystem = """
    You are William, the writing agent inside 11am. You edit the user's writing in their own voice. \
    The text is Markdown: keep its headings, lists, links and emphasis unless asked to change them. \
    Return only the new text: no preamble, no quotation marks around it, no notes about what you changed.
    """

    private let brain: Brain
    private let voice: VoiceProfile
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    init(brain: Brain, voice: VoiceProfile) {
        self.brain = brain
        self.voice = voice
        if let data = UserDefaults.standard.data(forKey: "write.pageSetup"), let saved = try? JSONDecoder().decode(PageSetup.self, from: data) {
            pageSetup = saved
        } else {
            pageSetup = PageSetup()
        }
    }

    /// Documents, their pictures (attachments/<id>/) and their versions (.versions/<id>/).
    var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("11am-sandbox/Write", isDirectory: true)
    }

    var selected: WriteDocument? { documents.first { $0.id == selectedID } }

    // MARK: Documents

    func load() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        documents = urls.compactMap { url -> WriteDocument? in
            guard url.pathExtension == "md",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return WriteDocument(id: id, text: text, modified: modified)
        }
        .sorted { $0.modified > $1.modified }
        if documents.isEmpty {
            documents = WriteSamples.documents()
            for document in documents { write(document) }
        }
        selectedID = documents.first?.id
    }

    func newDocument(template: DocTemplate? = nil) {
        let document = WriteDocument(id: UUID(), text: template?.markdown ?? "", modified: Date())
        documents.insert(document, at: 0)
        selectedID = document.id
        write(document)
    }

    /// Other agents hand finished text to William (a research report, a proposal).
    func addDocument(text: String) {
        let document = WriteDocument(id: UUID(), text: text, modified: Date())
        documents.insert(document, at: 0)
        selectedID = document.id
        write(document)
    }

    func duplicate(_ id: UUID) {
        guard let original = documents.first(where: { $0.id == id }) else { return }
        let copy = WriteDocument(id: UUID(), text: original.text, modified: Date())
        copyAttachments(from: original.id, to: copy.id)
        documents.insert(copy, at: 0)
        selectedID = copy.id
        write(copy)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        try? FileManager.default.removeItem(at: attachmentsFolder(for: id))
        try? FileManager.default.removeItem(at: versionsFolder(for: id))
        documents.removeAll { $0.id == id }
        if selectedID == id { selectedID = documents.first?.id }
        if suggestion?.documentID == id { suggestion = nil }
    }

    func update(_ id: UUID, text: String) {
        guard let index = documents.firstIndex(where: { $0.id == id }), documents[index].text != text else { return }
        documents[index].text = text
        documents[index].modified = Date()
        let document = documents[index]
        // Save shortly after typing pauses.
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self.write(document)
            self.snapshotIfDue(document)
        }
    }

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).md")
    }

    private func write(_ document: WriteDocument) {
        try? document.text.write(to: url(for: document.id), atomically: true, encoding: .utf8)
    }

    // MARK: Attachments

    func attachmentsFolder(for id: UUID) -> URL {
        folder.appendingPathComponent("attachments/\(id.uuidString)", isDirectory: true)
    }

    /// Stores a pasted or dropped file next to the document and returns the Markdown source for it.
    func attach(_ data: Data, named name: String, to id: UUID) -> String? {
        let destination = attachmentsFolder(for: id)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = Self.uniqueName(name, in: destination)
        do {
            try data.write(to: destination.appendingPathComponent(file))
        } catch {
            notice = "Couldn't keep \(name): \(error.localizedDescription)"
            return nil
        }
        let relative = "attachments/\(id.uuidString)/\(file)"
        return relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
    }

    private func copyAttachments(from source: UUID, to destination: UUID) {
        let from = attachmentsFolder(for: source)
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        try? FileManager.default.createDirectory(at: attachmentsFolder(for: destination).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: from, to: attachmentsFolder(for: destination))
        if let index = documents.firstIndex(where: { $0.id == destination }) {
            documents[index].text = documents[index].text.replacingOccurrences(of: source.uuidString, with: destination.uuidString)
        }
    }

    static func uniqueName(_ name: String, in folder: URL) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = (cleaned as NSString).deletingPathExtension
        let ext = (cleaned as NSString).pathExtension
        var candidate = cleaned.isEmpty ? "file" : cleaned
        var number = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            number += 1
        }
        return candidate
    }

    // MARK: Versions

    private func versionsFolder(for id: UUID) -> URL {
        folder.appendingPathComponent(".versions/\(id.uuidString)", isDirectory: true)
    }

    private var versionNames: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: "write.versionNames") as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "write.versionNames") }
    }

    func versions(for id: UUID) -> [WriteVersion] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: versionsFolder(for: id), includingPropertiesForKeys: nil)) ?? []
        let names = versionNames
        return urls.compactMap { url -> WriteVersion? in
            guard url.pathExtension == "md", let seconds = Double(url.deletingPathExtension().lastPathComponent) else { return nil }
            let key = "\(id.uuidString)/\(url.lastPathComponent)"
            return WriteVersion(id: key, date: Date(timeIntervalSince1970: seconds), name: names[key], url: url)
        }
        .sorted { $0.date > $1.date }
    }

    /// Keeps a copy now and then while you write: at most one every 15 minutes, and only when something changed.
    private func snapshotIfDue(_ document: WriteDocument) {
        let last = versions(for: document.id).first
        if let last, Date().timeIntervalSince(last.date) < 15 * 60 { return }
        if let last, (try? String(contentsOf: last.url, encoding: .utf8)) == document.text { return }
        saveVersion(of: document, named: nil)
    }

    func saveVersion(named name: String?) {
        guard let document = selected else { return }
        saveVersion(of: document, named: name)
        notice = "Version saved."
    }

    private func saveVersion(of document: WriteDocument, named name: String?) {
        let destination = versionsFolder(for: document.id)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = "\(Int(Date().timeIntervalSince1970)).md"
        try? document.text.write(to: destination.appendingPathComponent(file), atomically: true, encoding: .utf8)
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            var names = versionNames
            names["\(document.id.uuidString)/\(file)"] = name
            versionNames = names
        }
        objectWillChange.send()
    }

    func restore(_ version: WriteVersion) {
        guard let document = selected, let text = try? String(contentsOf: version.url, encoding: .utf8) else { return }
        saveVersion(of: document, named: "Before restoring")
        update(document.id, text: text)
        notice = "Restored the version from \(version.date.formatted(date: .abbreviated, time: .shortened)). The text before it is kept as a version too."
    }

    // MARK: Import and export

    static var importTypes: [UTType] {
        DocImport.fileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    func importFiles(_ urls: [URL]) {
        var imported = 0
        for url in urls {
            let id = UUID()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                var markdown = try DocImport.markdown(from: url) { [weak self] data, name in
                    self?.attach(data, named: name, to: id)
                }
                if MarkdownInfo.title(markdown).isEmpty || !markdown.hasPrefix("#") && MarkdownInfo.outline(markdown).isEmpty {
                    markdown = "# \(url.deletingPathExtension().lastPathComponent)\n\n" + markdown
                }
                let document = WriteDocument(id: id, text: markdown, modified: Date())
                documents.insert(document, at: 0)
                selectedID = id
                write(document)
                imported += 1
            } catch {
                notice = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if imported > 0 { notice = imported == 1 ? "Imported. It's a Markdown document now; the original file is untouched." : "Imported \(imported) documents." }
    }

    func data(for kind: WriteExport, document: WriteDocument) -> Data {
        // Citations go out as the words they show, with the reference list brought up to date.
        let text = Citations.plain(formatCitations?(document.text) ?? document.text)
        switch kind {
        case .pdf:
            return DocPDF.data(text, title: document.title, setup: pageSetup, baseURL: folder)
        case .docx:
            let base = folder
            return DocxWriter.data(markdown: text, title: document.title, setup: pageSetup) { source in
                let path = source.removingPercentEncoding ?? source
                return try? Data(contentsOf: path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            }
        case .markdown:
            return Data(text.utf8)
        case .html:
            return Data(MarkdownHTML.document(text, title: document.title).utf8)
        case .text:
            return Data(MarkdownPlain.text(text).utf8)
        }
    }

    func export(_ kind: WriteExport) {
        guard let document = selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(document.title) + "." + kind.fileExtension
        if let type = UTType(filenameExtension: kind.fileExtension) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(for: kind, document: document).write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func copyRichText() {
        guard let document = selected else { return }
        DocExport.copyRichText(Citations.plain(formatCitations?(document.text) ?? document.text), baseURL: folder)
        notice = "Copied with its formatting. Paste into Mail, Google Docs or Word."
    }

    static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(80))
    }

    private func savePageSetup() {
        if let data = try? JSONEncoder().encode(pageSetup) { UserDefaults.standard.set(data, forKey: "write.pageSetup") }
    }

    // MARK: Suggestions

    /// Rewrites the selection, or the whole draft when nothing is selected. Continue always adds at the end.
    func suggest(_ action: WriteAction, selection: NSRange) {
        guard let document = selected else { return }
        let text = document.text as NSString
        let range: NSRange
        let prompt: String
        if action == .continueWriting {
            range = NSRange(location: text.length, length: 0)
            let context = text.substring(from: max(0, text.length - 3_000))
            prompt = "\(action.instruction)\n\nText so far:\n\(context)"
        } else {
            let location = min(selection.location, text.length)
            let length = min(selection.length, text.length - location)
            range = length > 0 ? NSRange(location: location, length: length) : NSRange(location: 0, length: text.length)
            prompt = "\(action.instruction)\n\nText:\n\(text.substring(with: range))"
        }
        let original = text.substring(with: range)
        if action != .continueWriting && original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notice = "Write something first, or select the part to change."
            return
        }
        notice = nil
        let system = WriteModel.williamSystem + "\n\n" + voice.instructions
        let run = brain.run(BrainRequest(system: system, prompt: prompt, weight: original.count > 2_000 ? .deep : .quick))
        suggestion = WriteSuggestion(action: action, documentID: document.id, range: range, original: original, run: run)
    }

    func acceptSuggestion() {
        guard let suggestion, suggestion.run.status == .done,
              let index = documents.firstIndex(where: { $0.id == suggestion.documentID }) else { return }
        let current = documents[index].text as NSString
        let proposed = suggestion.run.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if suggestion.action == .continueWriting {
            let joiner = current.length == 0 || documents[index].text.hasSuffix("\n\n") ? "" : (documents[index].text.hasSuffix("\n") ? "\n" : "\n\n")
            update(suggestion.documentID, text: (current as String) + joiner + proposed)
            self.suggestion = nil
            return
        }

        // If the text moved while William was writing, find the original again.
        var range = suggestion.range
        if NSMaxRange(range) > current.length || current.substring(with: range) != suggestion.original {
            range = current.range(of: suggestion.original)
        }
        guard range.location != NSNotFound else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(proposed, forType: .string)
            notice = "The text changed while William was writing, so the suggestion was copied instead."
            self.suggestion = nil
            return
        }
        // Keep the spacing around the original so paragraphs don't run together.
        let leading = String(suggestion.original.prefix { $0.isWhitespace || $0.isNewline })
        let trailing = String(suggestion.original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed())
        update(suggestion.documentID, text: current.replacingCharacters(in: range, with: leading + proposed + trailing))
        self.suggestion = nil
    }

    func rejectSuggestion() {
        suggestion = nil
    }
}

enum WriteSamples {
    static func documents() -> [WriteDocument] {
        let now = Date()
        return [
            WriteDocument(
                id: UUID(),
                text: """
                # Investor update, October

                Hi all,

                I wanted to reach out to circle back on our progress this month and share some exciting updates. We have been leveraging our learnings from the pilot to really double down on the core experience, and I am thrilled to report that engagement has been **incredibly strong** across the board.

                ## Numbers

                | Measure | September | October |
                | --- | ---: | ---: |
                | Pilots | 3 | 5 |
                | Monthly active users | 310 | 455 |
                | Burn | $41k | $38k |
                | Runway | 13 months | 14 months |

                We closed two new pilots, *Acme* and *Northwind*.

                ## Next

                1. Ship single sign-on, which Acme needs before their rollout
                2. Hire our first designer
                - [x] Board deck drafted
                - [ ] Pilot go-live on Friday

                > [!NOTE] One ask
                > If you know a product designer who loves B2B tools, I'd love an intro.

                As always, please don't hesitate to reach out if there is anything at all that you think could be helpful.

                Best regards
                """,
                modified: now
            ),
            WriteDocument(
                id: UUID(),
                text: """
                # Welcome to Write

                William writes like you, so you only review. Documents are **Markdown files on this Mac**, shown as formatted pages.

                ## Formatting
                - **⌘B** bold, *⌘I* italic, ++⌘U++ underline, ==⇧⌘H== highlight, `⌘E` code, ⌘K a [link](https://11am.app)
                - ⌥⌘1, 2 and 3 for headings, ⇧⌘8 bullets, ⇧⌘7 numbers, ⇧⌘L a checklist
                - Paste or drop a picture or a file and it's kept with the document
                - [ ] Click a box to tick it

                ## William
                Select a sentence or a paragraph, then choose **Shorter**, **Clearer**, **Warmer** or **In my voice**. His version appears as a suggestion: accept with ⌘↩ or reject with esc. Nothing changes until you accept.

                ## In and out
                **Import** opens Word, RTF, HTML, OpenDocument and Markdown files. **Export** makes a PDF with your page setup, a Word file with real headings and lists, a web page, Markdown or plain text. Every 15 minutes of writing keeps a version you can go back to.
                """,
                modified: now.addingTimeInterval(-3_600)
            ),
        ]
    }
}
