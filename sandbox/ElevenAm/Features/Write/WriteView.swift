import AppKit
import SwiftUI

extension DocEditorStyle {
    /// The editor's look from the vellum theme: ink on paper, a quiet blue for links.
    @MainActor
    static func from(_ theme: Theme, _ scheme: ColorScheme, font: NSFont) -> DocEditorStyle {
        DocEditorStyle(
            body: font,
            ink: NSColor(theme.ink(scheme)),
            secondary: NSColor(theme.inkSecondary(scheme)),
            tertiary: NSColor(theme.inkTertiary(scheme)),
            accent: scheme == .dark ? NSColor(srgbRed: 0.56, green: 0.71, blue: 0.96, alpha: 1) : NSColor(srgbRed: 0.15, green: 0.35, blue: 0.68, alpha: 1),
            shade: NSColor(theme.ink(scheme).opacity(scheme == .dark ? 0.08 : 0.05)),
            highlight: NSColor(srgbRed: 1, green: 0.86, blue: 0.3, alpha: scheme == .dark ? 0.32 : 0.45)
        )
    }
}

/// William's app: a quiet page with a margin rule. The writing is the interface.
struct WriteView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @EnvironmentObject private var voice: VoiceProfile
    @Environment(\.colorScheme) private var scheme
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var showsVoice = false
    @State private var importing = false
    @State private var showingPageSetup = false
    @StateObject private var editor = DocEditorController()
    @AppStorage("write.outline") private var showsOutline = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "write", subtitle: "William writes like you, so you only review.") {
                HStack(spacing: 8) {
                    Button("Your voice") { showsVoice.toggle() }
                        .buttonStyle(.vellumSecondary)
                        .popover(isPresented: $showsVoice, arrowEdge: .bottom) {
                            VoiceEditor()
                                .environmentObject(theme)
                                .environmentObject(voice)
                        }
                    Button {
                        importing = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Open Word, RTF, HTML, OpenDocument or Markdown files as documents")
                    exportMenu
                    newMenu
                }
            }

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 14) {
                    DocumentList()
                        .frame(width: 160)
                    ZStack {
                        if let document = write.selected {
                            Page(document: document, selection: $selection, editor: editor, showsOutline: $showsOutline)
                                .id(document.id)
                                .transition(.rise(theme.rise))
                        } else {
                            VStack(spacing: 10) {
                                AgentLogo(code: "wm", size: 44, color: theme.inkTertiary(scheme))
                                Text("Start a new document.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // On a narrow window the comments float over the page instead.
                    .overlay(alignment: .topTrailing) {
                        if write.showsComments, proxy.size.width <= 860, let document = write.selected {
                            DocCommentsPanel(document: document, editor: editor)
                                .padding(12)
                                .frame(width: 270)
                                .frame(maxHeight: proxy.size.height - 60)
                                .vellum(level: 1, radius: max(theme.radius - 2, 10))
                                .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
                                .padding(.top, 44)
                                .padding(.trailing, 10)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    // The outline (or the comments) step aside when the page would get too narrow.
                    if write.showsComments, proxy.size.width > 860, let document = write.selected {
                        DocCommentsPanel(document: document, editor: editor)
                            .frame(width: 250)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if showsOutline, proxy.size.width > 860, let document = write.selected {
                        OutlineList(markdown: document.text) { editor.scroll(to: $0) }
                            .frame(width: 150)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .padding(24)
        .animation(theme.spring, value: write.selectedID)
        .animation(theme.spring, value: showsOutline)
        .animation(theme.spring, value: write.showsComments)
        .sheet(isPresented: $write.showsDraft) {
            DraftSheet()
                .environmentObject(write)
                .environmentObject(theme)
        }
        .onChange(of: write.selectedID) { _, _ in selection = NSRange(location: 0, length: 0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: WriteModel.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { write.importFiles(urls) }
        }
        .sheet(isPresented: $showingPageSetup) {
            PageSetupView()
                .environmentObject(write)
                .environmentObject(theme)
        }
    }

    private var exportMenu: some View {
        Menu {
            ForEach(WriteExport.allCases) { kind in
                Button(kind.title) { write.export(kind) }
            }
            Divider()
            Button("Copy with formatting") { write.copyRichText() }
            Button("Page setup…") { showingPageSetup = true }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .disabled(write.selected == nil)
    }

    private var newMenu: some View {
        Menu {
            Button("Blank document") { withAnimation(theme.spring) { write.newDocument() } }
            Button("Draft from my notes and files…") { write.showsDraft = true }
            Divider()
            ForEach(DocTemplate.all) { template in
                Button {
                    withAnimation(theme.spring) { write.newDocument(template: template) }
                } label: {
                    Label(template.name, systemImage: template.symbol)
                }
            }
        } label: {
            Label("New", systemImage: "plus")
        } primaryAction: {
            withAnimation(theme.spring) { write.newDocument() }
        }
        .menuStyle(.button)
        .fixedSize()
        .help("A blank document, or choose a template")
    }
}

private struct DocumentList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(Array(write.documents.enumerated()), id: \.element.id) { index, document in
                    DocumentRow(document: document, selected: write.selectedID == document.id)
                        .entrance(index)
                        .contextMenu {
                            Button("Duplicate") { withAnimation(theme.spring) { write.duplicate(document.id) } }
                            Divider()
                            Button("Delete", role: .destructive) {
                                withAnimation(theme.spring) { write.delete(document.id) }
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct DocumentRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    var selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            write.selectedID = document.id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(theme.ink(scheme))
                Text(document.modified.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: max(theme.radius - 3, 7), style: .continuous)
                    .fill(selected ? theme.raised(scheme) : (hovering ? theme.well(scheme).opacity(0.7) : Color.clear))
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(theme.radius - 3, 7), style: .continuous)
                    .strokeBorder(selected ? theme.edge(scheme) : Color.clear, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
    }
}

/// The headings, to jump around a long document.
struct OutlineList: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var markdown: String
    var jump: (Int) -> Void

    var body: some View {
        let headings = MarkdownInfo.outline(markdown)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Outline")
                .padding(.leading, 4)
            if headings.isEmpty {
                Text("Headings show up here. ⌥⌘1 makes one.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(headings) { heading in
                        Button {
                            jump(heading.location)
                        } label: {
                            Text(heading.title)
                                .font(.system(size: heading.level <= 1 ? 12.5 : 12, weight: heading.level <= 1 ? .semibold : .regular))
                                .foregroundStyle(heading.level <= 2 ? theme.ink(scheme) : theme.inkSecondary(scheme))
                                .lineLimit(2)
                                .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 10 + 4)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 4)
    }
}

/// The sheet you write on: format bar, a margin rule, the text, and William's tools along the bottom.
private struct Page: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    @Binding var selection: NSRange
    @ObservedObject var editor: DocEditorController
    @Binding var showsOutline: Bool
    @AppStorage("write.focus") private var focusMode = false
    @AppStorage("write.typewriter") private var typewriter = false
    @State private var showingVersions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                FormatBar(editor: editor)
                Spacer(minLength: 6)
                ToolButton(symbol: "magnifyingglass", help: "Find and replace · ⌘F") { editor.showFind() }
                ToolButton(symbol: "scope", help: "Focus: dim everything but this paragraph", on: focusMode) { focusMode.toggle() }
                ToolButton(symbol: "text.aligncenter", help: "Typewriter: keep the line you're on in the middle", on: typewriter) { typewriter.toggle() }
                CommentButton(document: document, selection: selection)
                WilliamMenu()
                CiteButton(document: document, editor: editor)
                ToolButton(symbol: "clock.arrow.circlepath", help: "Versions") { showingVersions = true }
                    .popover(isPresented: $showingVersions, arrowEdge: .bottom) {
                        VersionsView(documentID: document.id)
                            .environmentObject(write)
                            .environmentObject(theme)
                    }
                ToolButton(symbol: "sidebar.right", help: "Outline", on: showsOutline) { showsOutline.toggle() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)

            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(theme.ink(scheme).opacity(0.14))
                    .frame(width: 1)
                    .padding(.trailing, 20)
                DocEditor(
                    text: Binding(
                        get: { write.selected?.text ?? "" },
                        set: { write.update(document.id, text: $0) }
                    ),
                    selection: $selection,
                    style: .from(theme, scheme, font: Page.writingFont),
                    controller: editor,
                    focusMode: focusMode,
                    typewriter: typewriter,
                    baseURL: write.folder,
                    onAttach: { [document] data, name in write.attach(data, named: name, to: document.id) },
                    onCite: { keys in research.openSource(keys: keys) },
                    highlights: write.commentRanges(for: document.id)
                )
            }
            .padding(.leading, 30)
            .padding(.trailing, 24)
            .frame(maxWidth: 760, maxHeight: .infinity)
            .frame(maxWidth: .infinity)

            if let notice = write.notice {
                HStack {
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                    Spacer()
                    Button("Dismiss") { write.notice = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
            toolbar
        }
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .overlay(alignment: .bottom) {
            if let job = write.william, job.documentID == nil || job.documentID == document.id {
                WilliamJobCard(job: job)
                    .padding(12)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(theme.spring, value: write.william?.id)
        .overlay(alignment: .bottom) {
            if let suggestion = write.suggestion, suggestion.documentID == document.id {
                SuggestionCard(suggestion: suggestion, run: suggestion.run)
                    .padding(12)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(theme.spring, value: write.suggestion?.id)
    }

    private var toolbar: some View {
        let stats = MarkdownInfo.stats(document.text)
        return HStack(spacing: 6) {
            Text(selection.length > 0 ? "Selection" : "Whole draft")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 72, alignment: .leading)
            // Full labels when there's room, icons when the page is narrow.
            ViewThatFits(in: .horizontal) {
                actions(showTitles: true)
                actions(showTitles: false)
            }
            Spacer(minLength: 8)
            Text("\(stats.words) words · \(stats.readingMinutes) min")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .contentTransition(.numericText())
                .fixedSize()
                .help("\(stats.characters) characters")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func actions(showTitles: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(WriteAction.allCases) { action in
                Button {
                    write.suggest(action, selection: selection)
                } label: {
                    if showTitles {
                        Label(action.title, systemImage: action.symbol)
                    } else {
                        Image(systemName: action.symbol)
                    }
                }
                .buttonStyle(.vellumSecondary)
                .help(action.title)
                .disabled(write.suggestion != nil || brain.isBusy)
            }
        }
        .fixedSize()
    }

    /// New York for the writing itself: it reads like paper.
    static let writingFont: NSFont = DocTypography.serif(15.5)
}

/// Bold, italic, headings, lists and the rest, on the page.
struct FormatBar: View {
    @ObservedObject var editor: DocEditorController
    var compact = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            full
            short
        }
    }

    private var full: some View {
        HStack(spacing: 2) {
            styleMenu
            Divider().frame(height: 16).padding(.horizontal, 3)
            inlineButtons
            Divider().frame(height: 16).padding(.horizontal, 3)
            ToolButton(symbol: "list.bullet", help: "Bullets · ⇧⌘8") { editor.perform(.bullets) }
            ToolButton(symbol: "list.number", help: "Numbers · ⇧⌘7") { editor.perform(.numbers) }
            ToolButton(symbol: "checklist", help: "Checklist · ⇧⌘L") { editor.perform(.checklist) }
            ToolButton(symbol: "text.quote", help: "Quote · ⇧⌘.") { editor.perform(.quote) }
            Divider().frame(height: 16).padding(.horizontal, 3)
            insertMenu
        }
        .fixedSize()
    }

    private var short: some View {
        HStack(spacing: 2) {
            styleMenu
            ToolButton(symbol: "bold", help: "Bold · ⌘B") { editor.perform(.bold) }
            ToolButton(symbol: "italic", help: "Italic · ⌘I") { editor.perform(.italic) }
            ToolButton(symbol: "link", help: "Link · ⌘K") { editor.perform(.link) }
            Menu {
                Button("Bullets") { editor.perform(.bullets) }
                Button("Numbers") { editor.perform(.numbers) }
                Button("Checklist") { editor.perform(.checklist) }
                Button("Quote") { editor.perform(.quote) }
                Divider()
                Button("Underline") { editor.perform(.underline) }
                Button("Strikethrough") { editor.perform(.strike) }
                Button("Highlight") { editor.perform(.highlight) }
                Button("Code") { editor.perform(.code) }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 26)
            insertMenu
        }
        .fixedSize()
    }

    private var inlineButtons: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "bold", help: "Bold · ⌘B") { editor.perform(.bold) }
            ToolButton(symbol: "italic", help: "Italic · ⌘I") { editor.perform(.italic) }
            ToolButton(symbol: "underline", help: "Underline · ⌘U") { editor.perform(.underline) }
            ToolButton(symbol: "strikethrough", help: "Strikethrough · ⇧⌘X") { editor.perform(.strike) }
            ToolButton(symbol: "highlighter", help: "Highlight · ⇧⌘H") { editor.perform(.highlight) }
            ToolButton(symbol: "chevron.left.forwardslash.chevron.right", help: "Code · ⌘E") { editor.perform(.code) }
            ToolButton(symbol: "link", help: "Link · ⌘K") { editor.perform(.link) }
        }
    }

    private var styleMenu: some View {
        Menu {
            Button("Body text") { editor.perform(.heading(0)) }
            Button("Title") { editor.perform(.heading(1)) }
            Button("Heading") { editor.perform(.heading(2)) }
            Button("Subheading") { editor.perform(.heading(3)) }
        } label: {
            Text("Aa")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Heading styles · ⌥⌘1, 2, 3; ⌥⌘0 for body text")
    }

    private var insertMenu: some View {
        Menu {
            Button("Table") { editor.perform(.table) }
            Button("Divider") { editor.perform(.divider) }
            Button("Code block") { editor.perform(.codeBlock) }
        } label: {
            Image(systemName: "plus.square.on.square")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert a table, divider or code block")
    }
}

struct ToolButton: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var symbol: String
    var help: String
    var on = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? theme.paper(scheme) : theme.inkSecondary(scheme))
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? theme.ink(scheme) : (hovering ? theme.well(scheme) : Color.clear))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Named versions and the ones kept while you write. Restoring keeps what you had as a version too.
private struct VersionsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    var documentID: UUID
    @State private var name = ""

    var body: some View {
        let versions = write.versions(for: documentID)
        VStack(alignment: .leading, spacing: 10) {
            Text("Versions")
                .font(theme.display(18))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 6) {
                TextField("Name this version", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .buttonStyle(.vellumPrimary)
            }
            if versions.isEmpty {
                Text("A version is kept every 15 minutes while you write, and whenever you save one here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(versions) { version in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(version.name ?? version.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(theme.ink(scheme))
                                Text(version.name == nil ? version.date.formatted(.relative(presentation: .named)) : version.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            Spacer()
                            Button("Restore") { write.restore(version) }
                                .buttonStyle(.vellumSecondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func save() {
        write.saveVersion(named: name.isEmpty ? nil : name)
        name = ""
    }
}

/// Paper, orientation, margins, header and page numbers for PDF and Word export.
private struct PageSetupView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Page setup")
                .font(theme.display(22))
                .foregroundStyle(theme.ink(scheme))
            Text("Used when you export a PDF or a Word file.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkTertiary(scheme))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Paper").gridColumnAlignment(.trailing)
                    Picker("", selection: $write.pageSetup.paper) {
                        ForEach(PageSetup.Paper.allCases) { paper in Text(paper.title).tag(paper) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Orientation")
                    Picker("", selection: $write.pageSetup.landscape) {
                        Text("Portrait").tag(false)
                        Text("Landscape").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("Margins")
                    Picker("", selection: $write.pageSetup.margin) {
                        Text("Narrow").tag(36.0)
                        Text("Normal").tag(64.0)
                        Text("Wide").tag(90.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                GridRow {
                    Text("")
                    Toggle("Title at the top of each page after the first", isOn: $write.pageSetup.showsTitle)
                }
                GridRow {
                    Text("")
                    Toggle("Page numbers", isOn: $write.pageSetup.pageNumbers)
                }
            }
            .font(.system(size: 12.5))
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Export PDF…") {
                    dismiss()
                    DispatchQueue.main.async { write.export(.pdf) }
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

/// William's proposed change, floating over the page. Accept with ⌘Return, reject with Esc.
private struct SuggestionCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    let suggestion: WriteSuggestion
    @ObservedObject var run: BrainRun
    @State private var textHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "wm", size: 22)
                Text("William · \(suggestion.action.title)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                if !run.providerLabel.isEmpty {
                    ModelBadge(label: run.providerLabel, isLocal: run.isLocal)
                }
            }
            if suggestion.action != .continueWriting {
                Text(suggestion.original.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12))
                    .strikethrough(true, color: theme.inkTertiary(scheme))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(3)
            }
            ScrollView {
                Group {
                    if run.text.isEmpty {
                        RunView(run: run)
                    } else {
                        Text(run.text)
                            .font(.system(size: 14, design: .serif))
                            .lineSpacing(4)
                            .foregroundStyle(theme.ink(scheme))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .readHeight { textHeight = $0 }
            }
            .frame(height: min(max(textHeight, 20), 180))

            HStack(spacing: 8) {
                Button("Reject") { withAnimation(theme.spring) { write.rejectSuggestion() } }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Accept") { withAnimation(theme.spring) { write.acceptSuggestion() } }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(run.status != .done)
                Spacer()
                Text("⌘↩ accept · esc reject")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(16)
        .frame(maxWidth: 620)
        .vellum(level: 2, radius: max(theme.radius - 2, 8), blending: .withinWindow)
    }
}

/// The notes William and Marc write with.
private struct VoiceEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var voice: VoiceProfile
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "wm", size: 24)
                Text("Your voice")
                    .font(theme.display(18))
                    .foregroundStyle(theme.ink(scheme))
            }
            Text("William and Marc write with these notes. The full version learns from your sent mail and documents, on this Mac.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            SectionLabel(text: "How you write")
            field($voice.notes, height: 84)

            SectionLabel(text: "Samples of your writing · optional")
            field($voice.samples, height: 110)

            Button("Reset notes") { voice.notes = VoiceProfile.defaultNotes }
                .buttonStyle(.vellumSecondary)
        }
        .padding(16)
        .frame(width: 380)
    }

    private func field(_ text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12.5))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
            }
    }
}
