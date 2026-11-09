import AppKit
import Foundation

/// What William is doing for the document you're in: a summary, a translation, or a draft from your own material.
@MainActor
final class WilliamJob: ObservableObject, Identifiable {
    enum Kind: Equatable {
        case summary
        case translation(String)
        case draft
    }

    let id = UUID()
    let kind: Kind
    let documentID: UUID?
    @Published var run: BrainRun?
    @Published var progress = ""
    @Published var finished = false

    init(kind: Kind, documentID: UUID?) {
        self.kind = kind
        self.documentID = documentID
    }

    var title: String {
        switch kind {
        case .summary: return "Summary"
        case .translation(let language): return "In \(language)"
        case .draft: return "Draft"
        }
    }
}

extension WriteModel {
    // MARK: Comments

    func saveComments() {
        JSONStore.save(Dictionary(uniqueKeysWithValues: comments.map { ($0.key.uuidString, $0.value) }), to: "write-comments")
    }

    func comments(for documentID: UUID) -> [DocComment] {
        guard let document = documents.first(where: { $0.id == documentID }) else { return [] }
        return DocAnchors.ordered(comments[documentID] ?? [], in: document.text)
    }

    /// Where each open comment's passage is now, for highlighting.
    func commentRanges(for documentID: UUID) -> [NSRange] {
        guard let document = documents.first(where: { $0.id == documentID }) else { return [] }
        return (comments[documentID] ?? []).filter { !$0.resolved }.compactMap { DocAnchors.locate($0, in: document.text) }
    }

    func addComment(_ body: String, on range: NSRange, in documentID: UUID) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let document = documents.first(where: { $0.id == documentID }),
              let comment = DocAnchors.comment(on: range, in: document.text, body: text) else {
            notice = "Select the words you want to comment on first."
            return
        }
        comments[documentID, default: []].append(comment)
        saveComments()
        showsComments = true
        if comment.asksWilliam { answer(comment.id, in: documentID) }
    }

    func reply(_ body: String, to commentID: UUID, in documentID: UUID, author: String = "You") {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = comments[documentID]?.firstIndex(where: { $0.id == commentID }) else { return }
        comments[documentID]?[index].replies.append(DocReply(author: author, body: text, created: Date()))
        saveComments()
        if author == "You", DocAnchors.mentionsWilliam(text) { answer(commentID, in: documentID) }
    }

    func resolve(_ commentID: UUID, in documentID: UUID) {
        guard let index = comments[documentID]?.firstIndex(where: { $0.id == commentID }) else { return }
        comments[documentID]?[index].resolved.toggle()
        saveComments()
    }

    func deleteComment(_ commentID: UUID, in documentID: UUID) {
        comments[documentID]?.removeAll { $0.id == commentID }
        saveComments()
    }

    /// William answers from the document: the passage, the thread, and the text around it.
    func answer(_ commentID: UUID, in documentID: UUID) {
        guard let comment = comments[documentID]?.first(where: { $0.id == commentID }),
              let document = documents.first(where: { $0.id == documentID }) else { return }
        let thread = ([comment.author + ": " + comment.body] + comment.replies.map { "\($0.author): \($0.body)" }).joined(separator: "\n")
        let prompt = """
        The document:
        \(document.text.prefix(9_000))

        The passage the comment is on: "\(comment.quote)"

        The comment thread:
        \(thread)

        Reply to the last message in the thread, in two or three sentences. If it asks for new wording, give it.
        """
        let system = "You are William, the writing agent inside 11am. Answer comments on the user's document plainly, from the document. "
            + "Don't invent facts the document doesn't give; say what's missing instead."
        let run = brain.run(BrainRequest(system: system, prompt: prompt, weight: .quick))
        answering.insert(commentID)
        Task { @MainActor [weak self] in
            await run.finished()
            guard let self else { return }
            self.answering.remove(commentID)
            let text: String
            switch run.status {
            case .done: text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .failed(let message): text = "I couldn't answer: \(message)"
            default: return
            }
            guard !text.isEmpty, let index = self.comments[documentID]?.firstIndex(where: { $0.id == commentID }) else { return }
            self.comments[documentID]?[index].replies.append(DocReply(author: "William", body: text, created: Date()))
            self.saveComments()
        }
    }

    // MARK: Summary

    func summarise() {
        guard let document = selected else { return }
        let job = WilliamJob(kind: .summary, documentID: document.id)
        let system = WriteModel.williamSystem + "\n\n" + voice.instructions
        job.run = brain.run(BrainRequest(system: system, prompt: "Summarise this document in two or three sentences, plainly, for someone who won't read the rest:\n\n\(document.text.prefix(12_000))", weight: .quick))
        william = job
    }

    /// The summary under the title.
    func insertSummary(_ job: WilliamJob) {
        guard let id = job.documentID, let document = documents.first(where: { $0.id == id }), let text = job.run?.text else { return }
        update(id, text: DocShape.insertSummary(text, into: document.text))
        william = nil
        notice = "The summary is under the title. Run it again after big changes and it replaces itself."
    }

    // MARK: Translation

    /// A translated copy, a part at a time, then a pass to sound like you in that language.
    func translate(to language: String) {
        guard let document = selected else { return }
        translate(text: document.text, title: document.title, to: language, from: document.id)
    }

    /// Any text (a document here, or a PDF from Bolton) translated into a new document.
    func translate(text source: String, title sourceTitle: String, to language: String, from documentID: UUID? = nil) {
        let job = WilliamJob(kind: .translation(language), documentID: documentID)
        william = job
        let parts = DocShape.chunks(source)
        let system = WriteModel.williamSystem + " Translate into \(language). Keep the Markdown exactly: headings, lists, links, tables, emphasis. "
            + "Translate meaning, not word for word, so it reads as if written in \(language). " + voice.instructions
        Task { @MainActor [weak self] in
            guard let self else { return }
            var translated: [String] = []
            for (index, part) in parts.enumerated() {
                job.progress = parts.count > 1 ? "Part \(index + 1) of \(parts.count)…" : "Translating…"
                let run = self.brain.run(BrainRequest(system: system, prompt: part, weight: .deep))
                job.run = run
                await run.finished()
                guard run.status == .done else {
                    var reason = "no answer came back"
                    if case .failed(let message) = run.status { reason = message }
                    job.progress = "Stopped: " + reason
                    job.finished = true
                    return
                }
                translated.append(run.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let title = "\(sourceTitle) (\(language))"
            var text = translated.joined(separator: "\n\n")
            if !text.hasPrefix("# ") { text = "# \(title)\n\n" + text }
            self.addDocument(text: text)
            job.progress = "Done: a new document, \u{201C}\(title)\u{201D}."
            job.finished = true
        }
    }

    // MARK: Drafting from your own material

    /// Notes, documents and indexed files that match what you asked for.
    func findMaterial(_ request: String) -> [DraftMaterial] {
        var items: [DraftMaterial] = []
        for note in notes?.notes ?? [] where !NoteLock.isLocked(note.text) {
            items.append(DraftMaterial(id: "note:\(note.id)", title: note.title, kind: "Note", text: note.text, date: note.modified))
        }
        for document in documents {
            items.append(DraftMaterial(id: "doc:\(document.id)", title: document.title, kind: "Document", text: document.text, date: document.modified))
        }
        for file in files?.files ?? [] where !file.text.isEmpty {
            items.append(DraftMaterial(id: "file:\(file.path)", title: file.name, kind: "File", text: file.text, date: file.modified))
        }
        return MaterialFinder.rank(request, items, now: Date(), limit: 6)
    }

    /// A new document from what you asked for, written only from the material you kept ticked, optionally shaped like
    /// another document; the sources are listed at the end.
    func draft(_ request: String, from material: [DraftMaterial], shapedLike shape: WriteDocument?) {
        let ask = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ask.isEmpty else { return }
        let job = WilliamJob(kind: .draft, documentID: nil)
        william = job
        let terms = MaterialFinder.terms(ask)
        let sources = material.enumerated().map { index, item in
            "[\(index + 1)] \(item.kind): \(item.title)\n\(MaterialFinder.excerpt(item, terms: terms))"
        }.joined(separator: "\n\n")
        var prompt = "Write: \(ask)\n\nUse only these sources for facts, names and numbers. If something isn't in them, leave a [square-bracket gap] for the user to fill.\n\n\(sources)"
        if let shape { prompt += "\n\nFollow this outline (the shape of \u{201C}\(shape.title)\u{201D}):\n\(DocShape.outline(shape.text))" }
        prompt += "\n\nStart with a # title."
        let system = WriteModel.williamSystem + "\n\n" + voice.instructions
        let run = brain.run(BrainRequest(system: system, prompt: prompt, weight: .deep))
        job.run = run
        job.progress = "Writing from \(material.count) \(material.count == 1 ? "source" : "sources")…"
        Task { @MainActor [weak self] in
            await run.finished()
            guard let self, run.status == .done else {
                job.finished = true
                return
            }
            let list = material.map { "- \($0.kind): \($0.title)" }.joined(separator: "\n")
            self.addDocument(text: run.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n## Written from\n\n" + list + "\n")
            job.progress = "Done: the draft is the first document, with what it was written from at the end."
            job.finished = true
        }
    }

    // MARK: Flashcards

    /// Harris makes cards from the document, in Learn.
    func makeFlashcards() {
        guard let document = selected, let learn else { return }
        learn.makeCards(from: document.text)
        onOpen?(.learn)
    }
}

extension WriteModel {
    /// For screenshots: comments on the investor update, one of them answered by William.
    func loadCommentSample() {
        guard let document = documents.first(where: { $0.title.hasPrefix("Investor update") }) else { return }
        selectedID = document.id
        let ns = document.text as NSString
        var list: [DocComment] = []
        if var strong = DocAnchors.comment(on: ns.range(of: "incredibly strong"), in: document.text, body: "Is this true of both pilots? @William", date: Date().addingTimeInterval(-3_600)) {
            strong.replies = [DocReply(author: "William", body: "The update only gives totals: monthly active users went from 310 to 455. \"Up 47% in a month\" says it with the number, and doesn't claim more than the table shows.", created: Date().addingTimeInterval(-3_500))]
            list.append(strong)
        }
        if let hire = DocAnchors.comment(on: ns.range(of: "Hire our first designer"), in: document.text, body: "Add the budget and when we want them to start.", date: Date().addingTimeInterval(-1_800)) {
            list.append(hire)
        }
        if var done = DocAnchors.comment(on: ns.range(of: "circle back"), in: document.text, body: "Jargon. Cut it.", date: Date().addingTimeInterval(-7_200)) {
            done.resolved = true
            list.append(done)
        }
        comments[document.id] = list
        saveComments()
        showsComments = true
    }

    /// For screenshots: a finished summary waiting to go under the title.
    func showSampleSummary() {
        guard let document = documents.first(where: { $0.title.hasPrefix("Investor update") }) else { return }
        selectedID = document.id
        let job = WilliamJob(kind: .summary, documentID: document.id)
        let run = BrainRun(prompt: "Summarise")
        run.text = "Two new pilots (Acme and Northwind) took us to five, monthly active users rose from 310 to 455, and burn fell to $38k, giving 14 months of runway. Next: single sign-on for Acme's rollout and our first designer."
        run.providerLabel = "On this Mac"
        run.status = .done
        job.run = run
        william = job
    }
}
