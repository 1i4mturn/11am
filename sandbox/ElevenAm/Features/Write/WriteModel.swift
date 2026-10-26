import AppKit
import Foundation
import SwiftUI

struct WriteDocument: Identifiable, Equatable {
    let id: UUID
    var text: String
    var modified: Date

    var title: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let cleaned = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(60))
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

enum WriteAction: String, CaseIterable, Identifiable {
    case voice, shorter, clearer, warmer, grammar, continueWriting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "In my voice"
        case .shorter: return "Shorter"
        case .clearer: return "Clearer"
        case .warmer: return "Warmer"
        case .grammar: return "Fix grammar"
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

/// William in the sandbox: plain documents on disk, inline rewrites as suggestions, your voice in every prompt.
@MainActor
final class WriteModel: ObservableObject {
    @Published private(set) var documents: [WriteDocument] = []
    @Published var selectedID: UUID?
    @Published private(set) var suggestion: WriteSuggestion?
    @Published var notice: String?

    static let williamSystem = """
    You are William, the writing agent inside 11am. You edit the user's writing in their own voice. \
    Return only the new text: no preamble, no quotation marks around it, no notes about what you changed.
    """

    private let brain: Brain
    private let voice: VoiceProfile
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    init(brain: Brain, voice: VoiceProfile) {
        self.brain = brain
        self.voice = voice
    }

    private var folder: URL {
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

    func newDocument() {
        let document = WriteDocument(id: UUID(), text: "", modified: Date())
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

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
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
        }
    }

    private func url(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).md")
    }

    private func write(_ document: WriteDocument) {
        try? document.text.write(to: url(for: document.id), atomically: true, encoding: .utf8)
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
                Investor update, October

                Hi all,

                I wanted to reach out to circle back on our progress this month and share some exciting updates. We have been leveraging our learnings from the pilot to really double down on the core experience, and I am thrilled to report that engagement has been incredibly strong across the board.

                In terms of numbers, we closed two new pilots (Acme and Northwind), bringing us to five in total. Monthly active users grew from 310 to 455. Burn was $38k, and we have 14 months of runway.

                Going forward, our key focus areas will be shipping single sign-on, which Acme needs before their rollout, and hiring our first designer.

                As always, please don't hesitate to reach out if there is anything at all that you think could be helpful.

                Best regards
                """,
                modified: now
            ),
            WriteDocument(
                id: UUID(),
                text: """
                Welcome to Write

                William writes like you, so you only review.

                Select a sentence or a paragraph, then choose Shorter, Clearer, Warmer or In my voice. William's version appears as a suggestion. Accept it with ⌘Return or reject it with Esc. Nothing changes until you accept.

                With nothing selected, William works on the whole draft. Continue adds a paragraph at the end.

                Your voice lives under "Your voice" at the top. Marc uses the same notes when he drafts your email replies.

                Documents are plain text files on this Mac.
                """,
                modified: now.addingTimeInterval(-3_600)
            ),
        ]
    }
}
