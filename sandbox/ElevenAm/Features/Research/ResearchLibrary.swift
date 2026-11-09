import AppKit
import Foundation

/// One "Look this up": the question, what James found and read, and his answer with its sources.
@MainActor
final class LookUp: ObservableObject, Identifiable {
    enum Stage: Equatable {
        case searching, reading(Int), answering, done
        case failed(String)
    }

    let id = UUID()
    let question: String
    let started = Date()
    @Published var stage: Stage = .searching
    /// The pages he read, numbered as the answer cites them.
    @Published var sources: [CitationSource] = []
    @Published var run: BrainRun?
    @Published var review: AnswerReview?
    @Published var kept = false

    init(question: String) {
        self.question = question
    }

    var status: String {
        switch stage {
        case .searching: return "Searching the web…"
        case .reading(let count): return "Reading \(count) \(count == 1 ? "page" : "pages")…"
        case .answering: return "Writing a sourced answer…"
        case .done: return sources.isEmpty ? "Done" : "From \(sources.count) \(sources.count == 1 ? "source" : "sources")"
        case .failed(let message): return message
        }
    }
}

/// Where a clipping goes: Notes' Clippings folder, or inside a page of the wiki.
enum ClipPlace: Equatable {
    case notes
    case page(UUID)
}

extension ResearchModel {
    static let clippingsFolder = "Clippings"

    // MARK: The library

    func saveLibrary() { JSONStore.save(library, to: "research-sources") }

    /// Adds a source with a key of its own; a page already in the library is kept as it is.
    @discardableResult
    func addSource(_ source: CitationSource) -> CitationSource {
        if !source.url.isEmpty, let existing = library.first(where: { $0.url == source.url }) { return existing }
        var source = source
        if source.key.isEmpty || library.contains(where: { $0.key == source.key }) {
            source.key = Citations.key(for: source, existing: Set(library.map(\.key)))
        }
        library.append(source)
        saveLibrary()
        return source
    }

    /// What the page says about itself, as a source.
    static func source(from article: ClippedArticle) -> CitationSource {
        var source = CitationSource(title: article.title, url: article.url, kind: article.details.kind, authors: article.details.authors,
                                    container: article.details.site, published: article.details.published, accessed: Date(),
                                    excerpt: String(article.markdown.prefix(6_000)))
        source.doi = article.details.doi
        source.volume = article.details.volume
        source.issue = article.details.issue
        source.pages = article.details.pages
        return source
    }

    func addCurrentPage() {
        guard let url = pageURL else { notice = "Open a web page to add it."; return }
        if let existing = library.first(where: { $0.url == url.absoluteString }) {
            notice = "Already in your sources as \(citeText(existing))."
            tab = .sources
            return
        }
        Task {
            let source: CitationSource
            if let article = await readPage() {
                source = Self.source(from: article)
            } else {
                let text = await pageText()
                source = CitationSource(title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url.absoluteString,
                                        container: url.host() ?? "", excerpt: String(text.prefix(6_000)))
            }
            let added = addSource(source)
            tab = .sources
            let missing = (added.authors.isEmpty ? ["author"] : []) + (added.published == nil ? ["date"] : [])
            notice = "Added \u{201C}\(added.title)\u{201D}. Cite it as \(citeText(added))."
                + (missing.isEmpty ? "" : " The page doesn't give its \(missing.joined(separator: " or ")); add it if you know it.")
        }
    }

    func update(_ source: CitationSource) {
        guard let index = library.firstIndex(where: { $0.id == source.id }) else { return }
        var changed = source
        // Documents cite by key, so a key only changes when it's blank or taken.
        if changed.key.isEmpty || library.contains(where: { $0.id != source.id && $0.key == changed.key }) {
            changed.key = Citations.key(for: changed, existing: Set(library.filter { $0.id != source.id }.map(\.key)))
        }
        library[index] = changed
        saveLibrary()
    }

    func remove(_ source: CitationSource) {
        library.removeAll { $0.id == source.id }
        saveLibrary()
    }

    func clearSources() {
        library = []
        saveLibrary()
    }

    /// How the source is cited in the text, in your style, without Markdown.
    func citeText(_ source: CitationSource) -> String {
        Citations.unescape(Citations.inText([source], style: style, numbers: [library.firstIndex { $0.id == source.id }.map { $0 + 1 } ?? 1], letters: [:]))
            .replacingOccurrences(of: "*", with: "")
    }

    func reference(_ source: CitationSource) -> String {
        Citations.reference(source, style: style, number: (library.firstIndex { $0.id == source.id } ?? 0) + 1)
    }

    /// Copies a reference with its italics, ready for Pages, Word or Google Docs.
    func copyReference(_ source: CitationSource) {
        DocExport.copyRichText(reference(source), baseURL: nil)
        notice = "Copied the \(style.title) reference."
    }

    /// Every source as a reference list in your style.
    func copyBibliography() {
        let sorted = style.isNumbered ? library : library.sorted { Citations.sortKey($0, letters: [:]) < Citations.sortKey($1, letters: [:]) }
        let entries = sorted.enumerated().map { index, source in
            style.isNumbered ? "\(index + 1). " + Citations.reference(source, style: style, number: index + 1) : Citations.reference(source, style: style)
        }
        DocExport.copyRichText(entries.joined(separator: style.isNumbered ? "\n" : "\n\n"), baseURL: nil)
        notice = "Copied \(library.count) references in \(style.title)."
    }

    // MARK: Citations in Write and Decks

    /// What Cite puts at the cursor: a citation in your style that remembers its source.
    func citation(for source: CitationSource, in document: String) -> String {
        let cited = Citations.markers(in: document).flatMap(\.keys)
        var order: [String] = []
        for key in cited where !order.contains(key) { order.append(key) }
        let number = (order.firstIndex(of: source.key.lowercased()) ?? order.count) + 1
        return Citations.marker(for: [source], style: style) { _ in number }
    }

    /// A citation clicked in Write: its source opens in Research.
    func openSource(keys: String) {
        guard let key = keys.split(separator: ",").first.map({ String($0).lowercased() }),
              let source = library.first(where: { $0.key.lowercased() == key }) else {
            write.notice = "That citation's source isn't in your sources any more."
            return
        }
        tab = .sources
        if !source.url.isEmpty { open(source.url) }
        onOpen?(.research)
    }

    /// Rewrites every citation in the document in your style and puts the reference list at the end.
    func formatCitations(documentID: UUID) {
        guard let document = write.documents.first(where: { $0.id == documentID }) else { return }
        guard !Citations.markers(in: document.text).isEmpty else {
            write.notice = "Nothing cited yet. Put the cursor where a claim needs a source and choose Cite."
            return
        }
        let result = Citations.format(document.text, sources: library, style: style)
        write.update(documentID, text: result.text)
        var message = result.cited.isEmpty ? "None of the citations match your sources."
            : "\(result.cited.count) \(result.cited.count == 1 ? "source" : "sources") in \(style.title), with the \(style.heading.lowercased()) at the end."
        if !result.missing.isEmpty {
            message += " Not in your sources: \(result.missing.joined(separator: ", "))."
        }
        write.notice = message
    }

    /// The source on the slide you're on, as a line at its foot.
    func citeOnSlide(_ source: CitationSource) {
        guard let decks, decks.deck != nil else { return }
        let short = shortCite(source)
        let line = source.container.isEmpty || source.authors.isEmpty ? "Source: \(short)" : "Source: \(short), \(source.container)"
        decks.updateContent { $0.caption = line }
        decks.notice = "Cited \(short) on this slide. Add a sources slide at the end so people can look them up."
    }

    /// A last slide listing the sources, with the full references in its notes.
    func addSourcesSlide(_ sources: [CitationSource]) {
        guard let decks, decks.deck != nil, !sources.isEmpty else { return }
        let sorted = style.isNumbered ? sources : sources.sorted { Citations.sortKey($0, letters: [:]) < Citations.sortKey($1, letters: [:]) }
        var content = SlideContent()
        content.title = "Sources"
        content.bullets = sorted.map { source in
            let year = source.published.map { String($0.year) } ?? Citations.noDate(style)
            let where_ = source.host.isEmpty ? source.container : source.host
            let lead = source.authors.isEmpty ? "\(source.title) (\(year))" : "\(Citations.shortAuthors(source, style: style)) (\(year)), \(source.title)"
            return Self.unmark(where_.isEmpty ? lead : "\(lead) · \(where_)")
        }
        let notes = sorted.map { Self.unmark(Citations.reference($0, style: style)) }.joined(separator: "\n\n")
        decks.insertSlide(.bullets, content: content, notes: notes, atEnd: true)
        decks.notice = "Added a sources slide with \(sorted.count) \(sorted.count == 1 ? "source" : "sources"); the full \(style.title) references are in its notes."
    }

    /// "Nguyen & Brown, 2025": the in-text citation without its brackets or marks.
    func shortCite(_ source: CitationSource) -> String {
        let year = source.published.map { String($0.year) } ?? Citations.noDate(style)
        let who = Self.unmark(Citations.shortAuthors(source, style: style)).replacingOccurrences(of: "\u{201C}", with: "").replacingOccurrences(of: "\u{201D}", with: "")
        return style == .mla ? who : "\(who), \(year)"
    }

    static func unmark(_ text: String) -> String {
        text.replacingOccurrences(of: "\\*", with: "\u{0}").replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\u{0}", with: "*")
    }

    // MARK: Clipping

    /// Clips the page you're on (and anything you've selected) into Notes, read like reader mode.
    func clipCurrentPage(to place: ClipPlace = .notes) {
        Task {
            guard let article = await readPage() else { notice = "Open a page to clip it."; return }
            let selection = await selectedText()
            keepClip(ClipNote.markdown(article, selection: selection, clipped: Date()), title: article.title, place: place)
        }
    }

    /// From the browser button: James fetches the page himself and clips it, with what you'd selected.
    func clip(url: String, title: String, selection: String) async {
        guard let link = URL(string: url), link.scheme?.hasPrefix("http") == true else {
            clipText(selection, title: title, from: url)
            return
        }
        notice = "Clipping \(title.isEmpty ? link.host() ?? url : title)…"
        do {
            let html = try await Self.fetch(link)
            let article = await Task.detached(priority: .userInitiated) { ArticleReader.read(html: html, url: link) }.value
            keepClip(ClipNote.markdown(article, selection: selection, clipped: Date()), title: article.title, place: .notes)
        } catch {
            // Behind a login or offline: keep what the browser sent.
            let fallback = selection.isEmpty ? "[\(title.isEmpty ? url : title)](\(url))" : selection
            keepClip(ClipNote.markdown(text: fallback, title: title, from: "[\(link.host() ?? url)](\(url))", clipped: Date()),
                     title: title.isEmpty ? url : title, place: .notes)
        }
    }

    /// Text handed over from another app through the Services menu.
    func clipText(_ text: String, title: String = "", from source: String = "") {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        keepClip(ClipNote.markdown(text: body, title: title, from: source, clipped: Date()), title: title.isEmpty ? String(body.prefix(40)) : title, place: .notes)
    }

    private func keepClip(_ markdown: String, title: String, place: ClipPlace) {
        guard let notes else { return }
        switch place {
        case .notes:
            notes.newNote(text: markdown, folder: Self.clippingsFolder)
        case .page(let parent):
            if let page = notes.newSubpage(of: parent) { notes.update(page.id, text: markdown) }
        }
        let where_ = place == .notes ? "Notes › \(Self.clippingsFolder)" : "the page you chose"
        notice = "Clipped \u{201C}\(title)\u{201D} to \(where_)."
        onLog?("Clipped \u{201C}\(title)\u{201D} into \(where_).")
    }

    /// Fetches a page the way a browser would ask for it.
    nonisolated static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-AU,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Look this up

    /// From any app: James searches, reads the top pages, and answers citing them, in the agent pane.
    func lookUp(_ text: String) {
        let question = String(HTMLText.collapse(text).prefix(300))
        guard !question.isEmpty else { return }
        let lookup = LookUp(question: question)
        self.lookup = lookup
        onShowPane?()
        onLog?("Looking up \u{201C}\(question.prefix(60))\u{201D}.")
        Task { await run(lookup) }
    }

    private func run(_ lookup: LookUp) async {
        do {
            guard let url = SearchResults.url(for: lookup.question) else { throw URLError(.badURL) }
            let page = try await Self.fetch(url)
            let hits = Array(SearchResults.duckDuckGo(page).prefix(5))
            guard !hits.isEmpty else {
                lookup.stage = .failed("No results came back. Try different words.")
                return
            }
            lookup.stage = .reading(min(hits.count, 4))
            var found = await Self.read(Array(hits.prefix(4)))
            // Pages that couldn't be read still have their search snippets.
            if found.isEmpty {
                found = hits.prefix(3).map { hit in
                    CitationSource(title: hit.title, url: hit.url, container: hit.host, excerpt: hit.snippet)
                }
            }
            lookup.sources = found
            lookup.stage = .answering
            let materials = found.map { SourcedAnswer.Material(title: $0.title, url: $0.url, text: $0.excerpt) }
            let run = brain.run(BrainRequest(system: SourcedAnswer.system, prompt: SourcedAnswer.prompt(question: lookup.question, sources: materials), weight: .deep))
            lookup.run = run
            await run.finished()
            switch run.status {
            case .done:
                lookup.review = SourcedAnswer.review(run.text, sourceCount: found.count)
                lookup.stage = .done
            case .failed(let message):
                lookup.stage = .failed(message)
            default:
                break
            }
        } catch {
            lookup.stage = .failed("Couldn't reach the web: \(error.localizedDescription)")
        }
    }

    /// Reads up to four pages at once, off the main thread, and keeps the three best in search order.
    nonisolated static func read(_ hits: [WebHit]) async -> [CitationSource] {
        await withTaskGroup(of: (Int, CitationSource?).self, returning: [CitationSource].self) { group in
            for (index, hit) in hits.enumerated() {
                group.addTask {
                    guard let url = URL(string: hit.url), let html = try? await ResearchModel.fetch(url) else { return (index, nil) }
                    let article = ArticleReader.read(html: html, url: url)
                    guard article.words >= 80 else { return (index, nil) }
                    var source = CitationSource(title: article.title, url: hit.url, kind: article.details.kind, authors: article.details.authors,
                                                container: article.details.site, published: article.details.published, accessed: Date(),
                                                excerpt: String(article.markdown.prefix(6_000)))
                    source.doi = article.details.doi
                    return (index, source)
                }
            }
            var found: [(Int, CitationSource)] = []
            for await (index, source) in group {
                if let source { found.append((index, source)) }
            }
            return found.sorted { $0.0 < $1.0 }.prefix(3).map { $0.1 }
        }
    }

    /// The pages James read go into your sources.
    func keepLookUpSources() {
        guard let lookup else { return }
        for source in lookup.sources { addSource(source) }
        lookup.kept = true
        notice = "Added \(lookup.sources.count) sources from the look-up."
    }

    /// The answer as a document in Write, its [n] turned into citations of those sources.
    func sendLookUpToWrite() {
        guard let lookup, let run = lookup.run, run.status == .done else { return }
        var keyed: [CitationSource] = []
        for source in lookup.sources { keyed.append(addSource(source)) }
        lookup.kept = true
        let text = Self.linkCitations(in: run.text, sources: keyed)
        let formatted = Citations.format("# \(lookup.question)\n\n\(text)\n", sources: library, style: style)
        write.addDocument(text: formatted.text)
        onOpen?(.write)
    }

    /// The answer and its sources as a note.
    func clipLookUp() {
        guard let lookup, let run = lookup.run, run.status == .done else { return }
        let list = lookup.sources.enumerated().map { "\($0.offset + 1). [\($0.element.title)](\($0.element.url))" }.joined(separator: "\n")
        let markdown = "# \(lookup.question)\n\n\(run.text)\n\n## Sources\n\n\(list)\n\n#lookup"
        keepClip(markdown, title: lookup.question, place: .notes)
    }

    // MARK: Links and Services

    func handle(_ link: ClipLink) {
        switch link {
        case .clip(let url, let title, let selection):
            Task { await clip(url: url, title: title, selection: selection) }
        case .lookUp(let question):
            lookUp(question)
        }
    }
}

/// The Services menu in every app: "Look Up with James" and "Clip to 11am Notes".
@MainActor
final class ResearchServices: NSObject {
    weak var research: ResearchModel?

    init(research: ResearchModel) {
        self.research = research
    }

    @objc func lookUp(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some words to look up." as NSString
            return
        }
        NSApp.activate()
        research?.lookUp(text)
    }

    @objc func clipToNotes(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let link = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string).flatMap({ text in
            text.hasPrefix("http") && !text.contains(" ") && !text.contains("\n") ? text : nil
        }) {
            Task { await research?.clip(url: link, title: "", selection: "") }
            return
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "Select some text or a link to clip." as NSString
            return
        }
        research?.clipText(text)
    }
}
