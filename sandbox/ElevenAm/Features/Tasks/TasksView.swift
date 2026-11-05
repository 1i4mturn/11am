import SwiftUI

/// Leo's Tasks: smart lists and projects on the left, the tasks in the middle (as a list, a board or a week),
/// and the task you're looking at on the right.
struct TasksView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var tasks: TasksModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "tasks", subtitle: subtitle) {
                HStack(spacing: 10) {
                    Picker("", selection: $tasks.layout) {
                        ForEach(TaskLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    TasksMenu()
                }
            }
            GeometryReader { geometry in
                // On a narrow window the lists step aside for the week and for the task you're looking at.
                let width = geometry.size.width
                let showsLists = tasks.selected == nil ? (tasks.layout != .week || width > 1_000) : width > 880
                HStack(alignment: .top, spacing: 14) {
                    if showsLists {
                        TaskSidebar()
                            .frame(width: 180)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Group {
                        switch tasks.layout {
                        case .list: TaskListPane()
                        case .board: TaskBoard()
                        case .week: TaskWeek()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if let task = tasks.selected {
                        TaskInspector(task: task)
                            .frame(width: 290)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(width: width, height: geometry.size.height, alignment: .top)
            }
        }
        .padding(24)
        .animation(theme.spring, value: tasks.selectedID)
        .overlay(alignment: .bottom) { TaskNotice() }
    }

    private var subtitle: String {
        let today = tasks.count(.today)
        var parts = ["Leo", today == 0 ? "nothing due today" : "\(today) today"]
        let overdue = tasks.overdueCount
        if overdue > 0 { parts.append("\(overdue) overdue") }
        let inbox = tasks.count(.inbox)
        if inbox > 0 { parts.append("\(inbox) in the Inbox") }
        if tasks.settings.syncReminders { parts.append("in step with Reminders") }
        return parts.joined(separator: " · ")
    }
}

/// The agent behind a monogram, for "Marc made this".
enum AgentNames {
    static func name(_ monogram: String) -> String {
        switch monogram {
        case "le": return "Leo"
        case "mc": return "Marc"
        case "bn": return "Bolton"
        case "wm": return "William"
        case "jm": return "James"
        case "ge": return "George"
        case "cr": return "Conner"
        case "rt": return "Robert"
        case "co": return "Cole"
        case "hr": return "Harris"
        case "jo": return "Johnny"
        default: return "11am"
        }
    }
}

// MARK: - Menu and notices

private struct TasksMenu: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            if tasks.settings.syncReminders {
                Button("Sync with Reminders now") { Task { await tasks.sync() } }
                Button("Stop syncing with Reminders") { tasks.disableSync() }
            } else {
                Button("Sync with Apple Reminders…") { Task { await tasks.enableSync() } }
            }
            Toggle("Make tasks from promises in mail I send", isOn: Binding(get: { tasks.settings.findPromises }, set: { tasks.setFindPromises($0) }))
            Divider()
            if tasks.hasSample {
                Button("Remove the sample tasks") { tasks.clearSample() }
            } else {
                Button("Try the sample tasks") { tasks.loadSample() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
    }
}

private struct TaskNotice: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let notice = tasks.notice {
            HStack(spacing: 10) {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink(scheme))
                if tasks.canUndoDelete, notice.hasPrefix("Deleted") {
                    Button("Undo") { tasks.undoDelete() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12.5, weight: .semibold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 10)
            .onTapGesture { tasks.notice = nil }
            .task(id: notice) {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if tasks.notice == notice {
                    tasks.notice = nil
                    tasks.canUndoDelete = false
                }
            }
        }
    }
}

// MARK: - Sidebar

private struct TaskSidebar: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @State private var newProject = ""
    @State private var addingProject = false
    @FocusState private var projectFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach([TaskListID.inbox, .today, .upcoming, .someday, .logbook], id: \.self) { list in
                    row(list)
                }
                SectionLabel(text: "Projects")
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    .padding(.leading, 8)
                ForEach(tasks.projects) { project in
                    row(.project(project.id), progress: tasks.book.progress(of: project.id))
                }
                if addingProject {
                    TextField("Project name", text: $newProject)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($projectFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.well(scheme)))
                        .onSubmit {
                            tasks.addProject(newProject)
                            newProject = ""
                            addingProject = false
                        }
                        .onExitCommand { addingProject = false }
                        .onAppear { projectFocused = true }
                } else {
                    Button {
                        addingProject = true
                    } label: {
                        Label("New project", systemImage: "plus")
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                let tags = tasks.book.tags
                if !tags.isEmpty {
                    SectionLabel(text: "Tags")
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                        .padding(.leading, 8)
                    ForEach(tags.prefix(12), id: \.self) { tag in
                        row(.tag(tag))
                    }
                }
            }
        }
    }

    private func row(_ list: TaskListID, progress: (done: Int, total: Int)? = nil) -> some View {
        let selected = tasks.list == list
        let count = list == .logbook ? 0 : tasks.count(list)
        return Button {
            withAnimation(theme.spring) { tasks.list = list }
        } label: {
            HStack(spacing: 9) {
                if let progress, progress.total > 0 {
                    TaskRing(fraction: Double(progress.done) / Double(progress.total))
                        .frame(width: 13, height: 13)
                        .frame(width: 16)
                } else {
                    Image(systemName: tasks.symbol(of: list))
                        .font(.system(size: 12))
                        .frame(width: 16)
                }
                Text(tasks.title(of: list))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .font(.system(size: 11.5, weight: list == .today && tasks.overdueCount > 0 ? .bold : .regular))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.ink(scheme))
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: list)
        }
    }

    /// Dropping a task on a list files it there.
    private func drop(_ items: [String], on list: TaskListID) -> Bool {
        let ids = items.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        for id in ids {
            switch list {
            case .inbox:
                tasks.update(id) { task in
                    task.projectID = nil
                    task.sectionID = nil
                    task.due = nil
                    task.start = nil
                    task.someday = false
                }
            case .today:
                tasks.update(id) { task in
                    task.due = today
                    task.dueHasTime = false
                    task.start = nil
                    task.someday = false
                }
            case .upcoming:
                tasks.update(id) { task in
                    task.due = TaskDates.adding(1, days: today, Calendar.current)
                    task.someday = false
                }
            case .someday:
                tasks.update(id) { task in
                    task.someday = true
                    task.due = nil
                    task.start = nil
                }
            case .logbook:
                if tasks.book.task(id)?.isDone == false { tasks.toggle(id) }
            case .project(let project):
                tasks.move(id, toProject: project)
            case .tag(let tag):
                tasks.update(id) { task in
                    if !task.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { task.tags.append(tag) }
                }
            }
        }
        return true
    }
}

/// How far through a project is.
struct TaskRing: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var fraction: Double

    var body: some View {
        ZStack {
            Circle().strokeBorder(theme.ink(scheme).opacity(0.35), lineWidth: 1.2)
            // A thick arc that fills the middle like a pie.
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(theme.ink(scheme).opacity(0.85), style: StrokeStyle(lineWidth: 3.6))
                .rotationEffect(.degrees(-90))
                .padding(3.4)
        }
    }
}

// MARK: - List

private struct TaskListPane: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @State private var newSection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListTitle()
            if tasks.list != .logbook {
                QuickAddField()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    content
                }
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let shown = tasks.tasks(in: tasks.list)
        switch tasks.list {
        case .upcoming:
            let days = tasks.book.upcomingDays(now: tasks.now, calendar: tasks.calendar)
            if days.isEmpty { empty("Nothing coming up. Dates you give tasks show here.") }
            ForEach(days, id: \.day) { group in
                DayHeading(day: group.day)
                ForEach(group.tasks) { task in TaskRow(task: task, showDay: false) }
            }
        case .today:
            let overdue = shown.filter(tasks.isOverdue)
            let rest = shown.filter { !tasks.isOverdue($0) }
            if shown.isEmpty { empty("Nothing due today. Enjoy it, or pull something in from Upcoming.") }
            if !overdue.isEmpty {
                Heading(text: "Overdue")
                ForEach(overdue) { task in TaskRow(task: task) }
                if !rest.isEmpty { Heading(text: "Today") }
            }
            ForEach(rest) { task in TaskRow(task: task) }
        case .project(let id):
            let project = tasks.project(id)
            let sectionIDs = Set((project?.sections ?? []).map(\.id))
            let loose = shown.filter { task in task.sectionID.map { !sectionIDs.contains($0) } ?? true }
            if shown.isEmpty { empty("No tasks in this project yet. Add one above.") }
            ForEach(loose) { task in TaskRow(task: task, showProject: false) }
            ForEach(project?.sections ?? []) { section in
                Heading(text: section.name)
                    .dropDestination(for: String.self) { items, _ in
                        for id in items.compactMap(UUID.init(uuidString:)) { tasks.move(id, toProject: project?.id, section: section.id) }
                        return true
                    }
                ForEach(shown.filter { $0.sectionID == section.id }) { task in TaskRow(task: task, showProject: false) }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11))
                TextField("New section", text: $newSection)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        tasks.addSection(newSection, to: id)
                        newSection = ""
                    }
            }
            .foregroundStyle(theme.inkTertiary(scheme))
            .padding(.horizontal, 10)
            .padding(.top, 14)
        case .logbook:
            let groups = Dictionary(grouping: shown.prefix(200)) { Calendar.current.startOfDay(for: $0.completed ?? Date()) }
            if shown.isEmpty { empty("What you tick off lands here.") }
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                DayHeading(day: day)
                ForEach(groups[day] ?? []) { task in TaskRow(task: task) }
            }
        case .inbox:
            if shown.isEmpty { empty("Your Inbox is clear. New tasks without a date or project land here.") }
            ForEach(shown) { task in TaskRow(task: task) }
        case .someday:
            if shown.isEmpty { empty("Ideas for one day. Type \"someday\" when you add one.") }
            ForEach(shown) { task in TaskRow(task: task) }
        case .tag:
            ForEach(shown) { task in TaskRow(task: task) }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.inkTertiary(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 18)
    }
}

private struct ListTitle: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tasks.symbol(of: tasks.list))
                .font(.system(size: 17, weight: .medium))
            if renaming, let id = projectID {
                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .onSubmit {
                        tasks.updateProject(id) { $0.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? $0.name : name }
                        renaming = false
                    }
            } else {
                Text(tasks.title(of: tasks.list))
                    .font(.system(size: 22, weight: .bold))
            }
            if tasks.list == .today {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
            if let id = projectID, let project = tasks.project(id) {
                let progress = tasks.book.progress(of: id)
                Text("\(progress.done) of \(progress.total) done" + (project.deadline.map { " · due " + TaskDates.inline(TaskDates.label($0, hasTime: false, now: tasks.now, calendar: tasks.calendar)) } ?? ""))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Menu {
                    Button("Rename") {
                        name = project.name
                        renaming = true
                    }
                    Menu("Icon") {
                        ForEach(["circle.dashed", "globe", "house", "briefcase", "doc.text", "leaf", "airplane", "hammer", "book", "cart", "heart", "graduationcap"], id: \.self) { symbol in
                            Button { tasks.updateProject(id) { $0.symbol = symbol } } label: { Label(symbol, systemImage: symbol) }
                        }
                    }
                    Divider()
                    Button("Delete project (its tasks move to the Inbox)", role: .destructive) { tasks.deleteProject(id) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            } else {
                Spacer()
            }
        }
        .foregroundStyle(theme.ink(scheme))
    }

    private var projectID: UUID? {
        if case .project(let id) = tasks.list { return id }
        return nil
    }
}

private struct Heading: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.inkSecondary(scheme))
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.edge(scheme)).frame(height: 0.5).padding(.horizontal, 10)
            }
    }
}

private struct DayHeading: View {
    @EnvironmentObject private var tasks: TasksModel
    var day: Date

    var body: some View {
        Heading(text: TaskDates.label(day, hasTime: false, now: tasks.now, calendar: tasks.calendar))
    }
}

/// Type a task the way you'd say it. What's understood shows underneath before you press Return.
private struct QuickAddField: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary(scheme))
                TextField("Add a task: \"Call Tom tomorrow 3pm\"", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .focused($focused)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
            let understood = text.isEmpty ? [] : TaskParser.parse(text, now: tasks.now, calendar: tasks.calendar, dayFirst: tasks.dayFirst).understood
            if !understood.isEmpty {
                HStack(spacing: 6) {
                    ForEach(understood, id: \.self) { item in Chip(text: item) }
                }
                .padding(.leading, 4)
                .transition(.opacity)
            }
        }
        .animation(theme.motionEnabled ? .easeOut(duration: 0.15) : nil, value: text.isEmpty)
        .onAppear(perform: takeFocusIfAsked)
        .onChange(of: tasks.wantsFocus) { _, _ in takeFocusIfAsked() }
    }

    private func takeFocusIfAsked() {
        guard tasks.wantsFocus else { return }
        focused = true
        tasks.wantsFocus = false
    }

    private func submit() {
        guard tasks.add(text) != nil else { return }
        text = ""
        focused = true
    }
}

// MARK: - Rows

struct TaskCheck: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var task: TaskItem
    var size: CGFloat = 17
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(theme.ink(scheme).opacity(task.isDone ? 0 : 0.7), lineWidth: task.priority == .high ? 2 : 1.3)
                    .background(Circle().fill(task.isDone ? theme.ink(scheme) : Color.clear))
                if task.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(theme.paper(scheme))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(task.isDone ? "Mark as not done" : "Done")
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var task: TaskItem
    var showProject = true
    var showDay = true
    @State private var hovering = false

    var body: some View {
        let selected = tasks.selectedID == task.id
        HStack(alignment: .top, spacing: 10) {
            TaskCheck(task: task) {
                withAnimation(theme.spring) { tasks.toggle(task.id) }
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13.5))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? theme.inkTertiary(scheme) : theme.ink(scheme))
                    .lineLimit(2)
                TaskMeta(task: task, showProject: showProject, showDay: showDay)
            }
            Spacer(minLength: 6)
            if hovering && !task.isDone {
                SnoozeMenu(task: task)
            }
            if task.priority != TaskPriority.none {
                Text(task.priority.marks)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(theme.ink(scheme))
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? theme.raised(scheme) : (hovering ? theme.well(scheme) : Color.clear)))
        .contentShape(Rectangle())
        .onTapGesture { tasks.selectedID = selected ? nil : task.id }
        .onHover { hovering = $0 }
        .contextMenu { TaskContextMenu(task: task) }
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), id != task.id else { return false }
            withAnimation(theme.spring) { tasks.reorder(id, before: task.id) }
            return true
        }
    }
}

/// The small print under a task: when, repeats, steps, project, tags, who made it.
private struct TaskMeta: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var task: TaskItem
    var showProject = true
    var showDay = true

    var body: some View {
        let overdue = tasks.isOverdue(task)
        let project = showProject ? tasks.project(task.projectID) : nil
        if hasAnything(project: project) {
            FlowLayout(spacing: 9) {
                if !showDay {
                    if task.dueHasTime, let due = task.due {
                        Label(TaskDates.time(due, calendar: tasks.calendar), systemImage: "clock")
                    }
                } else if let due = tasks.dueText(task) {
                    Label(due, systemImage: overdue ? "exclamationmark.circle" : "calendar")
                        .fontWeight(overdue ? .semibold : .regular)
                        .foregroundStyle(overdue ? theme.ink(scheme) : theme.inkTertiary(scheme))
                } else if let start = task.start, start > tasks.now {
                    Label("From " + TaskDates.inline(TaskDates.label(start, hasTime: false, now: tasks.now, calendar: tasks.calendar)), systemImage: "moon.zzz")
                }
                if task.recurrence != nil {
                    Image(systemName: "repeat")
                }
                if !task.checklist.isEmpty {
                    let progress = task.checklistProgress
                    Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                }
                if !task.notes.isEmpty {
                    Image(systemName: "note.text")
                }
                if let project {
                    Label(project.name, systemImage: project.symbol)
                }
                ForEach(task.tags.prefix(3), id: \.self) { tag in
                    Text("#" + tag)
                }
                if let origin = task.origin, origin.kind != .reminders {
                    HStack(spacing: 4) {
                        Monogram(text: origin.monogram, size: 14)
                        Text("from \(AgentNames.name(origin.monogram))")
                    }
                }
                if task.status == .doing || task.status == .waiting {
                    Text(task.status.title)
                        .fontWeight(.medium)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(theme.inkTertiary(scheme))
            .lineLimit(1)
        }
    }

    private func hasAnything(project: TaskProject?) -> Bool {
        task.due != nil || task.start != nil || task.recurrence != nil || !task.checklist.isEmpty || !task.notes.isEmpty
            || project != nil || !task.tags.isEmpty || task.origin != nil || task.status == .doing || task.status == .waiting
    }
}

private struct SnoozeMenu: View {
    @EnvironmentObject private var tasks: TasksModel
    var task: TaskItem

    var body: some View {
        Menu {
            ForEach(SnoozeOption.allCases) { option in
                if let date = option.date(now: Date(), calendar: tasks.calendar) {
                    Button("\(option.title) · \(TaskDates.label(date, hasTime: true, now: Date(), calendar: tasks.calendar))") { tasks.snooze(task.id, option) }
                }
            }
        } label: {
            Image(systemName: "moon.zzz")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Snooze")
    }
}

private struct TaskContextMenu: View {
    @EnvironmentObject private var tasks: TasksModel
    var task: TaskItem

    var body: some View {
        Button(task.isDone ? "Mark as not done" : "Done") { tasks.toggle(task.id) }
        Menu("Snooze") {
            ForEach(SnoozeOption.allCases) { option in
                if option.date(now: Date(), calendar: tasks.calendar) != nil {
                    Button(option.title) { tasks.snooze(task.id, option) }
                }
            }
        }
        Menu("Priority") {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button((priority == TaskPriority.none ? "" : priority.marks + " ") + priority.title) { tasks.update(task.id) { $0.priority = priority } }
            }
        }
        Menu("Move to") {
            Button("Inbox") { tasks.move(task.id, toProject: nil) }
            ForEach(tasks.projects) { project in
                Button(project.name) { tasks.move(task.id, toProject: project.id) }
            }
        }
        Button(task.someday ? "Not someday" : "Someday") {
            tasks.update(task.id) { item in
                item.someday.toggle()
                if item.someday { item.due = nil; item.start = nil }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { tasks.delete(task.id) }
    }
}

// MARK: - Board

private struct TaskBoard: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListTitle()
            GeometryReader { geometry in
                let width = max(200, (geometry.size.width - 36) / 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            column(status, width: width)
                        }
                    }
                    .frame(height: geometry.size.height - 8, alignment: .top)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    /// The open tasks in this list, and what was finished in the last week.
    private var scope: [TaskItem] {
        let open = tasks.list == .logbook ? [] : tasks.tasks(in: tasks.list)
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let done = tasks.book.tasks.filter { task in
            guard let completed = task.completed, completed > weekAgo else { return false }
            switch tasks.list {
            case .project(let id): return task.projectID == id
            case .tag(let tag): return task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            case .inbox: return task.projectID == nil
            default: return true
            }
        }
        return open + done.sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
    }

    private func column(_ status: TaskStatus, width: CGFloat) -> some View {
        let items = scope.filter { status == .done ? $0.isDone : (!$0.isDone && $0.status == status) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(items.count)")
                    .monospacedDigit()
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 4)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(items) { task in BoardCard(task: task) }
                    if items.isEmpty {
                        Text(status == .waiting ? "Drag here what's waiting on someone else." : "Drag tasks here.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.well(scheme).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                if status != .done, tasks.book.task(id)?.isDone == true { tasks.toggle(id) }
                withAnimation(theme.spring) { tasks.setStatus(id, status) }
            }
            return true
        }
    }
}

private struct BoardCard: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var task: TaskItem

    var body: some View {
        let selected = tasks.selectedID == task.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                TaskCheck(task: task, size: 15) { withAnimation(theme.spring) { tasks.toggle(task.id) } }
                    .padding(.top, 1)
                Text(task.title)
                    .font(.system(size: 13))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? theme.inkTertiary(scheme) : theme.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if task.priority != TaskPriority.none {
                    Text(task.priority.marks).font(.system(size: 11, weight: .heavy))
                }
            }
            TaskMeta(task: task, showProject: !isProjectList)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? theme.raised(scheme) : theme.paper(scheme).opacity(scheme == .dark ? 0.35 : 0.8)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? theme.ink(scheme).opacity(0.5) : theme.edge(scheme), lineWidth: selected ? 1 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture { tasks.selectedID = selected ? nil : task.id }
        .draggable(task.id.uuidString)
        .contextMenu { TaskContextMenu(task: task) }
    }

    private var isProjectList: Bool {
        if case .project = tasks.list { return true }
        return false
    }
}

// MARK: - Week

/// The next seven days with your calendar alongside, so you can see where tasks fit. Drag a task onto a day.
private struct TaskWeek: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let cal = tasks.calendar
        let today = cal.startOfDay(for: tasks.now)
        VStack(alignment: .leading, spacing: 12) {
            if isScoped {
                ListTitle()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "calendar").font(.system(size: 17, weight: .medium))
                    Text("The week ahead").font(.system(size: 22, weight: .bold))
                    Text("Your calendar alongside. Drag a task onto a day.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.ink(scheme))
            }
            GeometryReader { geometry in
                // At least 120 points a day: seven on a wide window, fewer on a narrow one.
                let count = max(3, min(7, Int((geometry.size.width + 8) / 128)))
                let days = (0..<count).map { TaskDates.adding($0, days: today, cal) }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        dayColumn(day, isToday: day == today)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            let loose = unscheduled
            if !loose.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Not scheduled · drag onto a day")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(loose.prefix(30)) { task in
                                Text(task.title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(theme.well(scheme)))
                                    .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                                    .foregroundStyle(theme.ink(scheme))
                                    .onTapGesture { tasks.selectedID = task.id }
                                    .draggable(task.id.uuidString)
                            }
                        }
                    }
                }
            }
        }
    }

    private var isScoped: Bool {
        switch tasks.list {
        case .project, .tag: return true
        default: return false
        }
    }

    private func inScope(_ task: TaskItem) -> Bool {
        switch tasks.list {
        case .project(let id): return task.projectID == id
        case .tag(let tag): return task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        default: return true
        }
    }

    private var unscheduled: [TaskItem] {
        tasks.book.tasks.filter { !$0.isDone && $0.due == nil && !$0.someday && inScope($0) }
    }

    private func tasksOn(_ day: Date, isToday: Bool) -> [TaskItem] {
        let cal = tasks.calendar
        let open = tasks.book.tasks.filter { !$0.isDone && inScope($0) }
        let due = open.filter { task in
            guard let date = task.due else { return false }
            return cal.isDate(date, inSameDayAs: day) || (isToday && date < day)
        }
        return tasks.book.sorted(due, now: tasks.now, calendar: cal)
    }

    private func dayColumn(_ day: Date, isToday: Bool) -> some View {
        let cal = tasks.calendar
        let items = tasksOn(day, isToday: isToday)
        let events = calendar.events(on: day).filter { !$0.isAllDay }.prefix(5)
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 12, weight: .semibold))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 20, weight: isToday ? .bold : .regular))
            }
            .foregroundStyle(theme.ink(scheme))
            ForEach(Array(events), id: \.id) { event in
                Text(TaskDates.time(event.start, calendar: cal) + " " + event.title)
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            if !events.isEmpty {
                Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { task in
                        HStack(alignment: .top, spacing: 6) {
                            TaskCheck(task: task, size: 13) { withAnimation(theme.spring) { tasks.toggle(task.id) } }
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title)
                                    .font(.system(size: 11.5, weight: tasks.isOverdue(task) ? .semibold : .regular))
                                    .lineLimit(3)
                                if task.dueHasTime, let due = task.due {
                                    Text(TaskDates.time(due, calendar: cal))
                                        .font(.system(size: 10))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                            }
                        }
                        .foregroundStyle(theme.ink(scheme))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tasks.selectedID == task.id ? theme.raised(scheme) : theme.well(scheme)))
                        .contentShape(Rectangle())
                        .onTapGesture { tasks.selectedID = task.id }
                        .draggable(task.id.uuidString)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isToday ? theme.raised(scheme).opacity(0.7) : theme.well(scheme).opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                withAnimation(theme.spring) { tasks.schedule(id, on: day) }
            }
            return true
        }
    }
}
