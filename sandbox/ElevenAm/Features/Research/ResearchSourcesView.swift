import AppKit
import SwiftUI

/// What a source says about itself, corrected by you, with its reference shown as it will be cited.
struct SourceEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var source: CitationSource
    @State private var authors: String
    @State private var date: String

    init(source: CitationSource) {
        _source = State(initialValue: source)
        _authors = State(initialValue: source.authors.map(\.full).joined(separator: "; "))
        _date = State(initialValue: source.published.map(ClipNote.dateText) ?? "")
    }

    private var edited: CitationSource {
        var copy = source
        copy.authors = authors.split(whereSeparator: { $0 == ";" || $0 == "\n" }).compactMap { PersonName.parse(String($0)) }
        copy.published = CiteDate.parse(date)
        return copy
    }

    private var containerLabel: String {
        switch source.kind {
        case .journal: return "Journal"
        case .news: return "Publication"
        case .book, .report: return "Publisher"
        case .webpage, .video: return "Site"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AgentLogo(code: "jm", size: 24)
                Text(research.library.contains { $0.id == source.id } ? "Source" : "New source")
                    .font(theme.display(20))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Picker("", selection: $source.kind) {
                    ForEach(SourceKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                row("Title") { TextField("Title", text: $source.title) }
                row("Authors") { TextField("Jane Citizen; Sam Lee, or an organisation", text: $authors) }
                row(containerLabel) { TextField(containerLabel, text: $source.container) }
                row("Published") {
                    HStack {
                        TextField("3 November 2026, 2026-11-03 or 2026", text: $date)
                        if !date.isEmpty && CiteDate.parse(date) == nil {
                            Text("Not a date").font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }
                }
                row("Address") { TextField("https://", text: $source.url) }
                if source.kind == .journal {
                    row("DOI") { TextField("10.1234/…", text: $source.doi) }
                    row("Volume") {
                        HStack {
                            TextField("Volume", text: $source.volume).frame(width: 70)
                            Text("Issue").foregroundStyle(theme.inkTertiary(scheme))
                            TextField("Issue", text: $source.issue).frame(width: 60)
                            Text("Pages").foregroundStyle(theme.inkTertiary(scheme))
                            TextField("45–67", text: $source.pages).frame(width: 80)
                        }
                    }
                }
                row("Cited as") {
                    HStack(spacing: 6) {
                        TextField("key", text: $source.key)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 150)
                        Text("Documents find this source by its key.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12.5))

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: research.style.title)
                Text(SourceEditor.styled(Citations.reference(edited, style: research.style)))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("In the text: " + Citations.unescape(Citations.inText([edited], style: research.style, numbers: [1], letters: [:])).replacingOccurrences(of: "*", with: ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let result = edited
                    if research.library.contains(where: { $0.id == result.id }) {
                        research.update(result)
                    } else {
                        research.addSource(result)
                    }
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(source.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
                .gridColumnAlignment(.trailing)
            content()
        }
    }

    static func styled(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }
}

/// The browser button (a bookmarklet for Safari, Chrome or Firefox) and the Services menu, explained.
struct BrowserButtonSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var link: URL? {
        ClipLink.bookmarklet.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AgentLogo(code: "jm", size: 24)
                Text("Clip and look up from anywhere")
                    .font(theme.display(20))
                    .foregroundStyle(theme.ink(scheme))
            }
            step(1, "The browser button", "Drag this to the bookmarks bar in Safari, Chrome or Firefox. On any page, click it: James reads the page and keeps it in Notes › Clippings, with whatever you'd selected on top.") {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                        Text("Clip to 11am")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.ink(scheme)))
                    .foregroundStyle(theme.paper(scheme))
                    .onDrag {
                        if let link { return NSItemProvider(object: link as NSURL) }
                        return NSItemProvider(object: ClipLink.bookmarklet as NSString)
                    }
                    .help("Drag to your bookmarks bar")
                    Button(copied ? "Copied" : "Copy the button") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ClipLink.bookmarklet, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.vellumSecondary)
                }
            }
            step(2, "The Services menu", "In any app, select words and choose the app's menu › Services › Look Up with James. He searches, reads the top pages, and answers in the agent pane with each claim sourced. Clip to 11am Notes keeps the selection (or a link) instead.") {
                Text("Give them shortcuts in System Settings › Keyboard › Keyboard Shortcuts › Services.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            step(3, "Here in Research", "Clip keeps the page you're on; Add to sources keeps it for citing. Your sources are cited in Write with Cite, and in Decks from the Sources menu.") {
                EmptyView()
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func step<Extra: View>(_ number: Int, _ title: String, _ text: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(theme.well(scheme)))
                .foregroundStyle(theme.ink(scheme))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }
}

/// "Look this up", in the agent pane: the answer with each claim's source, and what James couldn't source.
struct LookUpCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var lookup: LookUp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                AgentLogo(code: "jm", size: 18, color: theme.inkSecondary(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look up")
                        .font(.system(size: 10.5, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(theme.inkTertiary(scheme))
                    Text(lookup.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { withAnimation(theme.spring) { research.lookup = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
                .help("Close")
            }

            switch lookup.stage {
            case .searching, .reading, .answering:
                if let run = lookup.run, !run.text.isEmpty {
                    AnswerText(run: run)
                } else {
                    ThinkingLine(text: lookup.status)
                }
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            case .done:
                if let run = lookup.run { AnswerText(run: run) }
            }

            if let review = lookup.review, !review.unsourced.isEmpty || !review.unknown.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if !review.unsourced.isEmpty {
                        Label(review.unsourced.count == 1 ? "One sentence has no source. Treat it with care." : "\(review.unsourced.count) sentences have no source. Treat them with care.",
                              systemImage: "exclamationmark.triangle")
                            .help(review.unsourced.joined(separator: "\n"))
                    }
                    if !review.unknown.isEmpty {
                        Label("Cites \(review.unknown.map { "[\($0)]" }.joined(separator: ", ")), which isn't a page he read.", systemImage: "questionmark.circle")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.inkSecondary(scheme))
            }

            if !lookup.sources.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lookup.sources.enumerated()), id: \.element.id) { index, source in
                        Button {
                            research.open(source.url)
                            model.go(to: .research)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill(theme.well(scheme)))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(source.title)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                    Text(source.host)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                            }
                            .foregroundStyle(theme.ink(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(source.url)
                    }
                }
            }

            if lookup.stage == .done {
                HStack(spacing: 6) {
                    Button(lookup.kept ? "Kept" : "Keep sources") { research.keepLookUpSources() }
                        .disabled(lookup.kept)
                    Button("To Write") { research.sendLookUpToWrite() }
                    Button("Clip") { research.clipLookUp() }
                }
                .buttonStyle(.vellumSecondary)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.well(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
    }
}

private struct AnswerText: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        Text(run.text)
            .font(.system(size: 12.5))
            .lineSpacing(2.5)
            .foregroundStyle(theme.ink(scheme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
