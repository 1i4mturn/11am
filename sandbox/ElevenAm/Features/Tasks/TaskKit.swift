import Foundation

// Leo's Tasks: tasks, projects with sections, smart lists, natural-language quick add, repeats, snoozing,
// promises found in the mail you send, and the merge rules for syncing with Apple Reminders.
// Foundation only, so it's tested on its own.

// MARK: - Basics

enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0, low, medium, high

    var title: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// "!", "!!" or "!!!", as typed in quick add.
    var marks: String { String(repeating: "!", count: rawValue) }

    static func < (a: TaskPriority, b: TaskPriority) -> Bool { a.rawValue < b.rawValue }
}

/// The columns of the board.
enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, doing, waiting, done

    var title: String {
        switch self {
        case .todo: return "To do"
        case .doing: return "Doing"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }
}

struct ChecklistItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var done = false
}

/// Where a task came from when 11am made it, so you can always see why it's there.
struct TaskOrigin: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case mail, meeting, note, reminders, agent, imported }

    var kind: Kind
    /// The agent who made it, by monogram ("mc" for Marc).
    var monogram: String
    /// What it came from, in a line: "Your email to Tom Baker · Deck for Friday".
    var label: String
    /// Opens the source again: a message ID, an event ID, a note ID.
    var reference: String?
    /// The words it was found in.
    var quote: String?
}

/// How a task repeats.
struct Recurrence: Codable, Hashable, Sendable {
    enum Unit: String, Codable, CaseIterable, Sendable { case day, weekday, week, month, year }

    var unit: Unit
    var every = 1
    /// For weekly repeats on particular days, as Calendar weekday numbers (1 is Sunday).
    var weekdays: [Int] = []
    /// Counts from when you tick it off rather than from when it was due ("3 days after I last watered them").
    var afterCompletion = false

    /// The next date after `date` (time of day kept).
    func next(after date: Date, calendar: Calendar) -> Date {
        let n = max(1, every)
        switch unit {
        case .day:
            return TaskDates.adding(n, days: date, calendar)
        case .weekday:
            var day = date
            repeat { day = TaskDates.adding(1, days: day, calendar) } while calendar.isDateInWeekend(day)
            return day
        case .week:
            guard !weekdays.isEmpty else { return TaskDates.adding(7 * n, days: date, calendar) }
            let baseWeek = TaskDates.monday(of: date, calendar)
            var day = date
            for _ in 0..<(7 * n + 7) {
                day = TaskDates.adding(1, days: day, calendar)
                guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                let days = calendar.dateComponents([.day], from: baseWeek, to: TaskDates.monday(of: day, calendar)).day ?? 0
                if (days / 7) % n == 0 { return day }
            }
            return TaskDates.adding(7 * n, days: date, calendar)
        case .month:
            return calendar.date(byAdding: .month, value: n, to: date) ?? date
        case .year:
            return calendar.date(byAdding: .year, value: n, to: date) ?? date
        }
    }

    /// "Every 2 weeks on Monday and Thursday".
    var text: String {
        let n = max(1, every)
        var line: String
        switch unit {
        case .day: line = n == 1 ? "Every day" : "Every \(n) days"
        case .weekday: line = "Every weekday"
        case .week:
            let names = weekdays.sorted { TaskDates.mondayFirst($0) < TaskDates.mondayFirst($1) }.map { TaskDates.dayNames[TaskDates.mondayFirst($0)] }
            if n == 1 {
                line = names.isEmpty ? "Every week" : "Every " + TaskText.join(names)
            } else {
                line = (n == 2 ? "Every fortnight" : "Every \(n) weeks") + (names.isEmpty ? "" : " on " + TaskText.join(names))
            }
        case .month: line = n == 1 ? "Every month" : "Every \(n) months"
        case .year: line = n == 1 ? "Every year" : "Every \(n) years"
        }
        if afterCompletion { line += " after it's done" }
        return line
    }
}

struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var notes = ""
    var projectID: UUID?
    var sectionID: UUID?
    var status: TaskStatus = .todo
    var priority: TaskPriority = .none
    var tags: [String] = []
    /// When it's due; `dueHasTime` says whether the time of day matters.
    var due: Date?
    var dueHasTime = false
    /// When it starts to show. Snoozing moves this: the task stays out of Today and the Inbox until then.
    var start: Date?
    var someday = false
    var checklist: [ChecklistItem] = []
    var recurrence: Recurrence?
    var created = Date()
    var modified = Date()
    var completed: Date?
    var origin: TaskOrigin?
    /// The linked Apple Reminders item, when syncing.
    var reminderID: String?
    var order: Double = 0

    var isDone: Bool { completed != nil }

    var checklistProgress: (done: Int, total: Int) {
        (checklist.filter(\.done).count, checklist.count)
    }
}

extension TaskItem {
    /// Tolerant of fields added in later versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        sectionID = try c.decodeIfPresent(UUID.self, forKey: .sectionID)
        status = (try? c.decodeIfPresent(TaskStatus.self, forKey: .status)) ?? .todo
        priority = (try? c.decodeIfPresent(TaskPriority.self, forKey: .priority)) ?? TaskPriority.none
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        someday = try c.decodeIfPresent(Bool.self, forKey: .someday) ?? false
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        recurrence = try? c.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? created
        completed = try c.decodeIfPresent(Date.self, forKey: .completed)
        origin = try? c.decodeIfPresent(TaskOrigin.self, forKey: .origin)
        reminderID = try c.decodeIfPresent(String.self, forKey: .reminderID)
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
    }
}

struct TaskSection: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
}

struct TaskProject: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var notes = ""
    var symbol = "circle.dashed"
    var sections: [TaskSection] = []
    var deadline: Date?
    var archived = false
    /// The Reminders list it syncs with.
    var reminderListID: String?
}

/// The smart lists down the side, then projects and tags.
enum TaskListID: Hashable, Codable, Sendable {
    case inbox, today, upcoming, someday, logbook
    case project(UUID)
    case tag(String)
}

// MARK: - Dates

enum TaskDates {
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// 0 for Monday … 6 for Sunday, from a Calendar weekday (1 is Sunday).
    static func mondayFirst(_ weekday: Int) -> Int { (weekday + 5) % 7 }

    static func adding(_ days: Int, days date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    /// Monday of the week `date` is in, at midnight.
    static func monday(of date: Date, _ calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return adding(-mondayFirst(calendar.component(.weekday, from: day)), days: day, calendar)
    }

    static func endOfDay(_ date: Date, _ calendar: Calendar) -> Date {
        adding(1, days: calendar.startOfDay(for: date), calendar)
    }

    static func at(_ hour: Int, _ minute: Int, on day: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }

    /// The next date with this weekday, today included if `includeToday`.
    static func next(weekday: Int, from now: Date, includeToday: Bool, _ calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        var ahead = (weekday - calendar.component(.weekday, from: today) + 7) % 7
        if ahead == 0 && !includeToday { ahead = 7 }
        return adding(ahead, days: today, calendar)
    }

    /// "Today", "Tomorrow", "Friday", "Fri 14 Nov", with ", 3:00 pm" when the time matters.
    static func label(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar, locale: Locale = Locale(identifier: "en_AU")) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        var text: String
        switch offset {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case -1: text = "Yesterday"
        case 2...6: text = dayNames[mondayFirst(calendar.component(.weekday, from: day))]
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: day) == calendar.component(.year, from: today) ? "EEE d MMM" : "d MMM yyyy")
            text = formatter.string(from: day)
        }
        if hasTime { text += ", " + time(date, calendar: calendar) }
        return text
    }

    /// "3 pm", "3:30 pm".
    static func time(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(twelve) \(suffix)" : String(format: "%d:%02d %@", twelve, minute, suffix)
    }
}

enum TaskText {
    /// "a", "a and b", "a, b and c".
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

// MARK: - The book of tasks

struct TaskBook: Codable, Sendable {
    var tasks: [TaskItem] = []
    var projects: [TaskProject] = []
    /// Recently removed tasks, newest first, so a slip can be undone.
    var removed: [TaskItem] = []

    init(tasks: [TaskItem] = [], projects: [TaskProject] = [], removed: [TaskItem] = []) {
        self.tasks = tasks
        self.projects = projects
        self.removed = removed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try c.decodeIfPresent([TaskProject].self, forKey: .projects) ?? []
        removed = try c.decodeIfPresent([TaskItem].self, forKey: .removed) ?? []
    }

    private enum CodingKeys: String, CodingKey { case tasks, projects, removed }

    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }
    func project(_ id: UUID?) -> TaskProject? { id.flatMap { id in projects.first { $0.id == id } } }

    // MARK: Which list a task is in

    func isInbox(_ task: TaskItem) -> Bool {
        !task.isDone && task.projectID == nil && task.due == nil && task.start == nil && !task.someday
    }

    func isToday(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard !task.isDone else { return false }
        if let start = task.start, start > now { return false }
        if let due = task.due, due < TaskDates.endOfDay(now, calendar) { return true }
        return task.start != nil
    }

    func isOverdue(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard !task.isDone, let due = task.due else { return false }
        return task.dueHasTime ? due < now : due < calendar.startOfDay(for: now)
    }

    /// The day a task shows under in Upcoming, if it's in the future.
    func upcomingDate(_ task: TaskItem, now: Date, calendar: Calendar) -> Date? {
        guard !task.isDone else { return nil }
        if let start = task.start, start > now { return start }
        if let due = task.due, due >= TaskDates.endOfDay(now, calendar) { return due }
        return nil
    }

    func isSomeday(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        task.someday && !task.isDone && task.due == nil && !isToday(task, now: now, calendar: calendar)
            && upcomingDate(task, now: now, calendar: calendar) == nil
    }

    /// The tasks in a list, in the order they're shown.
    func tasks(in list: TaskListID, now: Date, calendar: Calendar) -> [TaskItem] {
        switch list {
        case .inbox:
            return sorted(tasks.filter(isInbox), now: now, calendar: calendar)
        case .today:
            return sorted(tasks.filter { isToday($0, now: now, calendar: calendar) }, now: now, calendar: calendar)
        case .upcoming:
            return tasks.compactMap { task in upcomingDate(task, now: now, calendar: calendar).map { (task, $0) } }
                .sorted { ($0.1, $0.0.order) < ($1.1, $1.0.order) }.map(\.0)
        case .someday:
            return sorted(tasks.filter { isSomeday($0, now: now, calendar: calendar) }, now: now, calendar: calendar)
        case .logbook:
            return tasks.filter(\.isDone).sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        case .project(let id):
            let project = self.project(id)
            let sectionOrder = Dictionary(uniqueKeysWithValues: (project?.sections ?? []).enumerated().map { ($1.id, $0) })
            return tasks.filter { $0.projectID == id && !$0.isDone }
                .sorted { a, b in
                    let sa = a.sectionID.flatMap { sectionOrder[$0] } ?? -1
                    let sb = b.sectionID.flatMap { sectionOrder[$0] } ?? -1
                    if sa != sb { return sa < sb }
                    return a.order < b.order
                }
        case .tag(let tag):
            return sorted(tasks.filter { !$0.isDone && $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }, now: now, calendar: calendar)
        }
    }

    /// Overdue first, then the most important, then the soonest, then your own order.
    func sorted(_ list: [TaskItem], now: Date, calendar: Calendar) -> [TaskItem] {
        list.sorted { a, b in
            let oa = isOverdue(a, now: now, calendar: calendar), ob = isOverdue(b, now: now, calendar: calendar)
            if oa != ob { return oa }
            if a.priority != b.priority { return a.priority > b.priority }
            let da = a.due ?? .distantFuture, db = b.due ?? .distantFuture
            if da != db { return da < db }
            if a.order != b.order { return a.order < b.order }
            return a.created < b.created
        }
    }

    /// Upcoming, grouped by day.
    func upcomingDays(now: Date, calendar: Calendar) -> [(day: Date, tasks: [TaskItem])] {
        var groups: [Date: [TaskItem]] = [:]
        for task in tasks(in: .upcoming, now: now, calendar: calendar) {
            guard let date = upcomingDate(task, now: now, calendar: calendar) else { continue }
            groups[calendar.startOfDay(for: date), default: []].append(task)
        }
        return groups.keys.sorted().map { (day: $0, tasks: groups[$0] ?? []) }
    }

    func count(_ list: TaskListID, now: Date, calendar: Calendar) -> Int {
        tasks(in: list, now: now, calendar: calendar).count
    }

    /// Every tag in use, most used first.
    var tags: [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for task in tasks where !task.isDone {
            for tag in task.tags {
                let key = tag.lowercased()
                counts[key] = (counts[key]?.name ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        return counts.values.sorted { ($1.count, $0.name) < ($0.count, $1.name) }.map(\.name)
    }

    func progress(of projectID: UUID) -> (done: Int, total: Int) {
        let all = tasks.filter { $0.projectID == projectID }
        return (all.filter(\.isDone).count, all.count)
    }

    // MARK: Changes

    @discardableResult
    mutating func add(_ task: TaskItem) -> UUID {
        var task = task
        task.order = (tasks.map(\.order).max() ?? 0) + 1
        tasks.append(task)
        return task.id
    }

    mutating func update(_ id: UUID, now: Date, _ change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
        tasks[index].modified = now
    }

    /// Ticks a task off. A repeating task gets its next one, which is returned.
    @discardableResult
    mutating func complete(_ id: UUID, now: Date, calendar: Calendar) -> UUID? {
        guard let index = tasks.firstIndex(where: { $0.id == id }), !tasks[index].isDone else { return nil }
        let task = tasks[index]
        tasks[index].completed = now
        tasks[index].status = .done
        tasks[index].modified = now
        guard let rule = task.recurrence, let next = TaskBook.nextOccurrence(of: task, rule: rule, now: now, calendar: calendar) else { return nil }
        return add(next)
    }

    static func nextOccurrence(of task: TaskItem, rule: Recurrence, now: Date, calendar: Calendar) -> TaskItem? {
        guard let anchor = task.due ?? task.start else {
            // A repeat with no date starts from today.
            var next = task
            next.id = UUID()
            next.due = rule.next(after: calendar.startOfDay(for: now), calendar: calendar)
            return fresh(next, now: now)
        }
        var base: Date
        if rule.afterCompletion {
            base = calendar.startOfDay(for: now)
            if task.dueHasTime || task.due == nil {
                let parts = calendar.dateComponents([.hour, .minute], from: anchor)
                base = TaskDates.at(parts.hour ?? 0, parts.minute ?? 0, on: base, calendar)
            }
        } else {
            base = anchor
        }
        var nextAnchor = rule.next(after: base, calendar: calendar)
        // Missed a few? Skip to the first one from today, not a pile of overdue copies.
        var guardCount = 0
        while !rule.afterCompletion && nextAnchor < calendar.startOfDay(for: now) && guardCount < 1_000 {
            nextAnchor = rule.next(after: nextAnchor, calendar: calendar)
            guardCount += 1
        }
        var next = task
        next.id = UUID()
        if let due = task.due {
            next.due = nextAnchor
            next.start = task.start.map { nextAnchor.addingTimeInterval($0.timeIntervalSince(due)) }
        } else {
            next.start = nextAnchor
        }
        return fresh(next, now: now)
    }

    private static func fresh(_ task: TaskItem, now: Date) -> TaskItem {
        var task = task
        task.completed = nil
        task.status = .todo
        task.created = now
        task.modified = now
        task.reminderID = nil
        task.checklist = task.checklist.map { ChecklistItem(id: UUID(), title: $0.title, done: false) }
        return task
    }

    mutating func reopen(_ id: UUID, now: Date) {
        update(id, now: now) { task in
            task.completed = nil
            if task.status == .done { task.status = .todo }
        }
    }

    /// Moves a task on the board; Done ticks it off.
    @discardableResult
    mutating func setStatus(_ id: UUID, _ status: TaskStatus, now: Date, calendar: Calendar) -> UUID? {
        if status == .done { return complete(id, now: now, calendar: calendar) }
        update(id, now: now) { task in
            task.status = status
            task.completed = nil
        }
        return nil
    }

    mutating func snooze(_ id: UUID, until date: Date, now: Date) {
        update(id, now: now) { task in
            task.start = date
            task.someday = false
        }
    }

    mutating func remove(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        removed.insert(tasks.remove(at: index), at: 0)
        if removed.count > 50 { removed.removeLast(removed.count - 50) }
    }

    @discardableResult
    mutating func undoRemove() -> UUID? {
        guard !removed.isEmpty else { return nil }
        let task = removed.removeFirst()
        tasks.append(task)
        return task.id
    }

    /// Puts `id` just before `before` (or at the end) among the tasks shown together.
    mutating func move(_ id: UUID, before: UUID?, among shown: [TaskItem], now: Date) {
        let others = shown.filter { $0.id != id }
        let position = before.flatMap { target in others.firstIndex { $0.id == target } } ?? others.count
        let lower = position > 0 ? others[position - 1].order : (others.first?.order ?? 1) - 1
        let upper = position < others.count ? others[position].order : lower + 2
        update(id, now: now) { $0.order = (lower + upper) / 2 }
    }

    mutating func removeProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        for index in tasks.indices where tasks[index].projectID == id {
            tasks[index].projectID = nil
            tasks[index].sectionID = nil
        }
    }
}

// MARK: - Snoozing

enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
    case laterToday, thisEvening, tomorrow, thisWeekend, nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .laterToday: return "Later today"
        case .thisEvening: return "This evening"
        case .tomorrow: return "Tomorrow"
        case .thisWeekend: return "This weekend"
        case .nextWeek: return "Next week"
        }
    }

    /// When the task comes back, or nil when it doesn't make sense now (this evening, at 9 pm).
    func date(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .laterToday:
            let later = now.addingTimeInterval(3 * 3_600)
            let hour = calendar.dateInterval(of: .hour, for: later)?.start ?? later
            return calendar.isDate(hour, inSameDayAs: now) ? hour : nil
        case .thisEvening:
            let evening = TaskDates.at(18, 0, on: now, calendar)
            return evening > now ? evening : nil
        case .tomorrow:
            return TaskDates.at(9, 0, on: TaskDates.adding(1, days: now, calendar), calendar)
        case .thisWeekend:
            let weekday = calendar.component(.weekday, from: now)
            if weekday == 7 || weekday == 1 { return nil }
            return TaskDates.at(9, 0, on: TaskDates.next(weekday: 7, from: now, includeToday: false, calendar), calendar)
        case .nextWeek:
            return TaskDates.at(9, 0, on: TaskDates.adding(7, days: TaskDates.monday(of: now, calendar), calendar), calendar)
        }
    }
}

// MARK: - Quick add

/// What quick add understood from a line like "Call Tom tomorrow 3pm #work @Website !!".
struct TaskParse: Equatable, Sendable {
    var title: String
    var due: Date?
    var dueHasTime = false
    var start: Date?
    var recurrence: Recurrence?
    var priority: TaskPriority = .none
    var tags: [String] = []
    /// The words after @, to match against your projects.
    var project: String?
    var someday = false
    /// Shown under the field: "Tomorrow, 3 pm", "Every week", "#work".
    var understood: [String] = []
}

/// Natural-language quick add. Words in "double quotes" are left alone.
enum TaskParser {
    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static let monthShort = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]
    private static let dayFull = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let dayShort = ["sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7]
    private static let numberWords = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let datePrefixes: Set<String> = ["on", "by", "due", "this", "next", "start", "starting", "from", "until", "before"]

    static func parse(_ text: String, now: Date, calendar: Calendar, dayFirst: Bool = true) -> TaskParse {
        let raw = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        var words: [String] = []
        var quoted: [Bool] = []
        var inQuote = false
        for token in raw {
            let opens = token.hasPrefix("\"") || token.hasPrefix("“")
            let closes = token.count > 1 && (token.hasSuffix("\"") || token.hasSuffix("”"))
            if opens { inQuote = true }
            quoted.append(inQuote)
            if closes || (opens && token.count > 1 && (token.dropFirst().hasSuffix("\"") || token.dropFirst().hasSuffix("”"))) { inQuote = false }
            words.append(token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:()!\"“”")))
        }
        var used = Array(repeating: false, count: raw.count)
        var titleTokens = raw

        var result = TaskParse(title: "")
        var day: Date?
        var time: (Int, Int)?
        var exact: Date?
        var startDay: Date?

        func word(_ i: Int) -> String { i < words.count && !quoted[i] && !used[i] ? words[i] : "" }
        func take(_ range: Range<Int>) {
            for i in range { used[i] = true }
        }

        var i = 0
        while i < raw.count {
            if quoted[i] || used[i] { i += 1; continue }
            let w = words[i]
            let original = raw[i]

            // Priority: "!", "!!", "!!!", "p1"–"p3", or "!!" stuck on the end of a word.
            if let level = priority(original.lowercased()) {
                result.priority = max(result.priority, level)
                used[i] = true
                i += 1
                continue
            }
            if original.count > 2, original.hasSuffix("!!") {
                let bangs = original.reversed().prefix { $0 == "!" }.count
                if bangs <= 3 {
                    result.priority = max(result.priority, TaskPriority(rawValue: bangs) ?? .high)
                    titleTokens[i] = String(original.dropLast(bangs))
                }
            }

            // #tag and @project.
            if original.hasPrefix("#"), original.count > 1, original.dropFirst().first?.isLetter == true {
                let tag = String(original.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
                if !result.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { result.tags.append(tag) }
                used[i] = true
                i += 1
                continue
            }
            if original.hasPrefix("@"), original.count > 1, original.dropFirst().first?.isLetter == true {
                result.project = String(original.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
                    .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                used[i] = true
                i += 1
                continue
            }
            if w == "someday" || w == "sometime" {
                result.someday = true
                used[i] = true
                i += 1
                continue
            }

            // Repeats.
            if let (rule, length) = recurrence(at: i, word: word) {
                result.recurrence = rule
                for j in i..<(i + length) { used[j] = true }
                i += length
                continue
            }

            // A start date: "start Monday", "from 3 March".
            if (w == "start" || w == "starting" || w == "from"), let (date, length) = dayPhrase(at: i + 1, word: word, now: now, calendar: calendar, dayFirst: dayFirst, prefixed: true) {
                startDay = date
                take(i..<(i + 1 + length))
                i += 1 + length
                continue
            }

            // "in 3 days", "in 2 hours".
            if w == "in", let (amount, unit, length) = duration(at: i + 1, word: word) {
                switch unit {
                case "minute": exact = now.addingTimeInterval(Double(amount) * 60)
                case "hour": exact = now.addingTimeInterval(Double(amount) * 3_600)
                case "day": day = TaskDates.adding(amount, days: calendar.startOfDay(for: now), calendar)
                case "week": day = TaskDates.adding(7 * amount, days: calendar.startOfDay(for: now), calendar)
                case "month": day = calendar.date(byAdding: .month, value: amount, to: calendar.startOfDay(for: now))
                default: day = calendar.date(byAdding: .year, value: amount, to: calendar.startOfDay(for: now))
                }
                take(i..<(i + 1 + length))
                i += 1 + length
                continue
            }

            // A day, with an optional "on", "by" or "due" before it.
            let prefixed = w == "on" || w == "by" || w == "due" || w == "before"
            if prefixed, let (date, length) = dayPhrase(at: i + 1, word: word, now: now, calendar: calendar, dayFirst: dayFirst, prefixed: true) {
                day = date
                take(i..<(i + 1 + length))
                i += 1 + length
                if let (part, partLength) = partOfDay(at: i, word: word) { time = time ?? part; take(i..<(i + partLength)); i += partLength }
                continue
            }
            if let (date, length) = dayPhrase(at: i, word: word, now: now, calendar: calendar, dayFirst: dayFirst, prefixed: false) {
                day = date
                take(i..<(i + length))
                i += length
                if let (part, partLength) = partOfDay(at: i, word: word) { time = time ?? part; take(i..<(i + partLength)); i += partLength }
                continue
            }
            if w == "tonight" {
                day = calendar.startOfDay(for: now)
                time = time ?? (18, 0)
                take(i..<(i + 1))
                i += 1
                continue
            }

            // A time: "at 3pm", "3:30 pm", "15:00", "at 9", "noon".
            if let (clock, length) = timePhrase(at: i, word: word) {
                time = clock
                take(i..<(i + length))
                i += length
                continue
            }
            i += 1
        }

        // A repeat with no date starts at its first day, at the time given if there is one.
        if exact == nil, day == nil, startDay == nil, let rule = result.recurrence {
            var first = firstOccurrence(of: rule, now: now, calendar: calendar)
            if let time, TaskDates.at(time.0, time.1, on: first, calendar) <= now { first = rule.next(after: first, calendar: calendar) }
            day = first
        }

        // Put the date together.
        if let exact {
            result.due = exact
            result.dueHasTime = true
        } else if let day {
            if let time {
                result.due = TaskDates.at(time.0, time.1, on: day, calendar)
                result.dueHasTime = true
            } else {
                result.due = calendar.startOfDay(for: day)
            }
        } else if let time {
            // A time alone means the next one: today if it's still ahead, otherwise tomorrow.
            var date = TaskDates.at(time.0, time.1, on: now, calendar)
            if date <= now { date = TaskDates.at(time.0, time.1, on: TaskDates.adding(1, days: now, calendar), calendar) }
            result.due = date
            result.dueHasTime = true
        }
        result.start = startDay
        if result.due != nil || result.start != nil { result.someday = false }

        // What's left is the title.
        var title = zip(titleTokens, used).filter { !$0.1 }.map(\.0).joined(separator: " ")
        title = title.replacingOccurrences(of: #"\s+(on|at|by|due|from|in|for)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",-–")))
        if let first = title.first, first.isLowercase { title = first.uppercased() + title.dropFirst() }
        result.title = title

        // What to show under the field.
        if let due = result.due { result.understood.append(TaskDates.label(due, hasTime: result.dueHasTime, now: now, calendar: calendar)) }
        if let start = result.start {
            let label = TaskDates.label(start, hasTime: false, now: now, calendar: calendar)
            result.understood.append("Starts " + (label == "Today" || label == "Tomorrow" ? label.lowercased() : label))
        }
        if let rule = result.recurrence { result.understood.append(rule.text) }
        if result.someday { result.understood.append("Someday") }
        if result.priority != TaskPriority.none { result.understood.append(result.priority.marks + " " + result.priority.title.lowercased()) }
        result.understood += result.tags.map { "#" + $0 }
        if let project = result.project { result.understood.append("@" + project) }
        return result
    }

    private static func priority(_ w: String) -> TaskPriority? {
        switch w {
        case "!", "p3": return .low
        case "!!", "p2": return .medium
        case "!!!", "p1": return .high
        default: return nil
        }
    }

    private static func number(_ w: String) -> Int? {
        if let value = Int(w) { return value }
        return numberWords[w]
    }

    /// "3 days", "a week", "two hours" (after "in").
    private static func duration(at i: Int, word: (Int) -> String) -> (Int, String, Int)? {
        guard let amount = number(word(i)) else { return nil }
        let unit = word(i + 1)
        let units: [(String, [String])] = [
            ("minute", ["minute", "minutes", "min", "mins"]), ("hour", ["hour", "hours", "hr", "hrs"]),
            ("day", ["day", "days"]), ("week", ["week", "weeks"]), ("fortnight", ["fortnight", "fortnights"]),
            ("month", ["month", "months"]), ("year", ["year", "years"]),
        ]
        guard let match = units.first(where: { $0.1.contains(unit) }) else { return nil }
        if match.0 == "fortnight" { return (amount * 2, "week", 2) }
        return (amount, match.0, 2)
    }

    /// A day named any way people write one. Short day names only count after a prefix like "on" or "next",
    /// so "sun cream" stays a title.
    private static func dayPhrase(at i: Int, word: (Int) -> String, now: Date, calendar: Calendar, dayFirst: Bool, prefixed: Bool) -> (Date, Int)? {
        let today = calendar.startOfDay(for: now)
        let w = word(i)
        guard !w.isEmpty else { return nil }
        switch w {
        case "today": return (today, 1)
        case "tomorrow", "tmrw", "tmr", "tomorow": return (TaskDates.adding(1, days: today, calendar), 1)
        case "weekend": return (weekend(now: now, calendar: calendar, next: false), 1)
        case "eod": return (today, 1)
        case "eow": return (TaskDates.adding(4, days: TaskDates.monday(of: now, calendar), calendar), 1)
        case "eom": return (endOfMonth(now, calendar), 1)
        default: break
        }
        if w == "end", word(i + 1) == "of" {
            switch word(i + 2) {
            case "day": return (today, 3)
            case "week": return (TaskDates.adding(4, days: TaskDates.monday(of: now, calendar), calendar), 3)
            case "month": return (endOfMonth(now, calendar), 3)
            default: return nil
            }
        }
        if w == "this" || w == "next" {
            let next = w == "next"
            let after = word(i + 1)
            if let weekday = dayFull[after] ?? dayShort[after] {
                if next {
                    let monday = TaskDates.adding(7, days: TaskDates.monday(of: now, calendar), calendar)
                    return (TaskDates.adding(TaskDates.mondayFirst(weekday), days: monday, calendar), 2)
                }
                return (TaskDates.next(weekday: weekday, from: now, includeToday: true, calendar), 2)
            }
            switch after {
            case "week": return (next ? TaskDates.adding(7, days: TaskDates.monday(of: now, calendar), calendar) : today, 2)
            case "weekend": return (weekend(now: now, calendar: calendar, next: next), 2)
            case "month":
                guard next else { return nil }
                let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
                return (calendar.date(byAdding: .month, value: 1, to: first) ?? today, 2)
            case "year":
                guard next else { return nil }
                let year = calendar.component(.year, from: now) + 1
                return (calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today, 2)
            case "morning", "afternoon", "evening":
                return next ? nil : (today, 1)
            default: return nil
            }
        }
        if let weekday = dayFull[w] ?? (prefixed ? dayShort[w] : nil) {
            return (TaskDates.next(weekday: weekday, from: now, includeToday: true, calendar), 1)
        }
        // "12 March", "12th Mar", "March 12", "Mar 12th", with an optional year.
        if let dayNumber = ordinal(w), let month = monthNumber(word(i + 1)) {
            let (year, extra) = yearAfter(i + 2, word: word)
            return absolute(day: dayNumber, month: month, year: year, now: now, calendar: calendar).map { ($0, 2 + extra) }
        }
        if let month = monthNumber(w), (prefixed || months.contains(w) || w.count >= 3), let dayNumber = ordinal(word(i + 1)) {
            let (year, extra) = yearAfter(i + 2, word: word)
            return absolute(day: dayNumber, month: month, year: year, now: now, calendar: calendar).map { ($0, 2 + extra) }
        }
        // 12/3, 12/03/2027, 2026-12-03.
        let iso = w.split(separator: "-").compactMap { Int($0) }
        if iso.count == 3, iso[0] > 1900, w.count == 10 {
            return calendar.date(from: DateComponents(year: iso[0], month: iso[1], day: iso[2])).map { ($0, 1) }
        }
        let parts = w.split(separator: "/").compactMap { Int($0) }
        if parts.count >= 2, parts.count <= 3, w.split(separator: "/").count == parts.count {
            let dayNumber = dayFirst ? parts[0] : parts[1]
            let month = dayFirst ? parts[1] : parts[0]
            var year: Int?
            if parts.count == 3 { year = parts[2] < 100 ? 2000 + parts[2] : parts[2] }
            return absolute(day: dayNumber, month: month, year: year, now: now, calendar: calendar).map { ($0, 1) }
        }
        return nil
    }

    private static func ordinal(_ w: String) -> Int? {
        var digits = w
        for suffix in ["st", "nd", "rd", "th"] where digits.hasSuffix(suffix) { digits = String(digits.dropLast(2)) }
        guard let value = Int(digits), (1...31).contains(value) else { return nil }
        return value
    }

    private static func monthNumber(_ w: String) -> Int? {
        if let index = months.firstIndex(of: w) { return index + 1 }
        return monthShort[w]
    }

    private static func yearAfter(_ i: Int, word: (Int) -> String) -> (Int?, Int) {
        if let year = Int(word(i)), (2000...2200).contains(year) { return (year, 1) }
        return (nil, 0)
    }

    /// A date this year, or next year if it's already gone.
    private static func absolute(day: Int, month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let thisYear = calendar.component(.year, from: now)
        let parts = DateComponents(year: year ?? thisYear, month: month, day: day)
        guard parts.isValidDate(in: calendar), var date = calendar.date(from: parts) else { return nil }
        if year == nil, date < calendar.startOfDay(for: now) {
            date = calendar.date(from: DateComponents(year: thisYear + 1, month: month, day: day)) ?? date
        }
        return date
    }

    private static func weekend(now: Date, calendar: Calendar, next: Bool) -> Date {
        let weekday = calendar.component(.weekday, from: now)
        let today = calendar.startOfDay(for: now)
        if !next && (weekday == 7 || weekday == 1) { return today }
        let saturday = TaskDates.adding(5, days: TaskDates.monday(of: now, calendar), calendar)
        return next ? TaskDates.adding(7, days: saturday, calendar) : saturday
    }

    private static func endOfMonth(_ now: Date, _ calendar: Calendar) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let nextFirst = calendar.date(byAdding: .month, value: 1, to: first) ?? first
        return TaskDates.adding(-1, days: nextFirst, calendar)
    }

    /// "morning" after a day: 9 am; "afternoon": 2 pm; "evening" or "night": 6 pm.
    private static func partOfDay(at i: Int, word: (Int) -> String) -> ((Int, Int), Int)? {
        switch word(i) {
        case "morning": return ((9, 0), 1)
        case "afternoon": return ((14, 0), 1)
        case "evening", "night": return ((18, 0), 1)
        default: return nil
        }
    }

    private static func timePhrase(at i: Int, word: (Int) -> String) -> ((Int, Int), Int)? {
        var index = i
        let hasAt = word(i) == "at" || word(i) == "@"
        if hasAt { index += 1 }
        let w = word(index)
        guard !w.isEmpty else { return nil }
        if w == "noon" || w == "midday" { return ((12, 0), index - i + 1) }
        if w == "midnight" { return ((23, 59), index - i + 1) }
        // "3pm", "3:30pm", "3.30pm", "3 pm".
        var body = w
        var suffix = ""
        for candidate in ["am", "pm", "a.m", "p.m", "a.m.", "p.m."] where body.hasSuffix(candidate) {
            suffix = candidate.hasPrefix("a") ? "am" : "pm"
            body = String(body.dropLast(candidate.count))
        }
        var length = index - i + 1
        if suffix.isEmpty {
            let following = word(index + 1)
            if following == "am" || following == "pm" || following == "a.m" || following == "p.m" {
                suffix = following.hasPrefix("a") ? "am" : "pm"
                length += 1
            }
        }
        let pieces = body.split(whereSeparator: { $0 == ":" || ($0 == "." && !suffix.isEmpty) }).map(String.init)
        guard (1...2).contains(pieces.count), let hourValue = Int(pieces[0]), pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        let minute = pieces.count == 2 ? Int(pieces[1]) ?? 0 : 0
        guard (0...59).contains(minute) else { return nil }
        if !suffix.isEmpty {
            guard (1...12).contains(hourValue) else { return nil }
            var hour = hourValue % 12
            if suffix == "pm" { hour += 12 }
            return ((hour, minute), length)
        }
        // No am or pm: "15:00" is clear; "at 9" means 9 am, "at 3" or "5:30" means the afternoon. A bare number isn't a time.
        if pieces.count == 2, hourValue == 0 || (13...23).contains(hourValue) { return ((hourValue, minute), length) }
        guard hasAt || pieces.count == 2, (1...12).contains(hourValue) else { return nil }
        return ((hourValue <= 6 ? hourValue + 12 : hourValue == 12 ? 12 : hourValue, minute), length)
    }

    /// "every day", "every weekday", "every 2 weeks", "every Mon and Thu", "weekly", "fortnightly".
    private static func recurrence(at i: Int, word: (Int) -> String) -> (Recurrence, Int)? {
        switch word(i) {
        case "daily": return (Recurrence(unit: .day), 1)
        case "weekly": return (Recurrence(unit: .week), 1)
        case "fortnightly": return (Recurrence(unit: .week, every: 2), 1)
        case "monthly": return (Recurrence(unit: .month), 1)
        case "yearly", "annually": return (Recurrence(unit: .year), 1)
        case "every", "each": break
        default: return nil
        }
        var index = i + 1
        var every = 1
        if word(index) == "other" {
            every = 2
            index += 1
        } else if let n = Int(word(index)), n > 0, n < 400 {
            every = n
            index += 1
        }
        let unitWord = word(index)
        let units: [String: Recurrence.Unit] = [
            "day": .day, "days": .day, "weekday": .weekday, "weekdays": .weekday, "week": .week, "weeks": .week,
            "month": .month, "months": .month, "year": .year, "years": .year,
        ]
        if unitWord == "fortnight" { return (Recurrence(unit: .week, every: 2), index - i + 1) }
        if let unit = units[unitWord] {
            var rule = Recurrence(unit: unit, every: unit == .weekday ? 1 : every)
            var length = index - i + 1
            if unit == .week, word(index + 1) == "on" {
                let (days, used) = weekdayList(at: index + 2, word: word)
                if !days.isEmpty {
                    rule.weekdays = days
                    length += 1 + used
                }
            }
            return (rule, length)
        }
        let (days, used) = weekdayList(at: index, word: word)
        guard !days.isEmpty else { return nil }
        return (Recurrence(unit: .week, every: every, weekdays: days), index - i + used)
    }

    /// "monday", "mon and thu", "mon, wed, fri", "tue/thu".
    private static func weekdayList(at i: Int, word: (Int) -> String) -> ([Int], Int) {
        var days: [Int] = []
        var index = i
        var used = 0
        while true {
            let w = word(index)
            let pieces = w.split(separator: "/").map(String.init)
            let found = pieces.compactMap { dayFull[$0] ?? dayShort[$0] ?? dayFull[String($0.dropLast())] }
            if !found.isEmpty, found.count == pieces.count {
                days += found
                index += 1
                used = index - i
                if word(index) == "and" || word(index) == "&" { index += 1; continue }
                if !word(index).isEmpty, dayFull[word(index)] != nil || dayShort[word(index)] != nil { continue }
                break
            }
            break
        }
        var unique: [Int] = []
        for day in days where !unique.contains(day) { unique.append(day) }
        return (unique, used)
    }

    /// The first date a new repeating task is due: today, or the next matching weekday.
    static func firstOccurrence(of rule: Recurrence, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch rule.unit {
        case .weekday:
            return calendar.isDateInWeekend(today) ? rule.next(after: today, calendar: calendar) : today
        case .week where !rule.weekdays.isEmpty:
            return rule.weekdays.map { TaskDates.next(weekday: $0, from: now, includeToday: true, calendar) }.min() ?? today
        default:
            return today
        }
    }
}

// MARK: - Promises in your sent mail

/// Something you said you'd do, found in a message you sent.
struct MailPromise: Equatable, Sendable {
    var title: String
    var due: Date?
    var dueHasTime: Bool
    var quote: String
}

/// Marc reads what you send for "I'll…" and "I will…" and turns each into a task for you.
enum PromiseFinder {
    private static let openers = ["i'll ", "i’ll ", "i will ", "i'm going to ", "i’m going to ", "i am going to ", "let me ", "i promise to ", "i can get ", "i'll make sure ", "i’ll make sure "]
    private static let skip = ["i'll be ", "i’ll be ", "i will be ", "let me know", "i'll see ", "i’ll see ", "i'll leave it", "i’ll leave it", "i will leave it", "let me think"]

    static func promises(in body: String, to recipient: String, sent: Date, calendar: Calendar) -> [MailPromise] {
        let name = firstName(recipient)
        var found: [MailPromise] = []
        for sentence in sentences(in: ownWords(body)) {
            let lower = sentence.lowercased()
            guard !sentence.hasSuffix("?"), sentence.count <= 220 else { continue }
            guard let opener = openers.compactMap({ opener -> Range<String.Index>? in
                guard let range = lower.range(of: opener) else { return nil }
                // At the start, or after "and", "so" or a comma.
                let before = lower[lower.startIndex..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                guard before.isEmpty || before.hasSuffix(",") || before.hasSuffix(" and") || before == "and" || before == "so" || before.hasSuffix(" so") || before == "ok," || before == "sure," || before == "thanks," else { return nil }
                return range
            }).min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
            let tail = String(lower[opener.lowerBound...])
            if skip.contains(where: { tail.hasPrefix($0) }) { continue }
            let offset = min(lower.distance(from: lower.startIndex, to: opener.upperBound), sentence.count)
            let action = String(sentence[sentence.index(sentence.startIndex, offsetBy: offset)...]).trimmingCharacters(in: .whitespaces)
            guard action.split(separator: " ").count >= 2 else { continue }
            let parsed = TaskParser.parse(action, now: sent, calendar: calendar)
            var title = parsed.title
            if let name {
                title = title.replacingOccurrences(of: #"\byour\b"#, with: "\(name)'s", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"\byou\b"#, with: name, options: [.regularExpression, .caseInsensitive])
            }
            title = title.replacingOccurrences(of: #"\b(asap|soon|shortly)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.!")))
            guard title.count >= 4 else { continue }
            title = title.prefix(1).uppercased() + title.dropFirst()
            found.append(MailPromise(title: title, due: parsed.due, dueHasTime: parsed.dueHasTime, quote: sentence))
            if found.count == 3 { break }
        }
        return found
    }

    /// Drops the quoted message you replied to and your signature.
    static func ownWords(_ body: String) -> String {
        var kept: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") { continue }
            if trimmed == "--" || trimmed == "-- " || trimmed.hasPrefix("-----Original Message") || trimmed.hasPrefix("From: ") { break }
            if trimmed.hasPrefix("On "), trimmed.hasSuffix("wrote:") { break }
            if trimmed.hasPrefix("Sent from my") { break }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character == "\n" {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
                current = ""
                continue
            }
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                // Not "3.30pm" or "e.g.".
                if next == " " || next == "\n" {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
        return result
    }

    /// "Tom Baker <tom@example.com>" → "Tom"; "tom.baker@example.com" → "Tom".
    static func firstName(_ recipient: String) -> String? {
        var text = recipient
        if let angle = text.firstIndex(of: "<") { text = String(text[..<angle]) }
        text = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
        if text.isEmpty || text.contains("@") {
            let local = (text.isEmpty ? recipient : text).trimmingCharacters(in: CharacterSet(charactersIn: "<> ")).split(separator: "@").first.map(String.init) ?? ""
            let first = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" }).first.map(String.init) ?? ""
            guard first.count > 1, first.allSatisfy(\.isLetter) else { return nil }
            return first.prefix(1).uppercased() + first.dropFirst().lowercased()
        }
        if text.contains(",") { text = text.split(separator: ",").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? text }
        return text.split(separator: " ").first.map(String.init)
    }
}

// MARK: - Syncing with Apple Reminders

/// A reminder as read from Reminders, without EventKit, so the merge rules can be tested.
struct ReminderSnapshot: Equatable, Sendable {
    var id: String
    var listID: String
    var title: String
    var notes: String
    var due: Date?
    var dueHasTime: Bool
    var priority: TaskPriority
    var completed: Date?
    var modified: Date?

    /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
    static func priority(fromEventKit value: Int) -> TaskPriority {
        switch value {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return TaskPriority.none
        }
    }

    static func eventKitPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }
}

enum ReminderSync {
    struct Plan: Equatable {
        /// Tasks to replace with what's in Reminders, because Reminders has the newer change.
        var updateLocal: [TaskItem] = []
        /// Reminders 11am hasn't seen yet.
        var addLocal: [TaskItem] = []
        /// Linked tasks whose reminders were deleted.
        var removeLocal: [UUID] = []
        /// Tasks whose newer changes go to Reminders.
        var updateRemote: [TaskItem] = []
        /// Tasks to create in Reminders.
        var addRemote: [TaskItem] = []

        var isEmpty: Bool { updateLocal.isEmpty && addLocal.isEmpty && removeLocal.isEmpty && updateRemote.isEmpty && addRemote.isEmpty }
    }

    /// - Parameters:
    ///   - reminders: open reminders in the synced lists, plus any linked ones looked up by ID.
    ///   - missing: linked reminder IDs that no longer exist.
    ///   - defaultListID: the list the Inbox syncs with.
    static func plan(tasks: [TaskItem], projects: [TaskProject], reminders: [ReminderSnapshot], missing: Set<String>, defaultListID: String, now: Date) -> Plan {
        var plan = Plan()
        let byID = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let projectForList = Dictionary(projects.compactMap { project in project.reminderListID.map { ($0, project.id) } }, uniquingKeysWith: { a, _ in a })
        var linked = Set<String>()

        for task in tasks {
            guard let reminderID = task.reminderID else {
                if !task.isDone { plan.addRemote.append(task) }
                continue
            }
            linked.insert(reminderID)
            if missing.contains(reminderID) {
                plan.removeLocal.append(task.id)
                continue
            }
            guard let reminder = byID[reminderID], differs(task, reminder) else { continue }
            if let changed = reminder.modified, changed > task.modified {
                plan.updateLocal.append(merged(task, with: reminder, now: now))
            } else {
                plan.updateRemote.append(task)
            }
        }
        for reminder in reminders where !linked.contains(reminder.id) && reminder.completed == nil {
            var task = TaskItem(title: reminder.title.isEmpty ? "Reminder" : reminder.title)
            task = merged(task, with: reminder, now: now)
            task.reminderID = reminder.id
            task.projectID = reminder.listID == defaultListID ? nil : projectForList[reminder.listID]
            task.created = reminder.modified ?? now
            task.origin = TaskOrigin(kind: .reminders, monogram: "le", label: "From Reminders", reference: reminder.id)
            plan.addLocal.append(task)
        }
        return plan
    }

    static func differs(_ task: TaskItem, _ reminder: ReminderSnapshot) -> Bool {
        if task.title != reminder.title || task.notes != reminder.notes || task.priority != reminder.priority { return true }
        if task.isDone != (reminder.completed != nil) { return true }
        if task.dueHasTime != reminder.dueHasTime && (task.due != nil || reminder.due != nil) { return true }
        switch (task.due, reminder.due) {
        case (nil, nil): return false
        case (let a?, let b?): return abs(a.timeIntervalSince(b)) >= 60
        default: return true
        }
    }

    static func merged(_ task: TaskItem, with reminder: ReminderSnapshot, now: Date) -> TaskItem {
        var task = task
        task.title = reminder.title
        task.notes = reminder.notes
        task.due = reminder.due
        task.dueHasTime = reminder.due != nil && reminder.dueHasTime
        task.priority = reminder.priority
        if let completed = reminder.completed {
            if task.completed == nil {
                task.completed = completed
                task.status = .done
            }
        } else if task.completed != nil {
            task.completed = nil
            task.status = .todo
        }
        task.modified = reminder.modified ?? now
        return task
    }
}
