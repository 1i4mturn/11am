import SwiftUI

/// Everything about one task: when, how often, how important, where it lives, its steps, and where it came from.
struct TaskInspector: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var task: TaskItem
    @State private var newStep = ""
    @State private var newTag = ""
    @State private var repeatText = ""

    private var cal: Calendar { tasks.calendar }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    TaskCheck(task: task, size: 20) { withAnimation(theme.spring) { tasks.toggle(task.id) } }
                    Text(task.isDone ? "Done " + TaskDates.label(task.completed ?? Date(), hasTime: false, now: tasks.now, calendar: cal).lowercased() : task.status.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkTertiary(scheme))
                    Spacer()
                    Button { tasks.selectedID = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Close")
                }

                TextField("Task", text: Binding(get: { task.title }, set: { value in tasks.update(task.id) { $0.title = value } }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                TextField("Notes", text: Binding(get: { task.notes }, set: { value in tasks.update(task.id) { $0.notes = value } }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(2...10)
                    .foregroundStyle(theme.inkSecondary(scheme))

                if let origin = task.origin, origin.kind != .reminders {
                    OriginCard(origin: origin)
                }

                group("When") { when }
                group("Repeat") { repeats }
                group("Priority") {
                    Picker("", selection: Binding(get: { task.priority }, set: { value in tasks.update(task.id) { $0.priority = value } })) {
                        Text("None").tag(TaskPriority.none)
                        Text("!").tag(TaskPriority.low)
                        Text("!!").tag(TaskPriority.medium)
                        Text("!!!").tag(TaskPriority.high)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if !task.isDone {
                    group("Status") {
                        Picker("", selection: Binding(get: { task.status == .done ? .todo : task.status }, set: { value in tasks.setStatus(task.id, value) })) {
                            ForEach([TaskStatus.todo, .doing, .waiting], id: \.self) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                group("Project") { project }
                group("Tags") { tags }
                group("Steps") { steps }

                footer
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: title)
            content()
        }
    }

    // MARK: When

    @ViewBuilder private var when: some View {
        let today = cal.startOfDay(for: Date())
        Toggle("Due", isOn: Binding(get: { task.due != nil }, set: { on in
            tasks.update(task.id) { item in
                item.due = on ? today : nil
                item.dueHasTime = false
                if on { item.someday = false }
            }
        }))
        .toggleStyle(.switch)
        .controlSize(.small)
        if let due = task.due {
            HStack(spacing: 8) {
                DatePicker("", selection: Binding(get: { due }, set: { value in
                    tasks.update(task.id) { item in
                        let parts = cal.dateComponents([.hour, .minute], from: item.due ?? value)
                        item.due = item.dueHasTime ? TaskDates.at(parts.hour ?? 9, parts.minute ?? 0, on: value, cal) : cal.startOfDay(for: value)
                    }
                }), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                Toggle("Time", isOn: Binding(get: { task.dueHasTime }, set: { on in
                    tasks.update(task.id) { item in
                        guard let day = item.due else { return }
                        item.dueHasTime = on
                        item.due = on ? TaskDates.at(9, 0, on: day, cal) : cal.startOfDay(for: day)
                    }
                }))
                .toggleStyle(.checkbox)
                if task.dueHasTime {
                    DatePicker("", selection: Binding(get: { due }, set: { value in
                        tasks.update(task.id) { item in
                            let parts = cal.dateComponents([.hour, .minute], from: value)
                            item.due = TaskDates.at(parts.hour ?? 9, parts.minute ?? 0, on: item.due ?? value, cal)
                        }
                    }), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
            HStack(spacing: 6) {
                quickDay("Today", today)
                quickDay("Tomorrow", TaskDates.adding(1, days: today, cal))
                quickDay("Next week", TaskDates.adding(7, days: TaskDates.monday(of: today, cal), cal))
            }
        }
        Toggle("Hide until a start date", isOn: Binding(get: { task.start != nil }, set: { on in
            tasks.update(task.id) { item in
                item.start = on ? TaskDates.at(9, 0, on: TaskDates.adding(1, days: today, cal), cal) : nil
                if on { item.someday = false }
            }
        }))
        .toggleStyle(.switch)
        .controlSize(.small)
        if let start = task.start {
            DatePicker("", selection: Binding(get: { start }, set: { value in tasks.update(task.id) { $0.start = value } }), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        if task.due == nil && task.start == nil {
            Toggle("Someday", isOn: Binding(get: { task.someday }, set: { on in tasks.update(task.id) { $0.someday = on } }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func quickDay(_ title: String, _ day: Date) -> some View {
        Button(title) { tasks.schedule(task.id, on: day) }
            .buttonStyle(.vellumSecondary)
            .controlSize(.small)
    }

    // MARK: Repeat

    @ViewBuilder private var repeats: some View {
        let weekday = cal.component(.weekday, from: task.due ?? task.start ?? Date())
        let presets: [(String, Recurrence?)] = [
            ("Doesn't repeat", nil),
            ("Every day", Recurrence(unit: .day)),
            ("Every weekday", Recurrence(unit: .weekday)),
            ("Every week", Recurrence(unit: .week, weekdays: [weekday])),
            ("Every fortnight", Recurrence(unit: .week, every: 2, weekdays: [weekday])),
            ("Every month", Recurrence(unit: .month)),
            ("Every year", Recurrence(unit: .year)),
        ]
        Menu {
            ForEach(presets.indices, id: \.self) { index in
                Button(presets[index].0) { setRepeat(presets[index].1) }
            }
        } label: {
            Text(task.recurrence?.text ?? "Doesn't repeat")
        }
        .menuStyle(.button)
        .fixedSize()
        TextField("Or type it: every 3 days, every Mon and Thu", text: $repeatText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.well(scheme)))
            .onSubmit {
                let words = repeatText.lowercased().hasPrefix("every") || ["daily", "weekly", "fortnightly", "monthly", "yearly"].contains(repeatText.lowercased()) ? repeatText : "every " + repeatText
                if let rule = TaskParser.parse(words, now: Date(), calendar: cal, dayFirst: tasks.dayFirst).recurrence {
                    setRepeat(rule)
                    repeatText = ""
                } else {
                    tasks.notice = "Leo didn't follow that. Try \"every 2 weeks\" or \"every Mon and Thu\"."
                }
            }
        if let rule = task.recurrence {
            Toggle("Count from when it's done", isOn: Binding(get: { rule.afterCompletion }, set: { on in
                tasks.update(task.id) { $0.recurrence?.afterCompletion = on }
            }))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
    }

    private func setRepeat(_ rule: Recurrence?) {
        tasks.update(task.id) { item in
            item.recurrence = rule
            if let rule, item.due == nil, item.start == nil {
                item.due = TaskParser.firstOccurrence(of: rule, now: Date(), calendar: cal)
                item.someday = false
            }
        }
    }

    // MARK: Project, tags, steps

    @ViewBuilder private var project: some View {
        Picker("", selection: Binding(get: { task.projectID }, set: { value in tasks.move(task.id, toProject: value) })) {
            Text("Inbox (no project)").tag(UUID?.none)
            ForEach(tasks.projects) { project in
                Text(project.name).tag(Optional(project.id))
            }
        }
        .labelsHidden()
        if let current = tasks.project(task.projectID), !current.sections.isEmpty {
            Picker("", selection: Binding(get: { task.sectionID }, set: { value in tasks.move(task.id, toProject: current.id, section: value) })) {
                Text("No section").tag(UUID?.none)
                ForEach(current.sections) { section in
                    Text(section.name).tag(Optional(section.id))
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder private var tags: some View {
        if !task.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(task.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#" + tag)
                        Button {
                            tasks.update(task.id) { $0.tags.removeAll { $0 == tag } }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.well(scheme)))
                    .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
                }
            }
        }
        TextField("Add a tag", text: $newTag)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.well(scheme)))
            .onSubmit {
                let tag = newTag.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#")))
                if !tag.isEmpty {
                    tasks.update(task.id) { item in
                        if !item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { item.tags.append(tag) }
                    }
                }
                newTag = ""
            }
    }

    @ViewBuilder private var steps: some View {
        ForEach(task.checklist) { step in
            HStack(spacing: 8) {
                Button { tasks.toggleStep(step.id, in: task.id) } label: {
                    Image(systemName: step.done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                Text(step.title)
                    .font(.system(size: 12.5))
                    .strikethrough(step.done)
                    .foregroundStyle(step.done ? theme.inkTertiary(scheme) : theme.ink(scheme))
                Spacer(minLength: 4)
                Button { tasks.removeStep(step.id, in: task.id) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
        }
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11))
            TextField("Add a step", text: $newStep)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit {
                    tasks.addStep(newStep, to: task.id)
                    newStep = ""
                }
        }
        .foregroundStyle(theme.inkTertiary(scheme))
        Button {
            tasks.breakDown(task.id)
        } label: {
            HStack(spacing: 6) {
                if tasks.breakingDown == task.id {
                    ProgressView().controlSize(.small)
                    Text("Leo is breaking it down…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Break it into steps")
                }
            }
        }
        .buttonStyle(.vellumSecondary)
        .disabled(tasks.breakingDown != nil)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                if !task.isDone {
                    Menu("Snooze") {
                        ForEach(SnoozeOption.allCases) { option in
                            if option.date(now: Date(), calendar: cal) != nil {
                                Button(option.title) { tasks.snooze(task.id, option) }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                Spacer()
                Button("Delete", role: .destructive) { tasks.delete(task.id) }
                    .buttonStyle(.vellumSecondary)
            }
            Text(footnote)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
    }

    private var footnote: String {
        var parts = ["Added " + TaskDates.label(task.created, hasTime: false, now: tasks.now, calendar: cal).lowercased()]
        if task.reminderID != nil { parts.append("in Reminders") }
        if task.origin?.kind == .reminders { parts.append("came from Reminders") }
        return parts.joined(separator: " · ")
    }
}

/// "Marc made this from your email to Tom", with the words it came from.
private struct OriginCard: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var origin: TaskOrigin

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Monogram(text: origin.monogram, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(AgentNames.name(origin.monogram)) added this")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text(origin.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
                if let quote = origin.quote, !quote.isEmpty {
                    Text("“\(quote)”")
                        .font(.system(size: 11.5).italic())
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if origin.reference != nil, origin.kind == .mail || origin.kind == .meeting {
                    Button(origin.kind == .mail ? "Open the email" : "Open the event") { tasks.onOpenOrigin?(origin) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
    }
}
