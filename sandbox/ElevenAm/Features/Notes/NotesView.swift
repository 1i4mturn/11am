import AppKit
import SwiftUI

/// Bolton's notes: folders and tags down the side, the notes, and the note itself with what links to it.
struct NotesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @StateObject private var editor = DocEditorController()
    @State private var asking = false
    @State private var deleting: Note?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "notes", subtitle: subtitle) {
                HStack(spacing: 8) {
                    if notes.isImporting { ProgressView().controlSize(.small) }
                    NotesSearchField(text: $notes.search)
                        .frame(width: 170)
                    Button {
                        asking = true
                    } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Ask Bolton about your notes")
                    .popover(isPresented: $asking, arrowEdge: .bottom) {
                        AskNotesView()
                            .environmentObject(notes)
                            .environmentObject(theme)
                    }
                    Button {
                        withAnimation(theme.spring) { notes.openToday() }
                    } label: {
                        Label("Today", systemImage: "calendar.day.timeline.left")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Today's note, with today's calendar from Leo")
                    moreMenu
                    Button {
                        withAnimation(theme.spring) { notes.newNote() }
                        editor.focus()
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }

            if let notice = notes.notice {
                NotesBanner(text: notice) { notes.notice = nil }
                    .transition(.rise(theme.rise))
            }

            HStack(alignment: .top, spacing: 14) {
                NotesSidebar()
                    .frame(width: 176)
                NoteList(deleting: $deleting)
                    .frame(width: 230)
                ZStack {
                    if let note = notes.selected {
                        NoteDetail(note: note, editor: editor)
                            .id(note.id)
                            .transition(.rise(theme.rise))
                    } else {
                        VStack(spacing: 10) {
                            AgentLogo(code: "bn", size: 44, color: theme.inkTertiary(scheme))
                            Text(notes.search.isEmpty ? "No note open. ⇧⌘N starts one." : "Nothing matches that.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .animation(theme.spring, value: notes.selectedID)
        .animation(theme.spring, value: notes.notice)
        .confirmationDialog("Move \u{201C}\(deleting?.title ?? "")\u{201D} to the Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { note in
            Button("Move to Trash", role: .destructive) { withAnimation(theme.spring) { notes.delete(note.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It goes to the Mac's Trash, so you can still put it back.")
        }
        .task(id: notes.notice) {
            guard notes.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            notes.notice = nil
        }
        .onAppear {
            if notes.wantsFocus {
                notes.wantsFocus = false
                DispatchQueue.main.async { editor.focus() }
            }
        }
        .onChange(of: notes.wantsFocus) { _, wants in
            guard wants else { return }
            notes.wantsFocus = false
            DispatchQueue.main.async { editor.focus() }
        }
    }

    private var subtitle: String {
        let count = notes.notes.count
        let folders = notes.folders.count
        return "\(count) \(count == 1 ? "note" : "notes") · \(folders) \(folders == 1 ? "folder" : "folders") · plain Markdown on this Mac"
    }

    private var moreMenu: some View {
        Menu {
            Section("Import") {
                Button("From Apple Notes…") { notes.importAppleNotes() }
                Button("Markdown files or a Notion export…") { notes.importMarkdown() }
            }
            Section("Export") {
                Button("This note as Markdown…") { notes.exportSelected() }
                    .disabled(notes.selected == nil)
                Button("All notes as Markdown…") { notes.exportAll() }
            }
            Divider()
            Button("Show the notes folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([notes.root]) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .help("Import and export")
    }
}

private struct NotesSearchField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField("Search notes", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { Capsule().fill(theme.well(scheme)) }
        .overlay { Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }
}

private struct NotesBanner: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(code: "bn", size: 18, color: theme.inkSecondary(scheme))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

// MARK: Sidebar

private struct NotesSidebar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    @State private var addingFolder = false
    @State private var folderName = ""
    @State private var renaming: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(.all, title: "All notes", symbol: "note.text", count: notes.notes.count)
                row(.pinned, title: "Pinned", symbol: "pin", count: notes.notes.filter(\.pinned).count)
                PagesSidebarSection()

                HStack {
                    SectionLabel(text: "Folders")
                    Spacer()
                    Button {
                        folderName = ""
                        addingFolder = true
                    } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("New folder")
                    .popover(isPresented: $addingFolder, arrowEdge: .trailing) {
                        FolderNameField(title: "New folder", name: $folderName) {
                            notes.newFolder(folderName)
                            addingFolder = false
                        }
                        .environmentObject(theme)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 3)
                ForEach(notes.folders, id: \.self) { folder in
                    row(.folder(folder), title: folder, symbol: folder == NotesModel.dailyFolder ? "calendar" : "folder", count: notes.count(in: folder))
                        .contextMenu {
                            Button("Rename…") { renaming = folder; folderName = folder }
                            Button("Delete folder", role: .destructive) { withAnimation(theme.spring) { notes.deleteFolder(folder) } }
                        }
                        .popover(isPresented: Binding(get: { renaming == folder }, set: { if !$0 { renaming = nil } }), arrowEdge: .trailing) {
                            FolderNameField(title: "Rename folder", name: $folderName) {
                                notes.renameFolder(folder, to: folderName)
                                renaming = nil
                            }
                            .environmentObject(theme)
                        }
                }

                let tags = notes.tags
                if !tags.isEmpty {
                    SectionLabel(text: "Tags")
                        .padding(.horizontal, 8)
                        .padding(.top, 14)
                        .padding(.bottom, 3)
                    ForEach(Array(tags.prefix(16))) { item in
                        row(.tag(item.tag), title: "#" + item.tag, symbol: nil, count: item.count)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ scope: NotesScope, title: String, symbol: String?, count: Int) -> some View {
        let selected = notes.scope == scope && notes.search.isEmpty
        return Button {
            withAnimation(theme.spring) {
                notes.search = ""
                notes.scope = scope
                if let first = notes.visible.first, !notes.visible.contains(where: { $0.id == notes.selectedID }) { notes.selectedID = first.id }
            }
        } label: {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .frame(width: 14)
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            // Drag a note onto a folder to move it there.
            guard case .folder(let folder) = scope, let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            withAnimation(theme.spring) { notes.move(id, to: folder) }
            return true
        }
    }
}

private struct FolderNameField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    @Binding var name: String
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(done)
                .frame(width: 200)
            HStack {
                Spacer()
                Button("Done", action: done)
                    .buttonStyle(.vellumPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }
}

// MARK: List

private struct NoteList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    @Binding var deleting: Note?

    var body: some View {
        let visible = notes.visible
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: notes.search.isEmpty ? notes.scopeTitle : "\(visible.count) found")
                .padding(.horizontal, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, note in
                        NoteRow(note: note, selected: notes.selectedID == note.id, showsFolder: notes.scope == .all || !notes.search.isEmpty)
                            .entrance(index)
                            .draggable(note.id.uuidString)
                            .contextMenu {
                                Button(note.pinned ? "Unpin" : "Pin") { withAnimation(theme.spring) { notes.togglePin(note.id) } }
                                Menu("Move to") {
                                    Button("No folder") { notes.move(note.id, to: "") }
                                    ForEach(notes.folders, id: \.self) { folder in
                                        Button(folder) { withAnimation(theme.spring) { notes.move(note.id, to: folder) } }
                                    }
                                }
                                Divider()
                                Button("Move to Trash…", role: .destructive) { deleting = note }
                            }
                    }
                    if visible.isEmpty {
                        Text(notes.search.isEmpty ? "No notes here yet." : "No notes match that.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .padding(10)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct NoteRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var note: Note
    var selected: Bool
    var showsFolder: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(theme.spring) { notes.selectedID = note.id }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.pinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(theme.inkSecondary(scheme))
                    }
                    Text(note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(Self.date(note.modified))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.inkSecondary(scheme))
                    Text(note.snippet.isEmpty ? "No more text" : note.snippet)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                if showsFolder && !note.folder.isEmpty {
                    Label(note.folder, systemImage: "folder")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .foregroundStyle(theme.ink(scheme))
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
        .onHover { hovering = $0 }
    }

    /// "10:42 am" today, "Tue" this week, "12 Oct" otherwise.
    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: Note

private struct NoteDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @EnvironmentObject private var learn: LearnModel
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var note: Note
    @ObservedObject var editor: DocEditorController
    @State private var selection = NSRange(location: 0, length: 0)

    var body: some View {
        let backlinks = notes.backlinks(to: note)
        HStack(spacing: 0) {
        VStack(spacing: 0) {
            PageHeaderBar(note: note)
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
            HStack(spacing: 4) {
                FormatBar(editor: editor)
                Spacer(minLength: 6)
                ToolButton(symbol: note.pinned ? "pin.fill" : "pin", help: note.pinned ? "Unpin" : "Pin to the top", on: note.pinned) {
                    withAnimation(theme.spring) { notes.togglePin(note.id) }
                }
                ToolButton(symbol: "text.badge.star", help: "Summarise with Bolton") { notes.summarise() }
                ToolButton(symbol: "rectangle.on.rectangle.angled", help: "Make flashcards in Learn") {
                    learn.makeCards(from: note.text)
                    model.go(to: .learn)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)

            DocEditor(
                text: Binding(get: { notes.selected?.text ?? "" }, set: { notes.update(note.id, text: $0) }),
                selection: $selection,
                style: .from(theme, scheme, font: NSFont.systemFont(ofSize: 14)),
                controller: editor,
                placeholder: "Title on the first line, then anything. [[Links]] and #tags work.",
                insets: NSSize(width: 0, height: 16),
                baseURL: notes.root,
                onAttach: { [note] data, name in notes.attach(data, named: name, to: note.id) },
                onWikiLink: { title in withAnimation(theme.spring) { notes.open(link: title) } },
                onTag: { tag in
                    withAnimation(theme.spring) {
                        notes.search = ""
                        notes.scope = .tag(tag)
                    }
                }
            )
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)

            PageBlocksStrip(note: note)

            if let run = notes.noteRun {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        AgentLogo(code: "bn", size: 18)
                        Text("Bolton · Summary").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button { notes.clearNoteRun() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    ScrollView { RunView(run: run).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 150)
                }
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)) }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.rise(theme.rise))
            }

            SubpagesRow(note: note)
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
            HStack(spacing: 8) {
                if backlinks.isEmpty {
                    Text("No notes link here yet. Type [[\(note.title)]] in another note.")
                        .lineLimit(1)
                        .foregroundStyle(theme.inkTertiary(scheme))
                } else {
                    Text("Linked from")
                        .foregroundStyle(theme.inkTertiary(scheme))
                    ForEach(backlinks.prefix(4)) { other in
                        Button(other.title) { withAnimation(theme.spring) { notes.open(link: other.title) } }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.ink(scheme))
                            .underline()
                    }
                }
                Spacer(minLength: 8)
                Text("\(MarkdownInfo.stats(note.text).words) words · edited \(NoteRow.date(note.modified))")
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize()
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
            if notes.showsComments {
                Rectangle().fill(theme.edge(scheme)).frame(width: 0.5)
                PageCommentsPanel(note: note)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .animation(theme.spring, value: notes.noteRun?.id)
        .animation(theme.spring, value: notes.showsComments)
    }
}

/// "What did I note about Acme?" — answered from your notes, with the notes it used.
private struct AskNotesView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "bn", size: 22)
                Text("Ask your notes")
                    .font(theme.display(18))
                    .foregroundStyle(theme.ink(scheme))
            }
            AskField(placeholder: "What did I note about Acme?", text: $question) {
                notes.ask(question)
            }
            if let run = notes.askRun {
                ScrollView {
                    RunView(run: run).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            if !notes.askSources.isEmpty {
                SectionLabel(text: "From")
                FlowLayout(spacing: 6) {
                    ForEach(notes.askSources, id: \.self) { id in
                        if let note = notes.notes.first(where: { $0.id == id }) {
                            Button(note.title) {
                                notes.search = ""
                                notes.scope = .all
                                notes.selectedID = id
                            }
                            .buttonStyle(.vellumSecondary)
                        }
                    }
                }
            }
            Text("Bolton reads only your notes, and answers with the brain you chose in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(16)
        .frame(width: 380)
    }
}
