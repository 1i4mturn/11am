import SwiftUI

/// Cite in Write: pick a source and James cites it at the cursor in your style; Update brings every citation and
/// the reference list into line.
struct CiteButton: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var model: AppModel
    var document: WriteDocument
    var editor: DocEditorController
    @State private var showing = false

    var body: some View {
        ToolButton(symbol: "quote.bubble", help: "Cite a source · James") { showing = true }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                CitePicker(document: document, done: { showing = false }) { source in
                    editor.insert(research.citation(for: source, in: document.text))
                } update: {
                    research.formatCitations(documentID: document.id)
                } findMore: {
                    model.go(to: .research)
                }
                .environmentObject(research)
                .environmentObject(theme)
            }
    }
}

/// The sources to cite from, searchable, with the style and the reference list's Update.
struct CitePicker: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument?
    var done: () -> Void
    var cite: (CitationSource) -> Void
    var update: (() -> Void)?
    var findMore: () -> Void
    @State private var filter = ""

    private var matches: [CitationSource] {
        let words = filter.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return research.library }
        return research.library.filter { source in
            let text = ([source.title, source.container, source.key] + source.authors.map(\.full)).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private var citedKeys: Set<String> {
        Set(Citations.markers(in: document?.text ?? "").flatMap(\.keys))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AgentLogo(code: "jm", size: 18)
                Text("Cite")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Picker("", selection: $research.style) {
                    ForEach(CitationStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            TextField("Find a source", text: $filter)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            if research.library.isEmpty {
                Text("No sources yet. In Research, open a page and choose Add to sources, or keep the sources from a look-up.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matches) { source in
                        Button {
                            cite(source)
                            done()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: source.kind.symbol)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(source.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(theme.ink(scheme))
                                        .lineLimit(1)
                                    Text(research.citeText(source) + (source.container.isEmpty ? "" : " · \(source.container)"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if citedKeys.contains(source.key.lowercased()) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                        .help("Already cited here")
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
            Divider()
            HStack {
                Button("Find sources in Research") {
                    findMore()
                    done()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
                Spacer()
                if let update {
                    Button("Update citations") {
                        update()
                        done()
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Every citation in \(research.style.title), numbered where it needs to be, and the \(research.style.heading.lowercased()) at the end")
                }
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

/// Sources in Decks: cite one at the foot of this slide, or add a sources slide at the end.
struct DeckSourcesMenu: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            if research.library.isEmpty {
                Button("Find sources in Research…") { model.go(to: .research) }
            } else {
                Menu("Cite on this slide") {
                    ForEach(research.library) { source in
                        Button(research.citeText(source) + " · " + source.title) { research.citeOnSlide(source) }
                    }
                }
                Button("Add a sources slide") { research.addSourcesSlide(research.library) }
                Divider()
                Menu("Style: \(research.style.title)") {
                    ForEach(CitationStyle.allCases) { style in
                        Button(style.title) { research.style = style }
                    }
                }
            }
        } label: {
            Label("Sources", systemImage: "text.quote")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .help("James's sources: cite one on this slide, or list them on a slide at the end")
    }
}
