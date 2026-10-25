import AppKit
import SwiftUI

/// William's app: a quiet page with a margin rule. The writing is the interface.
struct WriteView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @EnvironmentObject private var voice: VoiceProfile
    @Environment(\.colorScheme) private var scheme
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var showsVoice = false

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
                    Button("New") {
                        withAnimation(theme.spring) { write.newDocument() }
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                DocumentList()
                    .frame(width: 160)
                ZStack {
                    if let document = write.selected {
                        Page(document: document, selection: $selection)
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
            }
        }
        .padding(24)
        .animation(theme.spring, value: write.selectedID)
        .onChange(of: write.selectedID) { _, _ in selection = NSRange(location: 0, length: 0) }
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
                Text("\(document.modified.formatted(.relative(presentation: .named))) · \(document.wordCount) words")
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

/// The sheet you write on: a margin rule, the text, and William's tools along the bottom.
private struct Page: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    @Binding var selection: NSRange

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(theme.ink(scheme).opacity(0.14))
                    .frame(width: 1)
                    .padding(.trailing, 20)
                ProseEditor(
                    text: Binding(
                        get: { write.selected?.text ?? "" },
                        set: { write.update(document.id, text: $0) }
                    ),
                    selection: $selection,
                    font: Page.writingFont,
                    textColor: NSColor(theme.ink(scheme))
                )
            }
            .padding(.leading, 30)
            .padding(.trailing, 24)
            .frame(maxWidth: 720, maxHeight: .infinity)
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
        HStack(spacing: 6) {
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
            Text("\(document.wordCount) words")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .contentTransition(.numericText())
                .fixedSize()
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
    static let writingFont: NSFont = {
        let size: CGFloat = 15.5
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif), let serif = NSFont(descriptor: descriptor, size: size) else { return base }
        return serif
    }()
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
