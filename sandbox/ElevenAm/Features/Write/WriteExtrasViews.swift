import AppKit
import SwiftUI

/// Comment on the words you've selected; "@William" in a comment gets an answer from the document.
struct CommentButton: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    var selection: NSRange
    @State private var writing = false
    @State private var text = ""

    var body: some View {
        HStack(spacing: 0) {
            ToolButton(symbol: "text.bubble", help: selection.length > 0 ? "Comment on the selection" : "Select words to comment on them") {
                if selection.length > 0 { writing = true } else { write.showsComments.toggle() }
            }
            .popover(isPresented: $writing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\u{201C}\(String((document.text as NSString).substring(with: safe(selection)).prefix(80)))\u{201D}")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(2)
                    TextField("Comment, or ask @William", text: $text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                        .onSubmit(add)
                    HStack {
                        Spacer()
                        Button("Cancel") { writing = false }
                            .buttonStyle(.vellumSecondary)
                        Button("Comment", action: add)
                            .buttonStyle(.vellumPrimary)
                            .keyboardShortcut(.defaultAction)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
                .frame(width: 320)
                .environmentObject(theme)
            }
            let count = (write.comments[document.id] ?? []).filter { !$0.resolved }.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .offset(x: -4, y: -6)
            }
        }
    }

    private func safe(_ range: NSRange) -> NSRange {
        let length = (document.text as NSString).length
        guard range.location != NSNotFound, range.location <= length else { return NSRange(location: 0, length: 0) }
        return NSRange(location: range.location, length: min(range.length, length - range.location))
    }

    private func add() {
        write.addComment(text, on: selection, in: document.id)
        text = ""
        writing = false
    }
}

/// William's tools for the whole document.
struct WilliamMenu: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            Button("Summarise it") { write.summarise() }
            Menu("Translate it into") {
                ForEach(DocShape.languages, id: \.self) { language in
                    Button(language) { write.translate(to: language) }
                }
            }
            Divider()
            Button("Draft from my notes and files…") { write.showsDraft = true }
            Button("Make flashcards with Harris") { write.makeFlashcards() }
            Divider()
            Button(write.showsComments ? "Hide comments" : "Show comments") { write.showsComments.toggle() }
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 26, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("William: summarise, translate, draft from your notes, flashcards")
    }
}

/// The document's comments: open ones in the order they appear, then any whose words are gone, then resolved.
struct DocCommentsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    var editor: DocEditorController
    @State private var showsResolved = false

    var body: some View {
        let all = write.comments(for: document.id)
        let shown = all.filter { showsResolved || !$0.resolved }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Comments · \(all.filter { !$0.resolved }.count)")
                Spacer()
                Button { write.showsComments = false } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            if all.contains(where: \.resolved) {
                Toggle("Show resolved", isOn: $showsResolved)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            if shown.isEmpty {
                Text("Select some words and press the speech bubble to comment. Write @William to ask him about it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(shown) { comment in
                        DocCommentThread(document: document, comment: comment, editor: editor)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 4)
    }
}

private struct DocCommentThread: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    var document: WriteDocument
    var comment: DocComment
    var editor: DocEditorController
    @State private var reply = ""

    var body: some View {
        let range = DocAnchors.locate(comment, in: document.text)
        VStack(alignment: .leading, spacing: 7) {
            Button {
                if let range { editor.select(range) }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Rectangle().fill(range == nil ? theme.inkTertiary(scheme) : Color.yellow.opacity(0.7)).frame(width: 3)
                    Text(range == nil ? "The words this was on have changed: \u{201C}\(DocAnchors.excerpt(comment, length: 40))\u{201D}" : DocAnchors.excerpt(comment))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(range == nil ? "" : "Show it in the document")
            message(comment.author, comment.body)
            ForEach(comment.replies) { item in message(item.author, item.body) }
            if write.answering.contains(comment.id) {
                ThinkingLine(text: "William is reading the document…")
            }
            if !comment.resolved {
                TextField("Reply", text: $reply)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .onSubmit {
                        write.reply(reply, to: comment.id, in: document.id)
                        reply = ""
                    }
            }
            HStack(spacing: 10) {
                Button(comment.resolved ? "Reopen" : "Resolve") { withAnimation(theme.spring) { write.resolve(comment.id, in: document.id) } }
                if !comment.asksWilliam && !comment.resolved {
                    Button("Ask William") { write.reply("@William what do you think?", to: comment.id, in: document.id) }
                }
                Spacer()
                Button { withAnimation(theme.spring) { write.deleteComment(comment.id, in: document.id) } } label: { Image(systemName: "trash") }
                    .help("Delete the comment")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
        .opacity(comment.resolved ? 0.6 : 1)
    }

    private func message(_ author: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if author == "William" { AgentLogo(code: "wm", size: 13) }
                Text(author).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.inkTertiary(scheme))
            }
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// William's summary, translation or draft, at the foot of the page.
struct WilliamJobCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var job: WilliamJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "wm", size: 18)
                Text(job.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                if !job.progress.isEmpty {
                    Text(job.progress)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                Spacer()
                Button { write.william = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            if job.kind == .summary, let run = job.run {
                ScrollView { RunView(run: run).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
                SummaryActions(job: job, run: run)
            } else if let run = job.run, !job.finished {
                ScrollView { RunView(run: run).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 160)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(RoundedRectangle(cornerRadius: max(theme.radius - 2, 10), style: .continuous).fill(theme.paper(scheme)))
        .overlay(RoundedRectangle(cornerRadius: max(theme.radius - 2, 10), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
    }
}

private struct SummaryActions: View {
    @EnvironmentObject private var write: WriteModel
    @ObservedObject var job: WilliamJob
    @ObservedObject var run: BrainRun

    var body: some View {
        if run.status == .done {
            HStack {
                Button("Put it under the title") { write.insertSummary(job) }
                    .buttonStyle(.vellumPrimary)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                }
                .buttonStyle(.vellumSecondary)
            }
        }
    }
}

/// "A proposal for Acme from last week's call notes and our pricing": Bolton finds the material, you keep what's
/// right, William writes from only that, in the shape of another document if you like.
struct DraftSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var write: WriteModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var found: [DraftMaterial] = []
    @State private var kept: Set<String> = []
    @State private var shape: UUID?
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AgentLogo(code: "wm", size: 24)
                Text("Draft from my notes and files")
                    .font(theme.display(20))
                    .foregroundStyle(theme.ink(scheme))
            }
            AskField(placeholder: "e.g. a proposal for Acme from last week's call notes and our pricing", text: $request) { find() }
            if searched {
                SectionLabel(text: found.isEmpty ? "Nothing matched" : "Bolton found")
                if found.isEmpty {
                    Text("Try the names of people, clients or projects that are in your notes.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                ForEach(found) { item in
                    Toggle(isOn: Binding(get: { kept.contains(item.id) }, set: { on in if on { kept.insert(item.id) } else { kept.remove(item.id) } })) {
                        HStack(spacing: 6) {
                            Text(item.kind)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .frame(width: 62, alignment: .leading)
                            Text(item.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                            Spacer()
                            Text(item.date.formatted(.relative(presentation: .named)))
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            HStack {
                Text("In the shape of")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                Picker("", selection: $shape) {
                    Text("Its own shape").tag(UUID?.none)
                    ForEach(write.documents) { document in
                        Text(document.title).tag(UUID?.some(document.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Text("William writes only from what's ticked, and leaves [gaps] for anything it doesn't say.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Write it") {
                    let material = found.filter { kept.contains($0.id) }
                    write.draft(request, from: material, shapedLike: write.documents.first { $0.id == shape })
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || kept.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 580)
    }

    private func find() {
        found = write.findMaterial(request)
        kept = Set(found.prefix(4).map(\.id))
        searched = true
    }
}
