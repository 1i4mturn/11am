import SwiftUI

// MARK: - Sidebar

/// Favourites and the page tree, in the Notes sidebar. Drag a note onto a page to put it inside.
struct PagesSidebarSection: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let favourites = notes.favourites
        let rows = notes.pageRows
        if !favourites.isEmpty {
            SectionLabel(text: "Favourites")
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 3)
            ForEach(favourites) { note in
                pageRow(note.id, depth: 0, hasChildren: false, showsDisclosure: false)
            }
        }
        if !rows.isEmpty {
            SectionLabel(text: "Pages")
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 3)
            ForEach(rows, id: \.id) { row in
                pageRow(row.id, depth: row.depth, hasChildren: row.hasChildren, showsDisclosure: true)
            }
        }
    }

    private func pageRow(_ id: UUID, depth: Int, hasChildren: Bool, showsDisclosure: Bool) -> some View {
        let title = notes.notes.first { $0.id == id }?.title ?? "Page"
        let selected = notes.selectedID == id
        return HStack(spacing: 3) {
            if showsDisclosure {
                Button {
                    withAnimation(theme.spring) { notes.toggleExpanded(id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(notes.expanded.contains(id) ? 90 : 0))
                        .frame(width: 12, height: 14)
                        .contentShape(Rectangle())
                        .opacity(hasChildren ? 1 : 0)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)
                .foregroundStyle(theme.inkTertiary(scheme))
            }
            Button {
                withAnimation(theme.spring) { notes.selectedID = id }
            } label: {
                HStack(spacing: 6) {
                    PageIcon(id: id, size: 11.5)
                    Text(title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(theme.ink(scheme))
        .padding(.leading, 4 + CGFloat(depth) * 11)
        .padding(.trailing, 8)
        .padding(.vertical, 4.5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear))
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first.flatMap(UUID.init(uuidString:)), dropped != id else { return false }
            return withAnimation(theme.spring) { notes.setParent(dropped, to: id) }
        }
        .contextMenu {
            Button("Add a sub-page") { _ = notes.newSubpage(of: id) }
            Button(notes.pages[id]?.favourite == true ? "Remove from favourites" : "Add to favourites") { notes.toggleFavourite(id) }
            if notes.pages[id]?.parent != nil {
                Button("Move to the top") { _ = notes.setParent(id, to: nil) }
            }
        }
    }
}

/// A page's emoji, or the plain page symbol.
struct PageIcon: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var id: UUID
    var size: CGFloat

    var body: some View {
        if let icon = notes.icon(of: id) {
            Text(icon).font(.system(size: size))
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: size - 1))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
    }
}

// MARK: - Header

/// Above a page: where it sits, its icon, and what you can do with it as a page.
struct PageHeaderBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var note: Note
    @State private var showsHistory = false

    private static let icons = ["📄", "📘", "🗂️", "🌐", "🚀", "🧭", "💡", "📈", "🧾", "🏠", "✈️", "🎯", "🛠️", "📣", "🧪", "🤝", "📅", "❤️"]

    var body: some View {
        let path = notes.breadcrumbs(for: note.id)
        let favourite = notes.pages[note.id]?.favourite == true
        let open = PageCheckboxes.open(in: note.text).count
        let commentCount = (notes.comments[note.id] ?? []).filter { !$0.resolved }.count
        HStack(spacing: 6) {
            Menu {
                ForEach(Self.icons, id: \.self) { icon in
                    Button(icon) { notes.setIcon(icon, for: note.id) }
                }
                Divider()
                Button("No icon") { notes.setIcon(nil, for: note.id) }
            } label: {
                PageIcon(id: note.id, size: 13)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose an icon")
            // The whole path when it fits, then just the page above, then just this page.
            ViewThatFits(in: .horizontal) {
                crumbs(path, current: note)
                crumbs(Array(path.suffix(1)), current: note, elided: path.count > 1)
                crumbs([], current: note)
                Color.clear.frame(width: 1, height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ToolButton(symbol: favourite ? "star.fill" : "star", help: favourite ? "Remove from favourites" : "Add to favourites", on: favourite) {
                notes.toggleFavourite(note.id)
            }
            ToolButton(symbol: "plus.square.on.square", help: "Add a sub-page inside this one") {
                withAnimation(theme.spring) { _ = notes.newSubpage(of: note.id) }
            }
            ToolButton(symbol: "checklist", help: open == 0 ? "Checkboxes on this page go to Tasks" : "Send \(open) open checkbox\(open == 1 ? "" : "es") to Tasks") {
                _ = notes.sendCheckboxesToTasks(note.id)
            }
            ToolButton(symbol: "clock.arrow.circlepath", help: "Earlier versions of this page") {
                showsHistory = true
            }
            ToolButton(symbol: commentCount > 0 ? "text.bubble.fill" : "text.bubble", help: "Comments, and ask an @agent", on: notes.showsComments) {
                withAnimation(theme.spring) { notes.showsComments.toggle() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .sheet(isPresented: $showsHistory) {
            PageHistorySheet(note: note)
                .environmentObject(notes)
                .environmentObject(theme)
        }
    }
}

extension PageHeaderBar {
    fileprivate func crumbs(_ pages: [Note], current: Note, elided: Bool = false) -> some View {
        HStack(spacing: 6) {
            if elided {
                Text("…").foregroundStyle(theme.inkTertiary(scheme))
                chevron
            }
            ForEach(pages) { page in
                Button(page.title) { withAnimation(theme.spring) { notes.selectedID = page.id } }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize()
                chevron
            }
            Text(current.title)
                .fontWeight(.semibold)
                .foregroundStyle(theme.ink(scheme))
                .fixedSize()
        }
        .font(.system(size: 12))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(theme.inkTertiary(scheme))
    }
}

/// The pages inside this one.
struct SubpagesRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var note: Note

    var body: some View {
        let children = notes.subpages(of: note.id)
        if !children.isEmpty {
            HStack(spacing: 8) {
                Text("Inside")
                    .foregroundStyle(theme.inkTertiary(scheme))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(children) { child in
                            Button {
                                withAnimation(theme.spring) { notes.selectedID = child.id }
                            } label: {
                                HStack(spacing: 4) {
                                    PageIcon(id: child.id, size: 11)
                                    Text(child.title).lineLimit(1)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(theme.well(scheme)))
                                .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.ink(scheme))
                        }
                    }
                }
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Live blocks

/// Lines like {{tasks: Website relaunch}} show their live content under the page, in the order they appear.
struct PageBlocksStrip: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var note: Note
    @State private var collapsed = false

    var body: some View {
        let blocks = PageBlocks.find(in: note.text)
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(theme.spring) { collapsed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 10))
                        SectionLabel(text: "Live in this page · \(blocks.count)")
                        Spacer()
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up").font(.system(size: 9, weight: .bold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
                if !collapsed {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, item in
                                card(item.block)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func card(_ block: PageBlock) -> some View {
        switch block {
        case .tasks(let scope): TasksBlock(scope: scope)
        case .sheet(let reference): SheetBlock(reference: reference)
        case .page(let title): EmbeddedPageBlock(title: title, host: note.id)
        case .events(let range): EventsBlock(range: range)
        }
    }
}

/// The frame every live block sits in.
private struct BlockFrame<Content: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var symbol: String
    var action: (String, () -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                if let action {
                    Button(action.0, action: action.1)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .foregroundStyle(theme.ink(scheme))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
    }
}

private struct TasksBlock: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var scope: String

    private var list: TaskListID? {
        switch scope.lowercased() {
        case "today": return .today
        case "upcoming": return .upcoming
        case "inbox": return .inbox
        case "someday": return .someday
        default:
            if scope.hasPrefix("#") { return .tag(String(scope.dropFirst())) }
            return tasks.matchProject(scope).map { .project($0.id) }
        }
    }

    var body: some View {
        let list = self.list
        let items = list.map { tasks.tasks(in: $0) } ?? []
        BlockFrame(title: "Tasks · " + (list.map { tasks.title(of: $0) } ?? scope), symbol: "checklist", action: ("Open in Tasks", {
            if let list { tasks.list = list }
            model.go(to: .tasks)
        })) {
            if list == nil {
                Text("No project called \(scope) in Tasks yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            } else if items.isEmpty {
                Text("Nothing open.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            ForEach(items.prefix(8)) { task in
                HStack(spacing: 8) {
                    TaskCheck(task: task, size: 14) {
                        withAnimation(theme.spring) { tasks.toggle(task.id) }
                    }
                    Text(task.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let due = tasks.dueText(task) {
                        Text(due)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .lineLimit(1)
                    }
                }
            }
            if items.count > 8 {
                Text("and \(items.count - 8) more")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }
}

private struct SheetBlock: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var sheets: SheetsModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var reference: String

    var body: some View {
        let preview = sheets.preview(reference)
        BlockFrame(title: preview.map { "\($0.workbook) · \($0.sheet)" } ?? reference, symbol: "tablecells", action: preview.map { found in
            ("Open in Sheets", {
                sheets.open(named: found.workbook)
                model.go(to: .sheets)
            })
        }) {
            if let preview {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                        ForEach(Array(preview.rows.enumerated()), id: \.offset) { index, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                    Text(cell)
                                        .font(.system(size: 11.5, weight: index == 0 ? .semibold : .regular).monospacedDigit())
                                        .foregroundStyle(theme.ink(scheme))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                if preview.more {
                    Text("The first rows and columns. The rest is in Sheets.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            } else {
                Text("No workbook called \(reference) in Sheets.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }
}

/// Another page, shown here and always up to date. Edit it on its own page.
private struct EmbeddedPageBlock: View {
    @EnvironmentObject private var notes: NotesModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var title: String
    var host: UUID

    var body: some View {
        let other = notes.note(titled: title)
        BlockFrame(title: other?.title ?? title, symbol: "rectangle.on.rectangle", action: other.map { found in
            ("Open", { withAnimation(theme.spring) { notes.selectedID = found.id } })
        }) {
            if let other, other.id == host {
                Text("A page can't show itself.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            } else if let other {
                let excerpt = MarkdownPlain.text(other.text).split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: "\n")
                Text(String(excerpt.prefix(700)))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No page called \(title) yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }
}

private struct EventsBlock: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var range: String

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = range.lowercased().hasPrefix("week") ? 7 : 1
        let events = (0..<days).flatMap { offset -> [CalEvent] in
            let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.events(on: day)
        }
        BlockFrame(title: days == 1 ? "Calendar · today" : "Calendar · the next 7 days", symbol: "calendar", action: ("Open Calendar", { model.go(to: .calendar) })) {
            if events.isEmpty {
                Text("Nothing on the calendar.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            ForEach(events.prefix(10), id: \.id) { event in
                HStack(spacing: 8) {
                    Text(event.isAllDay ? "All day" : (days == 1 ? "" : event.start.formatted(.dateTime.weekday(.abbreviated)) + " ") + TaskDates.time(event.start, calendar: cal))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(width: days == 1 ? 60 : 90, alignment: .leading)
                    Text(event.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Comments

/// Comments on a page. Mention an agent and they answer from the page.
struct PageCommentsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var note: Note
    @State private var draft = ""

    var body: some View {
        let thread = notes.comments[note.id] ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Comments")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(theme.spring) { notes.showsComments = false }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if thread.isEmpty {
                        Text("No comments yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    ForEach(thread) { comment in
                        CommentRow(comment: comment, page: note.id)
                    }
                    if notes.answering.contains(note.id) {
                        ThinkingLine(text: "Writing a reply…")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Mention @Leo, @Bolton or any agent and they answer from this page. \u{201C}@Leo turn these into tasks\u{201D} sends the checkboxes to Tasks.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 6) {
                TextField("Comment, or ask an @agent", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .lineLimit(1...4)
                    .onSubmit(send)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink(scheme))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func send() {
        notes.addComment(draft, to: note.id)
        draft = ""
    }
}

private struct CommentRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    var comment: PageComment
    var page: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if comment.author == "you" {
                    Image(systemName: "person.crop.circle").font(.system(size: 14))
                    Text("You").font(.system(size: 12, weight: .semibold))
                } else {
                    Monogram(text: comment.author, size: 18)
                    Text(AgentNames.name(comment.author)).font(.system(size: 12, weight: .semibold))
                }
                Text(comment.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.ink(scheme))
            Text(comment.text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .opacity(comment.resolved ? 0.45 : 1)
        .contextMenu {
            Button(comment.resolved ? "Reopen" : "Resolve") { notes.resolveComment(comment.id, on: page) }
            Button("Delete", role: .destructive) { notes.deleteComment(comment.id, on: page) }
        }
    }
}

// MARK: - History

/// Earlier versions of a page, kept every ten minutes or so while you write. Put one back and what's there now is kept too.
struct PageHistorySheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var notes: NotesModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var note: Note
    @State private var selected: PageVersion?

    var body: some View {
        let versions = notes.versions(of: note.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Versions of \u{201C}\(note.title)\u{201D}")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumSecondary)
            }
            .foregroundStyle(theme.ink(scheme))
            if versions.isEmpty {
                Text("No earlier versions yet. One is kept every ten minutes or so while you write, for the last two months.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSecondary(scheme))
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(versions) { version in
                                Button {
                                    selected = version
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(version.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12.5, weight: selected == version ? .semibold : .regular))
                                        Text(PageHistory.change(from: notes.text(of: version), to: note.text) + " since")
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.inkTertiary(scheme))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected == version ? theme.raised(scheme) : Color.clear))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.ink(scheme))
                            }
                        }
                    }
                    .frame(width: 200)
                    ScrollView {
                        Text(selected.map { notes.text(of: $0) } ?? "Choose a version to see it.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)))
                }
                HStack {
                    Spacer()
                    Button("Put this version back") {
                        if let selected { notes.restore(selected, to: note.id) }
                        dismiss()
                    }
                    .buttonStyle(.vellumPrimary)
                    .disabled(selected == nil)
                }
            }
        }
        .padding(18)
        .frame(width: 640, height: 460)
    }
}
