import SwiftUI
import EventKit

/// How the tasks in a list are laid out.
enum TaskLayout: String, CaseIterable, Identifiable {
    case list, board, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .board: return "Board"
        case .week: return "Week"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .board: return "rectangle.split.3x1"
        case .week: return "calendar"
        }
    }
}

struct TaskSettings: Codable {
    var syncReminders = false
    /// The Reminders list the Inbox syncs with.
    var defaultListID: String?
    var lastSync: Date?
    /// Marc turns "I'll…" in the mail you send into tasks.
    var findPromises = true
    /// The sample tasks, so they can be cleared in one go.
    var sampleIDs: [UUID] = []
    var sampleProjectIDs: [UUID] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syncReminders = try c.decodeIfPresent(Bool.self, forKey: .syncReminders) ?? false
        defaultListID = try c.decodeIfPresent(String.self, forKey: .defaultListID)
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        findPromises = try c.decodeIfPresent(Bool.self, forKey: .findPromises) ?? true
        sampleIDs = try c.decodeIfPresent([UUID].self, forKey: .sampleIDs) ?? []
        sampleProjectIDs = try c.decodeIfPresent([UUID].self, forKey: .sampleProjectIDs) ?? []
    }

    private enum CodingKeys: String, CodingKey { case syncReminders, defaultListID, lastSync, findPromises, sampleIDs, sampleProjectIDs }
}

/// Leo's Tasks: your own lists and projects, things the other agents noticed you need to do,
/// and Apple Reminders kept in step so Siri and your iPhone still work.
@MainActor
final class TasksModel: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var book = TaskBook()
    @Published var list: TaskListID = .today { didSet { if list != oldValue { selectedID = nil } } }
    @Published var layout: TaskLayout { didSet { UserDefaults.standard.set(layout.rawValue, forKey: "tasks.layout") } }
    @Published var selectedID: UUID?
    @Published private(set) var settings = TaskSettings()
    @Published var notice: String?
    @Published var canUndoDelete = false
    @Published private(set) var reminderAccess: Access = .unknown
    @Published private(set) var syncing = false
    /// Leo is splitting this task into steps.
    @Published private(set) var breakingDown: UUID?
    /// Asks the quick add field to take the keyboard (⌥⇧T from anywhere).
    @Published var wantsFocus = false
    /// Moves on at midnight so Today is today.
    @Published private(set) var now = Date()

    let brain: Brain
    /// Shows something in the activity feed: (monogram, text).
    var onLog: ((String, String) -> Void)?
    /// Opens where a task came from (an email, an event).
    var onOpenOrigin: ((TaskOrigin) -> Void)?
    /// Today, the brief and the iPhone want to know when tasks change.
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var clock: Timer?
    private var storeObserver: NSObjectProtocol?

    var calendar: Calendar { Calendar.current }

    /// 3/12 is 3 December unless you're in the US.
    var dayFirst: Bool { Locale.current.region?.identifier != "US" }

    init(brain: Brain) {
        self.brain = brain
        layout = UserDefaults.standard.string(forKey: "tasks.layout").flatMap(TaskLayout.init(rawValue:)) ?? .list
    }

    func load() {
        book = JSONStore.load(TaskBook.self, from: "tasks") ?? TaskBook()
        settings = JSONStore.load(TaskSettings.self, from: "tasks-settings") ?? TaskSettings()
        refreshAccess()
        clock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync(after: 2) }
        }
        if settings.syncReminders { scheduleSync(after: 1) }
    }

    private func tick() {
        let old = now
        now = Date()
        if !calendar.isDate(old, inSameDayAs: now) { onChange?() }
    }

    // MARK: Reading

    func tasks(in list: TaskListID) -> [TaskItem] { book.tasks(in: list, now: now, calendar: calendar) }
    func count(_ list: TaskListID) -> Int { book.count(list, now: now, calendar: calendar) }
    var selected: TaskItem? { selectedID.flatMap { book.task($0) } }
    var projects: [TaskProject] { book.projects.filter { !$0.archived } }
    func project(_ id: UUID?) -> TaskProject? { book.project(id) }
    func isOverdue(_ task: TaskItem) -> Bool { book.isOverdue(task, now: now, calendar: calendar) }
    var overdueCount: Int { tasks(in: .today).filter(isOverdue).count }

    func title(of list: TaskListID) -> String {
        switch list {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .someday: return "Someday"
        case .logbook: return "Logbook"
        case .project(let id): return book.project(id)?.name ?? "Project"
        case .tag(let tag): return "#" + tag
        }
    }

    func symbol(of list: TaskListID) -> String {
        switch list {
        case .inbox: return "tray"
        case .today: return "star"
        case .upcoming: return "calendar"
        case .someday: return "archivebox"
        case .logbook: return "checkmark.circle"
        case .project(let id): return book.project(id)?.symbol ?? "circle.dashed"
        case .tag: return "number"
        }
    }

    /// "Tomorrow, 3 pm" or "Overdue · Tuesday".
    func dueText(_ task: TaskItem) -> String? {
        guard let due = task.due else { return nil }
        let label = TaskDates.label(due, hasTime: task.dueHasTime, now: now, calendar: calendar)
        return isOverdue(task) ? "Overdue · " + label : label
    }

    /// What Leo puts in the brief.
    var briefFacts: String {
        let today = tasks(in: .today)
        guard !today.isEmpty else { return "" }
        let overdue = today.filter(isOverdue).count
        let names = today.prefix(6).map { task in task.title + (task.priority == .high ? " (important)" : "") }
        return "Tasks today: \(today.count)\(overdue > 0 ? ", \(overdue) overdue" : ""). " + names.joined(separator: "; ") + "."
    }

    // MARK: Adding

    /// Quick add: the words become a task in the list you're looking at, unless they say otherwise.
    @discardableResult
    func add(_ text: String, in list: TaskListID? = nil, origin: TaskOrigin? = nil, select: Bool = true) -> TaskItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = TaskParser.parse(trimmed, now: Date(), calendar: calendar, dayFirst: dayFirst)
        var task = TaskItem(title: parsed.title.isEmpty ? trimmed : parsed.title)
        task.due = parsed.due
        task.dueHasTime = parsed.dueHasTime
        task.start = parsed.start
        task.recurrence = parsed.recurrence
        task.priority = parsed.priority
        task.tags = parsed.tags
        task.someday = parsed.someday
        task.origin = origin
        if let name = parsed.project {
            if let match = matchProject(name) {
                task.projectID = match.id
            } else {
                notice = "No project called \(name), so it's in the Inbox."
            }
        }
        // Where you added it says something too.
        switch list ?? self.list {
        case .project(let id) where task.projectID == nil:
            task.projectID = id
        case .today where task.due == nil && task.start == nil && !task.someday:
            task.due = calendar.startOfDay(for: Date())
        case .upcoming where task.due == nil && task.start == nil && !task.someday:
            task.due = TaskDates.adding(1, days: calendar.startOfDay(for: Date()), calendar)
        case .someday where task.due == nil && task.start == nil:
            task.someday = true
        case .tag(let tag) where !task.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }):
            task.tags.append(tag)
        default:
            break
        }
        let id = book.add(task)
        if select { selectedID = id }
        changed()
        return book.task(id)
    }

    func matchProject(_ name: String) -> TaskProject? {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "")
        let open = projects
        return open.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == key }
            ?? open.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(key) }
    }

    /// "Make a task" on an email: Marc files it with a link back to the message.
    func add(from message: MailMessage) {
        let origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Email from \(message.fromName) · \(message.subject)",
                                reference: message.id, quote: String(message.snippet.prefix(160)))
        var task = TaskItem(title: message.subject.isEmpty ? "Follow up with \(message.fromName)" : "Follow up: \(message.subject)")
        task.origin = origin
        let id = book.add(task)
        selectedID = id
        changed()
        notice = "Added to Tasks: \(task.title)."
        onLog?("mc", "Made a task from \(message.fromName)'s email: \(task.title).")
    }

    /// Marc reads what you send and keeps your promises for you.
    func noteSent(to recipients: [String], subject: String, body: String, date: Date = Date()) {
        guard settings.findPromises, let recipient = recipients.first else { return }
        let promises = PromiseFinder.promises(in: body, to: recipient, sent: date, calendar: calendar)
        let name = PromiseFinder.firstName(recipient) ?? recipient
        for promise in promises {
            // Not twice: the same promise in a follow-up email.
            guard !book.tasks.contains(where: { !$0.isDone && $0.title.caseInsensitiveCompare(promise.title) == .orderedSame }) else { continue }
            var task = TaskItem(title: promise.title)
            task.due = promise.due
            task.dueHasTime = promise.dueHasTime
            task.origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Your email to \(name) · \(subject)", reference: nil, quote: promise.quote)
            book.add(task)
            onLog?("mc", "You told \(name) \"\(promise.quote)\" I've added \(promise.title) to Tasks.")
        }
        if !promises.isEmpty {
            changed()
            notice = promises.count == 1 ? "Marc added a task from your email: \(promises[0].title)." : "Marc added \(promises.count) tasks from your email."
        }
    }

    // MARK: Waiting for replies

    /// "Nudge me if Priya hasn't replied by Thursday": a dated task that ticks itself off when she writes back.
    func remindIfNoReply(from address: String, name: String, subject: String, by date: Date) {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        var task = TaskItem(title: "Follow up with \(first)" + (subject.isEmpty ? "" : ": \(subject)"))
        task.due = date
        task.origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Waiting for \(first)'s reply · \(subject)",
                                 reference: ReplyWatch.reference(address: address, since: Date()))
        book.add(task)
        changed()
        notice = "Marc will nudge you \(TaskDates.inline(TaskDates.label(date, hasTime: false, now: Date(), calendar: calendar))) if \(first) hasn't replied, and tick it off if they do."
    }

    /// New mail arrived: anyone you were waiting on who has replied comes off the list.
    func checkReplies(_ messages: [(from: String, date: Date)]) {
        let answered = ReplyWatch.answered(book.tasks, messages: messages)
        guard !answered.isEmpty else { return }
        for item in answered {
            book.complete(item.id, now: item.date, calendar: calendar)
        }
        changed()
        notice = answered.count == 1 ? "They replied, so Leo ticked off the follow-up." : "\(answered.count) people replied, so Leo ticked off their follow-ups."
    }

    // MARK: Changing

    func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        book.update(id, now: Date(), change)
        changed()
    }

    func toggle(_ id: UUID) {
        guard let task = book.task(id) else { return }
        if task.isDone {
            book.reopen(id, now: Date())
        } else {
            let nextID = book.complete(id, now: Date(), calendar: calendar)
            if let upcoming = nextID.flatMap({ book.task($0) }) {
                notice = "Done. Next one: \(dueText(upcoming) ?? "no date")."
            }
            if selectedID == id, tasks(in: list).contains(where: { $0.id == id }) == false { selectedID = nil }
        }
        changed()
    }

    func setStatus(_ id: UUID, _ status: TaskStatus) {
        book.setStatus(id, status, now: Date(), calendar: calendar)
        changed()
    }

    func snooze(_ id: UUID, _ option: SnoozeOption) {
        guard let date = option.date(now: Date(), calendar: calendar) else { return }
        book.snooze(id, until: date, now: Date())
        notice = "Snoozed until \(TaskDates.inline(TaskDates.label(date, hasTime: true, now: Date(), calendar: calendar)))."
        if selectedID == id { selectedID = nil }
        changed()
    }

    /// Dropped on a day in the week view: due that day, keeping its time.
    func schedule(_ id: UUID, on day: Date) {
        update(id) { task in
            var due = calendar.startOfDay(for: day)
            if task.dueHasTime, let old = task.due {
                let parts = calendar.dateComponents([.hour, .minute], from: old)
                due = TaskDates.at(parts.hour ?? 9, parts.minute ?? 0, on: due, calendar)
            }
            task.due = due
            task.someday = false
            if let start = task.start, start > due { task.start = nil }
        }
    }

    func move(_ id: UUID, toProject projectID: UUID?, section: UUID? = nil) {
        update(id) { task in
            task.projectID = projectID
            task.sectionID = section
        }
    }

    func reorder(_ id: UUID, before target: UUID?) {
        guard id != target else { return }
        book.move(id, before: target, among: tasks(in: list), now: Date())
        changed()
    }

    func delete(_ id: UUID) {
        guard let task = book.task(id) else { return }
        book.remove(id)
        if selectedID == id { selectedID = nil }
        if settings.syncReminders, let reminderID = task.reminderID,
           let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
        canUndoDelete = true
        notice = "Deleted \(task.title)."
        changed()
    }

    func undoDelete() {
        guard let id = book.undoRemove() else { return }
        // It comes back as a new reminder if it was synced.
        book.update(id, now: Date()) { $0.reminderID = nil }
        selectedID = id
        canUndoDelete = !book.removed.isEmpty
        notice = nil
        changed()
    }

    // MARK: Checklists

    func addStep(_ title: String, to id: UUID) {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        update(id) { $0.checklist.append(ChecklistItem(title: text)) }
    }

    func toggleStep(_ step: UUID, in id: UUID) {
        update(id) { task in
            if let index = task.checklist.firstIndex(where: { $0.id == step }) { task.checklist[index].done.toggle() }
        }
    }

    func removeStep(_ step: UUID, in id: UUID) {
        update(id) { $0.checklist.removeAll { $0.id == step } }
    }

    /// Leo splits a task into a few concrete steps.
    func breakDown(_ id: UUID) {
        guard let task = book.task(id), breakingDown == nil else { return }
        let project = book.project(task.projectID)?.name
        let request = BrainRequest(
            system: "You are Leo, a calm chief of staff. Break the task into 3 to 7 short, concrete steps someone can tick off. One step per line, no numbering, no bullets, no commentary. Each step starts with a verb.",
            prompt: "Task: \(task.title)" + (task.notes.isEmpty ? "" : "\nNotes: \(task.notes)") + (project.map { "\nProject: \($0)" } ?? ""),
            weight: .quick)
        let run = brain.run(request)
        breakingDown = id
        Task {
            await run.finished()
            defer { breakingDown = nil }
            guard case .done = run.status else {
                notice = "Leo couldn't break it down: \(run.status.failureText)."
                return
            }
            let steps = TasksModel.steps(from: run.text)
            guard !steps.isEmpty else {
                notice = "Leo didn't come back with steps. Try again."
                return
            }
            update(id) { task in task.checklist += steps.map { ChecklistItem(title: $0) } }
            notice = "Leo added \(steps.count) steps."
        }
    }

    nonisolated static func steps(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: #"^([-*•]|\d+[.)])\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty && $0.count < 140 && !$0.hasSuffix(":") }
            .prefix(10)
            .map { $0 }
    }

    // MARK: Projects

    @discardableResult
    func addProject(_ name: String) -> UUID? {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var project = TaskProject(name: text)
        project.symbol = ["circle.dashed", "shippingbox", "house", "briefcase", "leaf", "airplane", "hammer", "book"].randomElement() ?? "circle.dashed"
        book.projects.append(project)
        list = .project(project.id)
        changed()
        if settings.syncReminders { scheduleSync(after: 0.5) }
        return project.id
    }

    func updateProject(_ id: UUID, _ change: (inout TaskProject) -> Void) {
        guard let index = book.projects.firstIndex(where: { $0.id == id }) else { return }
        change(&book.projects[index])
        changed()
    }

    func addSection(_ name: String, to id: UUID) {
        let text = name.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        updateProject(id) { $0.sections.append(TaskSection(name: text)) }
    }

    func deleteProject(_ id: UUID) {
        book.removeProject(id)
        if list == .project(id) { list = .inbox }
        changed()
    }

    // MARK: Samples

    /// A believable week of tasks, for screenshots and for trying it out.
    func loadSample() {
        if hasSample { clearSample() }
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        func day(_ offset: Int, _ hour: Int? = nil) -> Date {
            let base = TaskDates.adding(offset, days: today, cal)
            return hour.map { TaskDates.at($0, 0, on: base, cal) } ?? base
        }
        var website = TaskProject(name: "Website relaunch", symbol: "globe")
        website.sections = [TaskSection(name: "Design"), TaskSection(name: "Build"), TaskSection(name: "Launch")]
        website.deadline = day(18)
        var house = TaskProject(name: "House", symbol: "house")
        house.sections = [TaskSection(name: "This month")]
        let tax = TaskProject(name: "Tax time", symbol: "doc.text")
        var sample = TaskBook(projects: [website, house, tax])

        func add(_ title: String, _ change: (inout TaskItem) -> Void = { _ in }) {
            var task = TaskItem(title: title)
            change(&task)
            sample.add(task)
        }
        add("Send Tom the deck") {
            $0.due = day(1)
            $0.priority = .high
            $0.origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Your email to Tom Baker · Deck for Friday", quote: "I'll send you the deck by Friday.")
            $0.tags = ["work"]
        }
        add("Pay the electricity bill") { $0.due = day(-1); $0.tags = ["home"]; $0.projectID = house.id; $0.sectionID = house.sections[0].id }
        add("Call the accountant about the BAS") {
            $0.due = day(0, 15)
            $0.dueHasTime = true
            $0.projectID = tax.id
            $0.checklist = [ChecklistItem(title: "Find last quarter's figures", done: true), ChecklistItem(title: "List the questions"), ChecklistItem(title: "Book a time")]
        }
        add("Weekly review") { $0.due = day(0); $0.recurrence = Recurrence(unit: .week, weekdays: [Calendar.current.component(.weekday, from: today)]) }
        add("Reply to Priya about the venue") {
            $0.due = day(0)
            $0.origin = TaskOrigin(kind: .mail, monogram: "mc", label: "Email from Priya Shah · Venue options", quote: "Could you let me know which venue works by Thursday?")
        }
        add("Moodboard for the new homepage") { $0.projectID = website.id; $0.sectionID = website.sections[0].id; $0.status = .doing; $0.due = day(2) }
        add("Pick a typeface") { $0.projectID = website.id; $0.sectionID = website.sections[0].id; $0.status = .waiting; $0.notes = "Waiting on Robert's two options." }
        add("Write the About page") { $0.projectID = website.id; $0.sectionID = website.sections[1].id; $0.due = day(4); $0.tags = ["writing"] }
        add("Set up redirects") { $0.projectID = website.id; $0.sectionID = website.sections[1].id }
        add("Announce it in the newsletter") { $0.projectID = website.id; $0.sectionID = website.sections[2].id; $0.due = day(18) }
        add("Water the plants") { $0.due = day(2); $0.recurrence = Recurrence(unit: .day, every: 3, afterCompletion: true); $0.tags = ["home"] }
        add("Book the car service") { $0.due = day(5); $0.projectID = house.id; $0.sectionID = house.sections[0].id }
        add("Follow up on the Lune proposal") {
            $0.start = day(3, 9)
            $0.origin = TaskOrigin(kind: .meeting, monogram: "le", label: "From your meeting · Lune kickoff", quote: "Conner: send the revised numbers once Lune has seen the draft.")
        }
        add("Gather receipts") { $0.projectID = tax.id; $0.due = day(9) }
        add("Learn to make sourdough") { $0.someday = true }
        add("Plan a weekend in Hobart") { $0.someday = true; $0.tags = ["travel"] }
        add("Buy a birthday present for Mum") { $0.due = nil }
        add("Renew passport") { $0.notes = "Photos first." }
        add("Read the strategy draft") { $0.completed = Date().addingTimeInterval(-3_600); $0.status = .done }
        add("Book flights") { $0.completed = Date().addingTimeInterval(-86_400); $0.status = .done; $0.tags = ["travel"] }

        settings.sampleIDs = sample.tasks.map(\.id)
        settings.sampleProjectIDs = sample.projects.map(\.id)
        book.tasks += sample.tasks
        book.projects += sample.projects
        changed()
    }

    var hasSample: Bool { !settings.sampleIDs.isEmpty }

    func clearSample() {
        let ids = Set(settings.sampleIDs)
        book.tasks.removeAll { ids.contains($0.id) }
        for project in settings.sampleProjectIDs { book.removeProject(project) }
        settings.sampleIDs = []
        settings.sampleProjectIDs = []
        selectedID = nil
        changed()
    }

    func setFindPromises(_ on: Bool) {
        settings.findPromises = on
        saveSettings()
    }

    // MARK: Saving

    private func changed() {
        objectWillChange.send()
        scheduleSave()
        onChange?()
        if settings.syncReminders { scheduleSync(after: 3) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.flushSave()
        }
    }

    func flushSave() {
        saveTask?.cancel()
        JSONStore.save(book, to: "tasks")
        saveSettings()
    }

    private func saveSettings() {
        JSONStore.save(settings, to: "tasks-settings")
    }

    // MARK: Apple Reminders

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: reminderAccess = .granted
        case .notDetermined: reminderAccess = .unknown
        default: reminderAccess = .denied
        }
    }

    /// Turns on two-way sync: the Inbox with your default Reminders list, each project with a list of its name.
    func enableSync() async {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        refreshAccess()
        guard granted else {
            notice = "11am needs access to Reminders. Allow it in System Settings › Privacy & Security › Reminders."
            return
        }
        guard let inbox = store.defaultCalendarForNewReminders() else {
            notice = "Reminders has no default list. Open Reminders once, then try again."
            return
        }
        settings.defaultListID = inbox.calendarIdentifier
        settings.syncReminders = true
        // Your other Reminders lists become projects, so everything you tell Siri shows up here.
        for list in store.calendars(for: .reminder) where list.calendarIdentifier != inbox.calendarIdentifier {
            if let index = book.projects.firstIndex(where: { $0.reminderListID == nil && $0.name.caseInsensitiveCompare(list.title) == .orderedSame }) {
                book.projects[index].reminderListID = list.calendarIdentifier
            } else if !book.projects.contains(where: { $0.reminderListID == list.calendarIdentifier }) {
                var project = TaskProject(name: list.title)
                project.symbol = "list.bullet"
                project.reminderListID = list.calendarIdentifier
                book.projects.append(project)
            }
        }
        saveSettings()
        await sync()
        onLog?("le", "Tasks and Reminders are in step. Siri and your iPhone add straight to 11am.")
    }

    func disableSync() {
        settings.syncReminders = false
        saveSettings()
        notice = "Sync with Reminders is off. Your tasks stay here, and your reminders stay in Reminders."
    }

    func scheduleSync(after seconds: Double) {
        guard settings.syncReminders else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard settings.syncReminders, reminderAccess == .granted || EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let defaultID = settings.defaultListID, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let allLists = store.calendars(for: .reminder)
        guard let inbox = allLists.first(where: { $0.calendarIdentifier == defaultID }) ?? store.defaultCalendarForNewReminders() else { return }
        settings.defaultListID = inbox.calendarIdentifier

        // Projects made in 11am get a list of their own in Reminders.
        for index in book.projects.indices where book.projects[index].reminderListID == nil && !book.projects[index].archived {
            let list = EKCalendar(for: .reminder, eventStore: store)
            list.title = book.projects[index].name
            list.source = inbox.source
            if (try? store.saveCalendar(list, commit: true)) != nil {
                book.projects[index].reminderListID = list.calendarIdentifier
            }
        }
        let listIDs = Set([inbox.calendarIdentifier] + book.projects.compactMap(\.reminderListID))
        let lists = store.calendars(for: .reminder).filter { listIDs.contains($0.calendarIdentifier) }

        let open = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists))
        let since = (settings.lastSync ?? Date()).addingTimeInterval(-86_400 * 2)
        let done = await fetch(store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: nil, calendars: lists))
        var items: [String: EKReminder] = [:]
        for reminder in open + done { items[reminder.calendarItemIdentifier] = reminder }
        var missing = Set<String>()
        for task in book.tasks {
            guard let id = task.reminderID, items[id] == nil else { continue }
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                items[id] = reminder
            } else {
                missing.insert(id)
            }
        }
        let snapshots = items.values.map(snapshot)
        let plan = ReminderSync.plan(tasks: book.tasks, projects: book.projects, reminders: snapshots, missing: missing,
                                     defaultListID: inbox.calendarIdentifier, now: Date())
        guard !plan.isEmpty else {
            settings.lastSync = Date()
            saveSettings()
            return
        }

        // Theirs, here.
        for incoming in plan.updateLocal {
            guard let current = book.task(incoming.id) else { continue }
            if !current.isDone, incoming.isDone, current.recurrence != nil {
                book.update(incoming.id, now: Date()) { task in
                    task.title = incoming.title
                    task.notes = incoming.notes
                }
                book.complete(incoming.id, now: incoming.completed ?? Date(), calendar: calendar)
            } else {
                book.update(incoming.id, now: incoming.modified) { $0 = incoming }
            }
        }
        for task in plan.addLocal { book.add(task) }
        for id in plan.removeLocal { book.remove(id) }

        // Ours, there.
        for task in plan.updateRemote {
            guard let id = task.reminderID, let reminder = items[id] else { continue }
            write(task, to: reminder, lists: lists, inbox: inbox)
            try? store.save(reminder, commit: false)
        }
        for task in plan.addRemote {
            let reminder = EKReminder(eventStore: store)
            write(task, to: reminder, lists: lists, inbox: inbox)
            if (try? store.save(reminder, commit: false)) != nil {
                book.update(task.id, now: task.modified) { $0.reminderID = reminder.calendarItemIdentifier }
            }
        }
        do {
            try store.commit()
        } catch {
            notice = "Couldn't update Reminders: \(error.localizedDescription)"
        }
        settings.lastSync = Date()
        objectWillChange.send()
        flushSave()
        onChange?()
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder] {
        let store = self.store
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
    }

    private func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
        let parts = reminder.dueDateComponents
        return ReminderSnapshot(
            id: reminder.calendarItemIdentifier, listID: reminder.calendar?.calendarIdentifier ?? "",
            title: reminder.title ?? "", notes: reminder.notes ?? "",
            due: parts.flatMap { components -> Date? in
                var components = components
                if components.calendar == nil { components.calendar = calendar }
                return calendar.date(from: components)
            },
            dueHasTime: parts?.hour != nil,
            priority: ReminderSnapshot.priority(fromEventKit: reminder.priority),
            completed: reminder.isCompleted ? (reminder.completionDate ?? Date()) : nil,
            modified: reminder.lastModifiedDate)
    }

    private func write(_ task: TaskItem, to reminder: EKReminder, lists: [EKCalendar], inbox: EKCalendar) {
        reminder.title = task.title
        reminder.notes = task.notes.isEmpty ? nil : task.notes
        reminder.priority = ReminderSnapshot.eventKitPriority(task.priority)
        let listID = book.project(task.projectID)?.reminderListID
        reminder.calendar = lists.first { $0.calendarIdentifier == listID } ?? inbox
        if let due = task.due {
            let units: Set<Calendar.Component> = task.dueHasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = calendar.dateComponents(units, from: due)
            // A time means a nudge on your phone.
            if task.dueHasTime, !(reminder.alarms ?? []).contains(where: { $0.absoluteDate == due }) {
                reminder.alarms = [EKAlarm(absoluteDate: due)]
            }
        } else {
            reminder.dueDateComponents = nil
        }
        if task.isDone != reminder.isCompleted { reminder.isCompleted = task.isDone }
    }

    var reminderListName: String? {
        settings.defaultListID.flatMap { id in store.calendars(for: .reminder).first { $0.calendarIdentifier == id }?.title }
    }
}
