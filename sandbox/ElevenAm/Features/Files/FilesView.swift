import AppKit
import SwiftUI

struct FilesView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var browser: FileBrowser
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "files", subtitle: subtitle) {
                HStack(spacing: 8) {
                    Picker("", selection: $browser.mode) {
                        ForEach(FilesMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if browser.mode == .search {
                        Button("Add Folder…") { files.chooseFolder() }
                            .buttonStyle(.vellumSecondary)
                        Button(files.isIndexing ? "Indexing…" : "Index Now") {
                            Task { await files.reindex() }
                        }
                        .buttonStyle(.vellumPrimary)
                        .disabled(files.isIndexing || files.folders.isEmpty)
                    }
                }
            }
            if let notice = browser.notice {
                HStack(spacing: 10) {
                    AgentLogo(code: "bn", size: 18, color: theme.inkSecondary(scheme))
                    Text(notice).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme)).lineLimit(2)
                    Spacer()
                    Button {
                        browser.notice = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))
                .transition(.rise(theme.rise))
            }
            if browser.mode == .browse {
                FilesBrowserView()
            } else {
                FilesSearchView()
            }
        }
        .padding(24)
        .animation(theme.spring, value: browser.notice)
        .animation(theme.spring, value: browser.mode)
        .task(id: browser.notice) {
            guard browser.notice != nil, (try? await Task.sleep(for: .seconds(8))) != nil else { return }
            browser.notice = nil
        }
        .overlay {
            if !browser.slideshow.isEmpty {
                SlideshowView()
                    .environmentObject(browser)
                    .transition(.opacity)
            }
        }
    }

    private var subtitle: String {
        if browser.mode == .search { return "Bolton · " + files.status }
        return "Bolton · " + (browser.folder?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "your folders")
    }
}

/// Finding things by what's in them, across the folders 11am indexes.
private struct FilesSearchView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var files: FileIndex
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var answer: BrainRun?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisplayTitle(text: "What are you looking for?", size: 26)

                AskField(placeholder: "contract signed with acme last year", text: $query) {
                    hits = files.search(query)
                }
                .onChange(of: query) { _, _ in
                    hits = files.search(query)
                }

                if !query.isEmpty {
                    HStack(spacing: 8) {
                        Button("Ask Bolton about these results") {
                            answer = brain.run(AskRouter.request(for: "find " + query, files: files))
                        }
                        .buttonStyle(.vellumSecondary)
                        .disabled(hits.isEmpty)
                        Text("\(hits.count) matches · searched on this Mac")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }

                if let answer {
                    Card { RunView(run: answer) }
                }

                if files.folders.isEmpty {
                    Card {
                        Text("Point Bolton at a folder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        Text("Your files stay exactly where they are. 11am keeps a small local index (a few thousand characters per file) and refreshes it overnight. PDFs, Word, RTF, Markdown and text are read.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Folders")
                        ForEach(files.folders, id: \.self) { folder in
                            HStack {
                                Image(systemName: "folder")
                                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 12.5))
                                Spacer()
                                Button("Remove") { files.removeFolder(folder) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            .foregroundStyle(theme.inkSecondary(scheme))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    if !hits.isEmpty {
                        SectionLabel(text: "Results").padding(.bottom, 6)
                        ForEach(hits) { hit in
                            ResultRow(hit: hit)
                        }
                    } else if query.isEmpty, !files.files.isEmpty {
                        SectionLabel(text: "Recently changed").padding(.bottom, 6)
                        ForEach(files.recentlyChanged(within: 24 * 7).prefix(12)) { file in
                            ResultRow(hit: SearchHit(file: file, score: 0, snippet: FileIndex.snippet(in: file.text, terms: []), reason: file.modified.formatted(date: .abbreviated, time: .shortened)))
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ResultRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var app: AppModel
    @Environment(\.colorScheme) private var scheme
    var hit: SearchHit

    var body: some View {
        Button {
            NSWorkspace.shared.open(hit.file.url)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(hit.file.kind.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .frame(width: 38, height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.edge(scheme).opacity(2), lineWidth: 0.75)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.file.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.ink(scheme))
                    Text(hit.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(2)
                    Text(hit.reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([hit.file.url]) }
            Button("Open") { NSWorkspace.shared.open(hit.file.url) }
            Button("Open a terminal here") {
                app.terminal.open(folder: hit.file.url)
                app.build.tab = .terminal
                app.go(to: .build)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
        }
    }
}
