import SwiftUI
import WebKit

/// James's app: browse normally with a sharp assistant beside you, clip what's worth keeping, cite what you use.
struct ResearchView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                DisplayTitle(text: "research", size: 30)
                Text("James · browse, clip, cite, and get a sourced answer")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                Spacer()
                Button {
                    research.showsBrowserButton = true
                } label: {
                    Label("Clip from anywhere", systemImage: "bookmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.inkSecondary(scheme))
                .help("The browser button and the Services menu: clip and look things up from any app")
            }
            BrowserBar()
            HStack(alignment: .top, spacing: 12) {
                WebContainer(webView: research.webView)
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                            .strokeBorder(theme.edge(scheme), lineWidth: 0.75)
                    }
                    .overlay(alignment: .top) {
                        if research.isLoading {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .controlSize(.small)
                                .tint(theme.ink(scheme))
                                .padding(.horizontal, 2)
                        }
                    }
                JamesPanel()
                    .frame(width: 300)
            }
        }
        .padding(20)
        .sheet(item: $research.editing) { source in
            SourceEditor(source: source)
                .environmentObject(research)
                .environmentObject(theme)
        }
        .sheet(isPresented: $research.showsBrowserButton) {
            BrowserButtonSheet()
                .environmentObject(research)
                .environmentObject(theme)
        }
    }
}

/// Back, forward, reload, the address, Clip and Add to sources.
private struct BrowserBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Group {
                Button { research.back() } label: { Image(systemName: "chevron.left") }
                    .disabled(!research.canGoBack)
                    .help("Back")
                Button { research.forward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!research.canGoForward)
                    .help("Forward")
                Button { research.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
                Button { research.showStartPage() } label: { Image(systemName: "house") }
                    .help("Start page")
            }
            .buttonStyle(.vellumSecondary)

            HStack(spacing: 8) {
                Image(systemName: research.isOnWebPage ? "lock" : "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                TextField("Search or enter an address", text: $research.address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { research.go() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(theme.well(scheme)))
            .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))

            Menu {
                Button("Clip to Notes › \(ResearchModel.clippingsFolder)") { research.clipCurrentPage() }
                if !notes.favourites.isEmpty {
                    Divider()
                    Section("Inside a page") {
                        ForEach(notes.favourites) { page in
                            Button(page.title) { research.clipCurrentPage(to: .page(page.id)) }
                        }
                    }
                }
            } label: {
                Label("Clip", systemImage: "scissors")
            } primaryAction: {
                research.clipCurrentPage()
            }
            .menuStyle(.button)
            .buttonStyle(.vellumSecondary)
            .fixedSize()
            .disabled(!research.isOnWebPage)
            .help("Keep the article in Notes, read like reader mode, with what you've selected on top")

            Button {
                research.addCurrentPage()
            } label: {
                Label("Add to sources", systemImage: "plus")
            }
            .buttonStyle(.vellumPrimary)
            .disabled(!research.isOnWebPage)
        }
    }
}

/// The browser itself. One WKWebView lives in the model, so history survives switching apps.
private struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView.removeFromSuperview()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct JamesPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $research.tab) {
                ForEach(JamesTab.allCases) { tab in
                    Text(tab == .sources ? "Sources · \(research.library.count)" : tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let notice = research.notice {
                HStack(alignment: .top, spacing: 8) {
                    AgentLogo(code: "jm", size: 16, color: theme.inkSecondary(scheme))
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { research.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
                .transition(.opacity)
            }

            switch research.tab {
            case .page: PageTab()
            case .sources: SourcesTab()
            case .report: ReportTab()
            }
        }
        .animation(theme.spring, value: research.tab)
        .animation(theme.spring, value: research.notice)
    }
}

private struct PageTab: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    AgentLogo(code: "jm", size: 24)
                    Text(research.title.isEmpty || !research.isOnWebPage ? "This page" : research.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Button("Summarise") { research.summarisePage() }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!research.isOnWebPage || brain.isBusy)
                    Button("Clip") { research.clipCurrentPage() }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!research.isOnWebPage)
                    Spacer()
                }
                AskField(placeholder: "Ask about this page…", text: $question) {
                    research.ask(question)
                }
                .disabled(!research.isOnWebPage)
                if let run = research.pageRun {
                    RunView(run: run)
                        .transition(.rise(theme.rise))
                }
                Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Look this up")
                    Text("Ask anything and James searches the web, reads the top pages and answers citing them. From any other app, select words and choose Services › Look Up with James.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    LookUpField()
                    if let lookup = research.lookup {
                        LookUpCard(lookup: lookup)
                            .transition(.rise(theme.rise))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(theme.spring, value: research.pageRun?.id)
            .animation(theme.spring, value: research.lookup?.id)
        }
        .scrollContentBackground(.hidden)
    }
}

struct LookUpField: View {
    @EnvironmentObject private var research: ResearchModel
    @State private var text = ""

    var body: some View {
        AskField(placeholder: "Look this up on the web…", text: $text) {
            research.lookUp(text)
            text = ""
        }
    }
}

private struct SourcesTab: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(CitationStyle.allCases) { style in
                        Button {
                            research.style = style
                        } label: {
                            if style == research.style { Label(style.title, systemImage: "checkmark") } else { Text(style.title) }
                        }
                    }
                } label: {
                    Label(research.style.title, systemImage: "text.quote")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(theme.ink(scheme))
                .help("The citation style for your references, documents and decks")
                Spacer()
                Menu {
                    Button("Copy all as a reference list") { research.copyBibliography() }
                        .disabled(research.library.isEmpty)
                    Button("Add a source by hand…") {
                        research.editing = CitationSource(title: "", kind: .book)
                    }
                    Divider()
                    Button("Remove all sources", role: .destructive) { withAnimation(theme.spring) { research.clearSources() } }
                        .disabled(research.library.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(theme.inkSecondary(scheme))
            }
            if research.library.isEmpty {
                Text("Add pages you trust. James cites them in your style, in Write and in Decks, and writes reports only from them.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(research.library.enumerated()), id: \.element.id) { index, source in
                        SourceRow(source: source)
                            .entrance(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(theme.spring, value: research.library.count)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct SourceRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme
    var source: CitationSource

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: source.kind.symbol)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 14)
                Text(research.citeText(source))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if source.authors.isEmpty || source.published == nil {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .help(source.authors.isEmpty ? "No author: add one if the page names one" : "No date: add one if you know it")
                }
                Menu {
                    Button("Edit…") { research.editing = source }
                    Button("Copy reference") { research.copyReference(source) }
                    if !source.url.isEmpty {
                        Button("Open") { research.open(source.url) }
                    }
                    Divider()
                    Button("Remove", role: .destructive) { withAnimation(theme.spring) { research.remove(source) } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(theme.inkTertiary(scheme))
            }
            Text(Self.styled(research.reference(source)))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .lineSpacing(1.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { research.editing = source }
    }

    /// The reference's *italics* shown as italics.
    static func styled(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }
}

private struct ReportTab: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var reportQuestion = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("James answers from your \(research.library.count) \(research.library.count == 1 ? "source" : "sources") only, and cites each claim. In Write the citations follow \(research.style.title).")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                AskField(placeholder: "What do you want to know?", text: $reportQuestion) {
                    research.writeReport(reportQuestion)
                }
                if let run = research.reportRun {
                    ReportRunView(run: run)
                        .transition(.rise(theme.rise))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(theme.spring, value: research.reportRun?.id)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ReportRunView: View {
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var model: AppModel
    @ObservedObject var run: BrainRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RunView(run: run)
            if run.status == .done {
                Button("Send to Write") {
                    research.sendReportToWrite()
                    model.go(to: .write)
                }
                .buttonStyle(.vellumPrimary)
            }
        }
    }
}
