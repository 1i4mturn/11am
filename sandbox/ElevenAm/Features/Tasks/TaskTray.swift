import SwiftUI

/// Above the calendar: today's and the week's tasks that don't have a time yet. Drag one onto the calendar to block time for it.
struct TaskTray: View {
    @EnvironmentObject private var tasks: TasksModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let soon = tasks.tasks(in: .today).filter { !$0.dueHasTime }
            + tasks.tasks(in: .upcoming).filter { task in
                !task.dueHasTime && (task.due.map { $0 < TaskDates.adding(7, days: Date(), tasks.calendar) } ?? false)
            }
        if !soon.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary(scheme))
                Text("Fit in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                    .help("Drag a task onto the calendar to block time for it")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(soon.prefix(12)) { task in
                            HStack(spacing: 5) {
                                if tasks.isOverdue(task) {
                                    Image(systemName: "exclamationmark.circle").font(.system(size: 9.5))
                                }
                                Text(task.title).lineLimit(1)
                                if let due = task.due, !Calendar.current.isDateInToday(due) {
                                    Text(due.formatted(.dateTime.weekday(.abbreviated)))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.ink(scheme))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(theme.raised(scheme)))
                            .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                            .draggable(task.id.uuidString) {
                                Text("Focus: \(task.title)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.raised(scheme)))
                            }
                            .help("Drag onto the calendar to block an hour for it")
                        }
                    }
                }
                Text("Drag onto the calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize()
            }
        }
    }
}
