import SwiftUI
import WebKit

/// James's app: browse normally with a sharp assistant beside you, then get a sourced answer.
struct ResearchView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                DisplayTitle(text: "research", size: 30)
                Text("James · browse, ask, and get a sourced answer")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
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
                    .frame(width: 270)
            }
        }
        .padding(20)
    }
}

/// Back, forward, reload, the address, and "add to sources".
private struct BrowserBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
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
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""
    @State private var reportQuestion = ""

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
                if let notice = research.notice {
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }

                Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)

                HStack {
                    SectionLabel(text: "Sources · \(research.sources.count)")
                    Spacer()
                    if !research.sources.isEmpty {
                        Button("Clear") { withAnimation(theme.spring) { research.clearSources() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                if research.sources.isEmpty {
                    Text("Add pages you trust. James writes only from these, and cites each one.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(research.sources.enumerated()), id: \.element.id) { index, source in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(width: 14, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Button(source.title) { research.open(source.url) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(2)
                            Text(URL(string: source.url)?.host() ?? source.url)
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button { withAnimation(theme.spring) { research.remove(source) } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .help("Remove source")
                    }
                    .entrance(index)
                }

                Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)

                SectionLabel(text: "Report")
                AskField(placeholder: "What do you want to know?", text: $reportQuestion) {
                    research.writeReport(reportQuestion)
                }
                if let run = research.reportRun {
                    ReportView(run: run)
                        .transition(.rise(theme.rise))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(theme.spring, value: research.sources.count)
            .animation(theme.spring, value: research.pageRun?.id)
            .animation(theme.spring, value: research.reportRun?.id)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ReportView: View {
    @EnvironmentObject private var theme: Theme
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
