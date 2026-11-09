import AppKit
import SwiftUI

/// Conner's decks: slides down the side, the slide on the canvas with its notes, and what it says and how it looks.
struct DecksView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @EnvironmentObject private var write: WriteModel
    @EnvironmentObject private var studio: DesignStudio
    @Environment(\.colorScheme) private var scheme
    @State private var asking = false
    @State private var outlining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "decks", subtitle: subtitle) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(DeckTheme.all) { item in
                            Button(item.name) { withAnimation(theme.spring) { decks.setTheme(item) } }
                        }
                        Divider()
                        Button("From the brand kit") { withAnimation(theme.spring) { decks.setTheme(.brand(studio.brand)) } }
                    } label: {
                        Label(decks.deck?.theme.name ?? "Theme", systemImage: "paintpalette")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                    DeckSourcesMenu()
                        .disabled(decks.deck == nil)
                    Menu {
                        ForEach(DecksModel.Export.allCases) { kind in
                            Button(kind.title + "…") { decks.export(kind) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .help("Export")
                    newMenu
                    Button {
                        decks.present()
                    } label: {
                        Label("Present", systemImage: "play.fill")
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.return, modifiers: [.command, .option])
                    .disabled(decks.deck == nil)
                }
            }

            if let notice = decks.notice {
                HStack(spacing: 10) {
                    AgentLogo(code: "cr", size: 18, color: theme.inkSecondary(scheme))
                    Text(notice).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme)).lineLimit(2)
                    Spacer()
                    Button { decks.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))
            }

            if decks.deck != nil {
                HStack(alignment: .top, spacing: 14) {
                    SlideSorter()
                        .frame(width: 156)
                    VStack(spacing: 8) {
                        CanvasToolbar(controller: decks.controller, brand: studio.brand, addPicture: addPicture)
                        CanvasEditorView(controller: decks.controller, backdrop: .clear, accent: NSColor(theme.ink(scheme)))
                            .background { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme)) }
                            .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
                        NotesField()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    SlidePanel(controller: decks.controller)
                        .frame(width: 236)
                        .vellum(level: 3, radius: max(theme.radius - 4, 8))
                }
            } else {
                VStack(spacing: 10) {
                    AgentLogo(code: "cr", size: 44, color: theme.inkTertiary(scheme))
                    Text("No deck yet. Start one, or ask Conner for a draft.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .animation(theme.spring, value: decks.notice)
        .task(id: decks.notice) {
            guard decks.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            decks.notice = nil
        }
        .onDisappear { decks.flushSave() }
        .sheet(isPresented: $outlining) { OutlineSheet(done: { outlining = false }).environmentObject(decks).environmentObject(theme) }
        .popover(isPresented: $asking) { AskConner(done: { asking = false }).environmentObject(decks).environmentObject(theme) }
    }

    private var subtitle: String {
        guard let deck = decks.deck else { return "Conner · slides from an outline, presented or sent as PowerPoint" }
        let hidden = deck.slides.filter(\.hidden).count
        return "\(deck.name) · \(deck.slides.count) slides\(hidden > 0 ? ", \(hidden) hidden" : "") · \(deck.theme.name)"
    }

    private var newMenu: some View {
        Menu {
            Button("Blank deck") { decks.newDeck() }
            Button("From an outline…") { outlining = true }
            Button("Ask Conner for a draft…") { asking = true }
            if !write.documents.isEmpty {
                Menu("From a document in Write") {
                    ForEach(write.documents) { document in
                        Button(document.title) { decks.newDeck(fromDocument: document.text, title: document.title) }
                    }
                }
            }
            Divider()
            Menu("Open") {
                ForEach(decks.entries) { entry in
                    Button("\(entry.name) · \(entry.slides) slides") { decks.open(entry.id) }
                }
            }
            if let deck = decks.deck {
                Button("Move \u{201C}\(deck.name)\u{201D} to the Trash") { decks.delete(deck.id) }
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.vellumSecondary)
        .fixedSize()
    }

    private func addPicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let data = try? Data(contentsOf: url) { decks.controller.addImage(data) }
        }
    }
}

// MARK: Slides

private struct SlideSorter: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(SlideLayout.allCases) { layout in
                    Button {
                        decks.addSlide(layout)
                    } label: {
                        Label(layout.title, systemImage: layout.symbol)
                    }
                }
            } label: {
                Label("Add a slide", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.vellumSecondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        let slides = decks.deck?.slides ?? []
                        ForEach(slides.indices, id: \.self) { index in
                            thumbnail(index, slides[index])
                                .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: decks.slideIndex) { _, index in withAnimation { proxy.scrollTo(index, anchor: .center) } }
            }
        }
    }

    private func thumbnail(_ index: Int, _ slide: Slide) -> some View {
        let selected = index == decks.slideIndex
        let canvas = selected ? decks.controller.document : slide.canvas
        let images = decks.images
        return Button {
            decks.showSlide(index)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 18, alignment: .trailing)
                CanvasThumbnail(document: canvas, images: images, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(selected ? theme.ink(scheme) : theme.edge(scheme), lineWidth: selected ? 2 : 0.5)
                    }
                    .opacity(slide.hidden ? 0.35 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if slide.hidden {
                            Image(systemName: "eye.slash.fill").font(.system(size: 10)).padding(4).foregroundStyle(theme.ink(scheme))
                        }
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplicate") { decks.duplicateSlide(index) }
            Button(slide.hidden ? "Show in the presentation" : "Skip in the presentation") { decks.toggleHidden(index) }
            Button("Move up") { decks.moveSlide(index, by: -1) }.disabled(index == 0)
            Button("Move down") { decks.moveSlide(index, by: 1) }.disabled(index >= (decks.deck?.slides.count ?? 1) - 1)
            Button("Present from here") { decks.showSlide(index); decks.present() }
            Divider()
            Button("Delete slide") { decks.deleteSlide(index) }.disabled((decks.deck?.slides.count ?? 1) <= 1)
        }
    }
}

private struct NotesField: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme
    @State private var notes = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(theme.inkTertiary(scheme))
                .padding(.top, 2)
            TextField("Speaker notes for this slide", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(2...4)
                .onChange(of: notes) { _, value in
                    if value != decks.slide?.notes { decks.setNotes(value) }
                }
            Button("Write them") { decks.writeNotes() }
                .buttonStyle(.vellumSecondary)
                .help("Conner writes notes from what the slide says")
        }
        .padding(10)
        .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)) }
        .onAppear { notes = decks.slide?.notes ?? "" }
        .onChange(of: decks.slideIndex) { _, _ in notes = decks.slide?.notes ?? "" }
        .onChange(of: decks.slide?.notes) { _, value in if value != notes { notes = value ?? "" } }
    }
}

private struct SlidePanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @EnvironmentObject private var studio: DesignStudio
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: CanvasController
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Slide").tag(0)
                Text("Design").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            if tab == 0 {
                SlideContentEditor()
                    .id(decks.slide?.id)
            } else {
                CanvasInspector(controller: controller, brand: studio.brand)
            }
        }
        .onChange(of: controller.selection) { _, selection in if !selection.isEmpty { tab = 1 } }
    }
}

private struct SlideContentEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme
    @State private var title = ""
    @State private var subtitle = ""
    @State private var bullets = ""
    @State private var secondary = ""
    @State private var number = ""
    @State private var caption = ""
    @State private var quote = ""
    @State private var attribution = ""
    @State private var chart = ""
    @State private var table = ""
    /// Set once the fields hold the slide's words, so filling them doesn't count as an edit.
    @State private var ready = false

    var body: some View {
        let layout = decks.slide?.layout ?? .bullets
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Layout")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(SlideLayout.allCases) { item in
                        Button {
                            withAnimation(theme.spring) { decks.setLayout(item) }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: item.symbol).font(.system(size: 13))
                                Text(item.title).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(item == layout ? theme.paper(scheme) : theme.inkSecondary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(item == layout ? theme.ink(scheme) : theme.well(scheme)) }
                        }
                        .buttonStyle(.plain)
                        .help(item.title)
                    }
                }
                if decks.slide?.customised == true {
                    HStack {
                        Text("Edited by hand").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                        Spacer()
                        Button("Reset layout") { withAnimation(theme.spring) { decks.resetLayout() } }
                            .buttonStyle(.vellumSecondary)
                    }
                }
                field("Title", $title) { value in decks.updateContent { $0.title = value } }
                if [.title, .section, .statement, .closing].contains(layout) {
                    field("Subtitle", $subtitle) { value in decks.updateContent { $0.subtitle = value } }
                }
                if [.bullets, .twoColumns, .team, .timeline].contains(layout) {
                    lines(layout == .team ? "People (Name — role), one per line" : (layout == .timeline ? "Steps (When: what), one per line" : "Points, one per line"), $bullets) { value in
                        decks.updateContent { $0.bullets = Self.split(value) }
                    }
                }
                if layout == .twoColumns {
                    lines("Second column", $secondary) { value in decks.updateContent { $0.secondary = Self.split(value) } }
                }
                if layout == .bigNumber {
                    field("Number", $number) { value in decks.updateContent { $0.number = value } }
                }
                if [.bigNumber, .image, .chart].contains(layout) {
                    field("Caption", $caption) { value in decks.updateContent { $0.caption = value } }
                }
                if layout == .quote {
                    lines("Quote", $quote) { value in decks.updateContent { $0.quote = value } }
                    field("Who said it", $attribution) { value in decks.updateContent { $0.attribution = value } }
                }
                if layout == .chart {
                    lines("Bars (Label: number), one per line", $chart) { value in
                        decks.updateContent { content in
                            content.chart = Self.split(value).compactMap { line in
                                guard let colon = line.lastIndex(of: ":"), let number = Double(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")) else { return nil }
                                return ChartPoint(label: line[..<colon].trimmingCharacters(in: .whitespaces), value: number)
                            }
                        }
                    }
                }
                if layout == .table {
                    lines("Rows (cells split by |), first row is the header", $table) { value in
                        decks.updateContent { $0.table = Self.split(value).map { $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) } } }
                    }
                }
                if layout == .image {
                    Button(decks.slide?.content.image == nil ? "Choose a picture…" : "Change the picture…") { decks.setPicture() }
                        .buttonStyle(.vellumSecondary)
                }
                HStack {
                    Button {
                        decks.sharpen()
                    } label: {
                        Label("Sharper", systemImage: "sparkle")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Conner rewrites the words shorter, keeping the facts")
                    if let run = decks.askRun, !run.isFinished {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .padding(12)
        }
        .onAppear {
            refresh()
            DispatchQueue.main.async { ready = true }
        }
    }

    private func refresh() {
        guard let content = decks.slide?.content else { return }
        title = content.title
        subtitle = content.subtitle
        bullets = content.bullets.joined(separator: "\n")
        secondary = content.secondary.joined(separator: "\n")
        number = content.number
        caption = content.caption
        quote = content.quote
        attribution = content.attribution
        chart = content.chart.map { "\($0.label): \(ChartPoint.format($0.value))" }.joined(separator: "\n")
        table = content.table.map { $0.joined(separator: " | ") }.joined(separator: "\n")
    }

    static func split(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func field(_ label: String, _ text: Binding<String>, apply: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            TextField(label, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onChange(of: text.wrappedValue) { _, value in if ready { apply(value) } }
        }
    }

    private func lines(_ label: String, _ text: Binding<String>, apply: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            TextEditor(text: text)
                .font(.system(size: 12))
                .frame(minHeight: 90, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.well(scheme)) }
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
                .onChange(of: text.wrappedValue) { _, value in if ready { apply(value) } }
        }
    }
}

// MARK: New decks

private struct OutlineSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme
    var done: () -> Void
    @State private var outline = DecksSamples.pitch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A deck from an outline").font(theme.display(24)).foregroundStyle(theme.ink(scheme))
            Text("# for the title, ## for each slide, - for points. A heading that's a number makes a big number; \"- Label: 12\" lines make a chart; | rows make a table; > makes a quote; Notes: lines become speaker notes.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $outline)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)) }
            HStack {
                Text("\(DeckOutline.slides(from: outline, theme: .paper).count) slides").font(.system(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Cancel", action: done).buttonStyle(.vellumSecondary).keyboardShortcut(.cancelAction)
                Button("Make the deck") {
                    decks.newDeck(outline: outline, theme: decks.deck?.theme ?? .paper)
                    done()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
    }
}

private struct AskConner: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme
    var done: () -> Void
    @State private var request = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "cr", size: 20, color: theme.ink(scheme))
                Text("What's the deck for?").font(.system(size: 13, weight: .semibold))
            }
            AskField(placeholder: "e.g. a 10-slide seed pitch from my investor update", text: $request) { decks.ask(request) }
            if let run = decks.askRun { RunView(run: run) }
            Text("Conner drafts an outline and lays it out in your theme. He uses placeholders rather than inventing numbers.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 400)
        .onChange(of: decks.deck?.id) { _, _ in if decks.askRun == nil { done() } }
    }
}
