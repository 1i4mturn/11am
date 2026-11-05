import SwiftUI

/// Today's tasks on the Today page, to tick off without leaving it.
struct TodayTasksCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let today = tasks.tasks(in: .today)
        if !today.isEmpty || !tasks.book.tasks.isEmpty {
            Card {
                HStack {
                    SectionLabel(text: today.isEmpty ? "Tasks" : "Tasks today · \(today.count)")
                    Spacer()
                    Button("Open Tasks") {
                        tasks.list = .today
                        model.go(to: .tasks)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                }
                if today.isEmpty {
                    Text("Nothing due today.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                ForEach(today.prefix(6)) { task in
                    HStack(spacing: 10) {
                        TaskCheck(task: task, size: 15) {
                            withAnimation(theme.spring) { tasks.toggle(task.id) }
                        }
                        Text(task.title)
                            .font(.system(size: 13, weight: tasks.isOverdue(task) ? .semibold : .regular))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(1)
                        if tasks.isOverdue(task) {
                            Text("overdue")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        } else if task.dueHasTime, let due = task.due {
                            Text(TaskDates.time(due, calendar: tasks.calendar))
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                        Spacer(minLength: 6)
                        if task.priority != TaskPriority.none {
                            Text(task.priority.marks).font(.system(size: 11, weight: .heavy))
                        }
                        if let origin = task.origin, origin.kind != .reminders {
                            Monogram(text: origin.monogram, size: 16)
                                .help("\(AgentNames.name(origin.monogram)) added this: \(origin.label)")
                        }
                    }
                }
                if today.count > 6 {
                    Text("and \(today.count - 6) more")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
        }
    }
}
