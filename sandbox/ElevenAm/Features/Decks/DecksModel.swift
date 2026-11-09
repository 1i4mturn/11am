import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DeckEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var slides: Int
    var modified: Date
}

/// Conner's decks: slides on the canvas, saved on this Mac, presented full screen or sent as PDF and PowerPoint.
@MainActor
final class DecksModel: ObservableObject {
    @Published private(set) var entries: [DeckEntry] = []
    @Published private(set) var deck: SlideDeck?
    @Published var slideIndex = 0
    @Published var notice: String?
    @Published var askRun: BrainRun?
    @Published var presenting = false

    let root = JSONStore.folder.appendingPathComponent("Decks", isDirectory: true)
    let assets: CanvasAssetStore
    let controller: CanvasController
    private let brain: Brain
    private var saveTask: Task<Void, Never>?
    private var loadingSlide = false

    init(brain: Brain) {
        self.brain = brain
        let assets = CanvasAssetStore(folder: JSONStore.folder.appendingPathComponent("Decks/Assets", isDirectory: true))
        self.assets = assets
        controller = CanvasController(document: CanvasDocument(name: "Slide", size: SlideDeck.size), assets: assets)
        controller.onChange = { [weak self] canvas in self?.canvasChanged(canvas) }
    }

    var slide: Slide? {
        guard let deck, deck.slides.indices.contains(slideIndex) else { return nil }
        return deck.slides[slideIndex]
    }

    // MARK: Files

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [DeckEntry] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file), let deck = try? Self.decoder.decode(SlideDeck.self, from: data) else { continue }
            found.append(DeckEntry(id: deck.id, name: deck.name, slides: deck.slides.count, modified: deck.modified))
        }
        entries = found.sorted { $0.modified > $1.modified }
        if entries.isEmpty && !UserDefaults.standard.bool(forKey: "decks.seeded") {
            UserDefaults.standard.set(true, forKey: "decks.seeded")
            let sample = SlideDeck(name: "Seed round", theme: .paper, slides: DeckOutline.slides(from: DecksSamples.pitch, theme: .paper))
            write(sample)
        }
        if deck == nil, let first = entries.first { open(first.id) }
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

    private func write(_ deck: SlideDeck) {
        if let data = try? Self.encoder.encode(deck) { try? data.write(to: url(deck.id), options: .atomic) }
        let entry = DeckEntry(id: deck.id, name: deck.name, slides: deck.slides.count, modified: deck.modified)
        if let index = entries.firstIndex(where: { $0.id == deck.id }) { entries[index] = entry } else { entries.insert(entry, at: 0) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            self?.flushSave()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        if let deck { write(deck) }
    }

    func open(_ id: UUID) {
        flushSave()
        guard let data = try? Data(contentsOf: url(id)), let loaded = try? Self.decoder.decode(SlideDeck.self, from: data) else {
            notice = "That deck couldn't be read."
            return
        }
        deck = loaded
        showSlide(0)
    }

    func open(named name: String) {
        if let entry = entries.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { open(entry.id) }
    }

    func delete(_ id: UUID) {
        NSWorkspace.shared.recycle([url(id)]) { _, _ in }
        entries.removeAll { $0.id == id }
        if deck?.id == id {
            deck = nil
            if let first = entries.first { open(first.id) }
        }
    }

    func rename(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        change { $0.name = name }
    }

    // MARK: Changing

    private func change(_ edit: (inout SlideDeck) -> Void) {
        guard var current = deck else { return }
        edit(&current)
        current.modified = Date()
        deck = current
        scheduleSave()
    }

    func showSlide(_ index: Int) {
        guard let deck, !deck.slides.isEmpty else { return }
        slideIndex = max(0, min(index, deck.slides.count - 1))
        loadingSlide = true
        controller.load(deck.slides[slideIndex].canvas)
        loadingSlide = false
    }

    /// Hand edits on the canvas: kept, and the slide remembers it was edited.
    private func canvasChanged(_ canvas: CanvasDocument) {
        guard !loadingSlide else { return }
        let index = slideIndex
        change { deck in
            guard deck.slides.indices.contains(index) else { return }
            deck.slides[index].canvas = canvas
            deck.slides[index].customised = true
        }
    }

    /// Changing what a slide says lays it out again, or updates the words in place on a hand-edited slide.
    func updateContent(_ transform: (inout SlideContent) -> Void) {
        let index = slideIndex
        change { deck in
            guard deck.slides.indices.contains(index) else { return }
            transform(&deck.slides[index].content)
            if deck.slides[index].customised {
                Self.applyWords(deck.slides[index].content, to: &deck.slides[index].canvas)
            } else {
                deck.slides[index].canvas = DeckLayoutEngine.canvas(deck.slides[index].layout, deck.slides[index].content, deck.theme)
            }
        }
        reloadCanvas()
    }

    private static func applyWords(_ content: SlideContent, to canvas: inout CanvasDocument) {
        for index in canvas.layers.indices {
            guard case .text(_, let style) = canvas.layers[index].content else { continue }
            let words: String?
            switch canvas.layers[index].role {
            case "title": words = content.title
            case "subtitle", "kicker": words = content.subtitle
            case "body": words = content.bullets.map { "•  " + $0 }.joined(separator: "\n")
            case "body2": words = content.secondary.map { "•  " + $0 }.joined(separator: "\n")
            case "number": words = content.number
            case "caption": words = content.caption
            case "quote": words = content.quote
            case "attribution": words = content.attribution.isEmpty ? "" : "— " + content.attribution
            default: words = nil
            }
            if let words { canvas.layers[index].content = .text(words, style) }
        }
    }

    private func reloadCanvas() {
        guard let slide else { return }
        loadingSlide = true
        let selection = controller.selection
        controller.load(slide.canvas)
        controller.selection = selection
        loadingSlide = false
    }

    func setLayout(_ layout: SlideLayout) {
        let index = slideIndex
        change { deck in
            guard deck.slides.indices.contains(index) else { return }
            deck.slides[index].layout = layout
            deck.relayout(index)
        }
        reloadCanvas()
    }

    func resetLayout() {
        let index = slideIndex
        change { $0.relayout(index) }
        reloadCanvas()
    }

    func setTheme(_ theme: DeckTheme) {
        change { $0.apply(theme) }
        reloadCanvas()
    }

    func setNotes(_ notes: String) {
        let index = slideIndex
        change { deck in
            guard deck.slides.indices.contains(index) else { return }
            deck.slides[index].notes = notes
        }
    }

    func addSlide(_ layout: SlideLayout) {
        guard let theme = deck?.theme else { return }
        var content = SlideContent()
        content.title = layout == .closing ? "Thank you" : "New slide"
        if layout == .bullets || layout == .twoColumns || layout == .timeline || layout == .team { content.bullets = ["First point", "Second point", "Third point"] }
        if layout == .twoColumns { content.secondary = ["One more", "And another"] }
        if layout == .bigNumber { content.number = "42%" }
        if layout == .quote { content.quote = "A line worth remembering"; content.attribution = "Who said it" }
        if layout == .chart { content.chart = [ChartPoint(label: "Q1", value: 12), ChartPoint(label: "Q2", value: 18), ChartPoint(label: "Q3", value: 27)] }
        if layout == .table { content.table = [["Plan", "Price"], ["Solo", "$12"], ["Team", "$40"]] }
        let slide = Slide(layout: layout, content: content, theme: theme)
        let index = min(slideIndex + 1, deck?.slides.count ?? 0)
        change { $0.slides.insert(slide, at: index) }
        showSlide(index)
    }

    /// A slide another agent wrote (James's sources slide), after the current one or at the end.
    func insertSlide(_ layout: SlideLayout, content: SlideContent, notes: String = "", atEnd: Bool = false) {
        guard let theme = deck?.theme else { return }
        let slide = Slide(layout: layout, content: content, notes: notes, theme: theme)
        let index = atEnd ? (deck?.slides.count ?? 0) : min(slideIndex + 1, deck?.slides.count ?? 0)
        change { $0.slides.insert(slide, at: index) }
        showSlide(index)
    }

    func duplicateSlide(_ index: Int) {
        guard let deck, deck.slides.indices.contains(index) else { return }
        var copy = deck.slides[index]
        copy.id = UUID()
        copy.canvas.id = UUID()
        change { $0.slides.insert(copy, at: index + 1) }
        showSlide(index + 1)
    }

    func deleteSlide(_ index: Int) {
        guard let deck, deck.slides.count > 1, deck.slides.indices.contains(index) else { return }
        change { $0.slides.remove(at: index) }
        showSlide(min(index, (self.deck?.slides.count ?? 1) - 1))
    }

    func moveSlide(_ index: Int, by offset: Int) {
        guard let deck, deck.slides.indices.contains(index), deck.slides.indices.contains(index + offset) else { return }
        change { $0.slides.swapAt(index, index + offset) }
        showSlide(index + offset)
    }

    func toggleHidden(_ index: Int) {
        change { deck in
            guard deck.slides.indices.contains(index) else { return }
            deck.slides[index].hidden.toggle()
        }
    }

    func setPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let id = assets.add(data)
        updateContent { $0.image = id }
    }

    // MARK: New decks

    func newDeck(outline: String? = nil, name: String = "Untitled deck", theme: DeckTheme = .paper) {
        flushSave()
        var slides = outline.map { DeckOutline.slides(from: $0, theme: theme) } ?? []
        if slides.isEmpty {
            var content = SlideContent()
            content.title = name
            content.subtitle = "Subtitle"
            slides = [Slide(layout: .title, content: content, theme: theme)]
        }
        let title = slides.first?.content.title.isEmpty == false ? slides[0].content.title : name
        let fresh = SlideDeck(name: title, theme: theme, slides: slides)
        write(fresh)
        deck = fresh
        showSlide(0)
    }

    /// A deck from a document in Write: headings become slides, lists become bullets.
    func newDeck(fromDocument markdown: String, title: String) {
        var outline = markdown
        if !outline.hasPrefix("# ") { outline = "# \(title)\n\n" + outline }
        newDeck(outline: outline, name: title)
        notice = "Made \(deck?.slides.count ?? 0) slides from \u{201C}\(title)\u{201D}. Each one can be changed."
    }

    /// Conner writes an outline from a description; the layouts are the canvas's.
    func ask(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let system = """
        You are Conner, the business agent inside 11am, outlining a presentation. Reply with a Markdown outline only:
        "# Title" then a subtitle line; then "## Slide heading" for each slide with 2 to 4 "- " bullets of at most 10 words.
        A heading that is a number (like "## $1.2m ARR") becomes a big-number slide. "> quote — person" makes a quote slide.
        A list of "- Label: number" lines becomes a bar chart. Add "Notes: …" lines with what to say. 8 to 12 slides.
        Never invent customer names, numbers or quotes the person didn't give you; use placeholders like [number] instead.
        """
        let run = brain.run(BrainRequest(system: system, prompt: "The deck is for: \(request)", weight: .deep))
        askRun = run
        Task { [weak self] in
            await run.finished()
            guard let self, self.askRun === run, case .done = run.status else { return }
            var outline = run.text
            if let start = outline.range(of: "```") {
                let body = String(outline[start.upperBound...].drop { $0 != "\n" })
                outline = body.components(separatedBy: "```").first ?? body
            }
            self.newDeck(outline: outline, name: "New deck", theme: self.deck?.theme ?? .paper)
            self.notice = "Conner drafted \(self.deck?.slides.count ?? 0) slides. Check every number before you present."
            self.askRun = nil
        }
    }

    /// Shorter, sharper words for the current slide.
    func sharpen() {
        guard let slide else { return }
        let words = ([slide.content.title, slide.content.subtitle] + slide.content.bullets).filter { !$0.isEmpty }.joined(separator: "\n")
        let system = "You are Conner. Rewrite slide text to be shorter and sharper. Keep the same number of lines, same facts, no new numbers. Reply with the lines only."
        let run = brain.run(BrainRequest(system: system, prompt: words, weight: .quick))
        askRun = run
        let index = slideIndex
        Task { [weak self] in
            await run.finished()
            guard let self, case .done = run.status, self.slideIndex == index else { return }
            let lines = run.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*")) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            self.updateContent { content in
                var queue = lines
                if !content.title.isEmpty, !queue.isEmpty { content.title = queue.removeFirst() }
                if !content.subtitle.isEmpty, !queue.isEmpty { content.subtitle = queue.removeFirst() }
                content.bullets = content.bullets.map { bullet in queue.isEmpty ? bullet : queue.removeFirst() }
            }
            self.askRun = nil
        }
    }

    func writeNotes() {
        guard let slide else { return }
        let words = ([slide.content.title, slide.content.subtitle, slide.content.number, slide.content.quote] + slide.content.bullets).filter { !$0.isEmpty }.joined(separator: "\n")
        let system = "You are Conner. Write speaker notes for this slide: three or four short sentences in plain spoken English, using only what the slide says."
        let run = brain.run(BrainRequest(system: system, prompt: words, weight: .quick))
        askRun = run
        let index = slideIndex
        Task { [weak self] in
            await run.finished()
            guard let self, case .done = run.status, self.slideIndex == index else { return }
            self.setNotes(run.text.trimmingCharacters(in: .whitespacesAndNewlines))
            self.askRun = nil
        }
    }

    // MARK: Export

    enum Export: String, CaseIterable, Identifiable {
        case pdf, pptx, png
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pdf: return "PDF"
            case .pptx: return "PowerPoint (.pptx)"
            case .png: return "Pictures of each slide (PNG)"
            }
        }
    }

    var images: CanvasImages { { [assets] id in assets.image(id) } }

    func export(_ kind: Export) {
        guard let deck else { return }
        flushSave()
        switch kind {
        case .png:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Save here"
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            for (index, slide) in deck.visibleSlides.enumerated() {
                if let data = CanvasRenderer.png(slide.canvas, images: images) {
                    try? data.write(to: folder.appendingPathComponent("\(deck.name) \(index + 1).png"))
                }
            }
            notice = "Saved \(deck.visibleSlides.count) pictures."
        case .pdf, .pptx:
            let panel = NSSavePanel()
            let ext = kind == .pdf ? "pdf" : "pptx"
            panel.nameFieldStringValue = deck.name.replacingOccurrences(of: "/", with: "-") + "." + ext
            if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let data = kind == .pdf ? CanvasRenderer.pdf(deck.visibleSlides.map(\.canvas), images: images)
                                    : PPTXWriter.data(deck, imageData: { [assets] id in assets.data(id) })
            do {
                try data.write(to: url, options: .atomic)
                notice = "Saved \(url.lastPathComponent)."
            } catch {
                notice = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Presenting

    func present(from index: Int? = nil) {
        guard let deck, !deck.visibleSlides.isEmpty else { return }
        flushSave()
        Presenter.shared.start(deck: deck, from: index ?? visibleIndex(for: slideIndex), images: images) { [weak self] in
            self?.presenting = false
        }
        presenting = true
    }

    private func visibleIndex(for index: Int) -> Int {
        guard let deck else { return 0 }
        let id = deck.slides.indices.contains(index) ? deck.slides[index].id : nil
        return deck.visibleSlides.firstIndex { $0.id == id } ?? 0
    }
}

enum DecksSamples {
    static let pitch = """
    # 11am
    Software you own, on the Mac you have

    ## The problem
    - A founder pays for eleven subscriptions
    - None of them talk to each other
    - Everything they know is scattered across them
    Notes: Start with the bill. Most founders have never added it up.

    ## $4,200 a year
    What a five-person team spends on the software 11am replaces

    ## What 11am does
    - Mail, calendar, documents, sheets and books in one app
    - Eleven agents that do the busywork overnight
    - Runs on the Mac, so it's fast and private
    Notes: Show the notch, then the brief.

    > It gave me back a day a week — Priya, Head of Ops at Acme

    ## Customers by month
    - Jul: 12
    - Aug: 19
    - Sep: 31
    - Oct: 48

    ## Pricing
    | Plan | Price | Who it's for |
    | --- | --- | --- |
    | Solo | $12 a month | One founder |
    | Team | $40 a month | Up to ten people |

    ## The plan
    - Nov: Mail, calendar and documents
    - Jan: Sheets, books and design
    - Mar: iPhone and the language course
    - Jun: 1,000 paying teams

    ## The team
    - Sam Lee — Product and design
    - Alex Chen — Engineering
    - Priya Nair — Customers

    ## Thank you
    hello@11am.app
    """
}

/// Full-screen slides with the arrow keys, and a presenter view with notes, the next slide and a timer on a
/// second display when there is one.
@MainActor
final class Presenter: ObservableObject {
    static let shared = Presenter()

    @Published var index = 0
    @Published private(set) var slides: [Slide] = []
    @Published private(set) var started = Date()
    private(set) var images: CanvasImages = { _ in nil }
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var onEnd: (() -> Void)?

    func start(deck: SlideDeck, from start: Int, images: @escaping CanvasImages, onEnd: @escaping () -> Void) {
        stop()
        slides = deck.visibleSlides
        index = max(0, min(start, slides.count - 1))
        self.images = images
        self.onEnd = onEnd
        started = Date()
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else { return }
        let audience = screens.count > 1 ? (screens.first { $0 != main } ?? main) : main
        windows.append(makeWindow(on: audience, view: AnyView(SlideStage().environmentObject(self))))
        if screens.count > 1 {
            windows.append(makeWindow(on: main, view: AnyView(PresenterStage().environmentObject(self))))
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.windows.isEmpty else { return event }
            switch event.keyCode {
            case 124, 125, 49, 36, 121: self.next()      // → ↓ space return page-down
            case 123, 126, 51, 116: self.previous()      // ← ↑ delete page-up
            case 53: self.stop()                         // escape
            default: return event
            }
            return nil
        }
    }

    private func makeWindow(on screen: NSScreen, view: AnyView) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.level = .screenSaver
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return window
    }

    func next() {
        if index < slides.count - 1 { index += 1 } else { stop() }
    }

    func previous() {
        if index > 0 { index -= 1 }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        let end = onEnd
        onEnd = nil
        end?()
    }
}

private struct SlideStage: View {
    @EnvironmentObject private var presenter: Presenter

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if presenter.slides.indices.contains(presenter.index) {
                    let slide = presenter.slides[presenter.index]
                    let height = min(proxy.size.height, proxy.size.width / CGFloat(slide.canvas.size.aspect))
                    CanvasThumbnail(document: slide.canvas, images: presenter.images, height: height)
                        .id(slide.id)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: presenter.index)
            .contentShape(Rectangle())
            .onTapGesture { presenter.next() }
        }
        .ignoresSafeArea()
    }
}

private struct PresenterStage: View {
    @EnvironmentObject private var presenter: Presenter

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    if presenter.slides.indices.contains(presenter.index) {
                        let slide = presenter.slides[presenter.index]
                        CanvasThumbnail(document: slide.canvas, images: presenter.images, height: 380)
                        ScrollView {
                            Text(slide.notes.isEmpty ? "No notes for this slide." : slide.notes)
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(slide.notes.isEmpty ? 0.4 : 0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(elapsed(context.date))
                        .font(.system(size: 54, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("Slide \(presenter.index + 1) of \(presenter.slides.count)")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                    if presenter.slides.indices.contains(presenter.index + 1) {
                        Text("Next").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        CanvasThumbnail(document: presenter.slides[presenter.index + 1].canvas, images: presenter.images, height: 200)
                    }
                    Spacer()
                    Text("← → to move · esc to stop").font(.system(size: 15)).foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: 380, alignment: .leading)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
        }
    }

    private func elapsed(_ now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(presenter.started))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
