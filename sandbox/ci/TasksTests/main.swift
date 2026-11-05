import Foundation

// Checks Leo's Tasks: quick add in plain English, repeats, the smart lists, ticking off, snoozing, ordering,
// promises found in sent mail, and the rules for syncing with Apple Reminders.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
cal.locale = Locale(identifier: "en_AU")

func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// Thursday 5 November 2026, 10 am in Sydney.
let now = day(2026, 11, 5, 10)
check(cal.component(.weekday, from: now) == 5, "The test day is a Thursday")

func parse(_ text: String, dayFirst: Bool = true, at time: Date = now) -> TaskParse {
    TaskParser.parse(text, now: time, calendar: cal, dayFirst: dayFirst)
}

// MARK: Quick add

var p = parse("Call Tom tomorrow at 3pm")
check(p.title == "Call Tom" && p.due == day(2026, 11, 6, 15) && p.dueHasTime, "Tomorrow at 3pm")
check(p.understood.first == "Tomorrow, 3 pm", "What was understood is shown back: \(p.understood)")
p = parse("Pay rent friday")
check(p.title == "Pay rent" && p.due == day(2026, 11, 6) && !p.dueHasTime, "A day name means the next one")
check(parse("Pay rent thursday").due == day(2026, 11, 5), "Today's day name means today")
p = parse("Buy sun cream")
check(p.title == "Buy sun cream" && p.due == nil, "Short day names don't count on their own (sun cream)")
check(parse("Dentist on sun").due == day(2026, 11, 8), "…but do after \"on\"")
check(parse("Submit report by 28 Oct").due == day(2027, 10, 28), "A date that's gone means next year")
check(parse("Renew rego 3/12").due == day(2026, 12, 3), "Day first: 3/12 is 3 December")
check(parse("Renew rego 3/12", dayFirst: false).due == day(2027, 3, 12), "Month first: 3/12 is 12 March (next year)")
check(parse("Lodge it on 2026-12-01").due == day(2026, 12, 1), "ISO dates")
check(parse("Book venue March 14th").due == day(2027, 3, 14), "Month then day, with a suffix")
check(parse("Send invoice next monday").due == day(2026, 11, 9), "Next Monday is in next week")
check(parse("Plan trip next week").due == day(2026, 11, 9), "Next week starts on Monday")
check(parse("Review in 3 days").due == day(2026, 11, 8), "In 3 days")
p = parse("Check the oven in 2 hours")
check(p.due == day(2026, 11, 5, 12) && p.dueHasTime && p.title == "Check the oven", "In 2 hours")
check(parse("Follow up in a fortnight").due == day(2026, 11, 19), "In a fortnight")
p = parse("Call mum tonight")
check(p.due == day(2026, 11, 5, 18) && p.dueHasTime && p.title == "Call mum", "Tonight is 6 pm")
check(parse("Call mum tomorrow morning").due == day(2026, 11, 6, 9), "Tomorrow morning is 9 am")
check(parse("Call at 9").due == day(2026, 11, 6, 9), "A time that's passed today means tomorrow")
check(parse("Call at 3").due == day(2026, 11, 5, 15), "At 3 means the afternoon")
check(parse("Email Sam 5:30").due == day(2026, 11, 5, 17, 30), "5:30 means the afternoon")
check(parse("Stand-up 15:45").due == day(2026, 11, 5, 15, 45), "24-hour times")
p = parse("Buy 1.5 litres of milk")
check(p.due == nil && p.title == "Buy 1.5 litres of milk", "1.5 litres isn't a time")
check(parse("Pay invoice by end of month").due == day(2026, 11, 30), "End of month")
p = parse("Pay rent!! #home @Personal")
check(p.title == "Pay rent" && p.priority == .medium && p.tags == ["home"] && p.project == "Personal", "Priority, tag and project")
check(parse("Fix login bug p1").priority == .high && parse("Fix login bug !").priority == .low, "p1 and !")
p = parse("Pay rent friday!!")
check(p.title == "Pay rent" && p.priority == .medium && p.due == day(2026, 11, 6), "!! stuck on a date word")
p = parse("Watch \"Friday Night Lights\"")
check(p.due == nil && p.title == "Watch \"Friday Night Lights\"", "Words in quotes are left alone")
p = parse("Learn piano someday")
check(p.someday && p.title == "Learn piano" && p.due == nil, "Someday")
p = parse("Book flights start monday")
check(p.start == day(2026, 11, 9) && p.due == nil && p.title == "Book flights", "A start date")
p = parse("Book #1 priority item")
check(p.tags.isEmpty, "#1 isn't a tag")

// Repeats.
p = parse("Water plants every 3 days")
check(p.recurrence == Recurrence(unit: .day, every: 3) && p.due == day(2026, 11, 5) && p.title == "Water plants", "Every 3 days, from today")
p = parse("Gym every mon and thu at 7am")
check(p.recurrence?.weekdays == [2, 5] && p.due == day(2026, 11, 9, 7) && p.title == "Gym", "Every Mon and Thu at 7am starts Monday, as 7am today has passed")
p = parse("Team report every 2 weeks on friday")
check(p.recurrence == Recurrence(unit: .week, every: 2, weekdays: [6]) && p.due == day(2026, 11, 6), "Every 2 weeks on Friday")
check(parse("Fortnightly team catch-up").recurrence == Recurrence(unit: .week, every: 2), "Fortnightly")
check(parse("Timesheet every weekday").recurrence?.unit == .weekday, "Every weekday")
check(parse("Pay super monthly").recurrence?.unit == .month, "Monthly")

// MARK: Repeats

let weekday = Recurrence(unit: .weekday)
check(weekday.next(after: day(2026, 11, 6), calendar: cal) == day(2026, 11, 9), "After Friday, the next weekday is Monday")
let monThu = Recurrence(unit: .week, every: 2, weekdays: [2, 5])
check(monThu.next(after: day(2026, 11, 2), calendar: cal) == day(2026, 11, 5), "Fortnightly Mon/Thu: Monday → Thursday the same week")
check(monThu.next(after: day(2026, 11, 5), calendar: cal) == day(2026, 11, 16), "…then skips a week")
check(Recurrence(unit: .month).next(after: day(2026, 1, 31), calendar: cal) == day(2026, 2, 28), "Monthly from 31 January lands on 28 February")
check(monThu.text == "Every fortnight on Monday and Thursday", "Repeats read naturally: \(monThu.text)")
check(Recurrence(unit: .week, weekdays: [6, 2]).text == "Every Monday and Friday", "Weekdays are listed Monday first")
check(Recurrence(unit: .day, every: 3, afterCompletion: true).text == "Every 3 days after it's done", "After it's done")

// MARK: Smart lists

let project = TaskProject(name: "Website", sections: [TaskSection(name: "Design"), TaskSection(name: "Build")])
var book = TaskBook(projects: [project])
let plain = book.add(TaskItem(title: "Plain"))
let dueToday = book.add(TaskItem(title: "Due today", due: day(2026, 11, 5)))
let overdue = book.add(TaskItem(title: "Overdue", due: day(2026, 11, 3)))
let important = book.add(TaskItem(title: "Important", priority: .high, due: day(2026, 11, 5)))
let nextTuesday = book.add(TaskItem(title: "Next Tuesday", due: day(2026, 11, 10)))
let later = book.add(TaskItem(title: "Starts tomorrow", start: day(2026, 11, 6, 9)))
let dream = book.add(TaskItem(title: "Learn piano", someday: true))
let inProject = book.add(TaskItem(title: "Wireframes", projectID: project.id, sectionID: project.sections[1].id))
let firstInProject = book.add(TaskItem(title: "Moodboard", projectID: project.id, sectionID: project.sections[0].id))
let finished = book.add(TaskItem(title: "Finished", completed: day(2026, 11, 4)))

func ids(_ list: TaskListID) -> [UUID] { book.tasks(in: list, now: now, calendar: cal).map(\.id) }
check(ids(.inbox) == [plain], "The Inbox holds tasks with no project and no date")
check(ids(.today) == [overdue, important, dueToday], "Today: overdue first, then the most important")
check(ids(.upcoming) == [later, nextTuesday], "Upcoming: by date")
check(ids(.someday) == [dream], "Someday")
check(ids(.logbook) == [finished], "The logbook holds what's done")
check(ids(.project(project.id)) == [firstInProject, inProject], "A project lists its tasks section by section")
check(book.upcomingDays(now: now, calendar: cal).map(\.day) == [day(2026, 11, 6), day(2026, 11, 10)], "Upcoming is grouped by day")
check(book.isOverdue(book.task(overdue)!, now: now, calendar: cal) && !book.isOverdue(book.task(dueToday)!, now: now, calendar: cal), "Overdue means before today")
check(ids(.today).contains(later) == false, "A task that starts tomorrow isn't in Today")
check(book.tasks(in: .today, now: day(2026, 11, 6, 9, 30), calendar: cal).contains { $0.id == later }, "…and is, once it starts")

// MARK: Ticking off, repeats and snoozing

var weekly = TaskItem(title: "Weekly review", due: day(2026, 11, 5), checklist: [ChecklistItem(title: "Inbox zero", done: true)], recurrence: Recurrence(unit: .week, weekdays: [5]))
let weeklyID = book.add(weekly)
let nextID = book.complete(weeklyID, now: now, calendar: cal)
check(book.task(weeklyID)?.isDone == true && book.task(weeklyID)?.status == .done, "Ticking off marks it done")
let nextWeekly = nextID.flatMap { book.task($0) }
check(nextWeekly?.due == day(2026, 11, 12) && nextWeekly?.isDone == false, "A repeating task comes back next week")
check(nextWeekly?.checklist.allSatisfy { !$0.done } == true, "…with its checklist cleared")
check(book.complete(weeklyID, now: now, calendar: cal) == nil, "Ticking off twice does nothing")

weekly = TaskItem(title: "Missed", due: day(2026, 10, 1), recurrence: Recurrence(unit: .week))
let missedID = book.add(weekly)
let caughtUp = book.complete(missedID, now: now, calendar: cal).flatMap { book.task($0) }
check(caughtUp?.due == day(2026, 11, 5), "Missed repeats catch up to today, not a pile of overdue copies")

let watering = book.add(TaskItem(title: "Water", due: day(2026, 11, 1, 9), dueHasTime: true, recurrence: Recurrence(unit: .day, every: 3, afterCompletion: true)))
let watered = book.complete(watering, now: now, calendar: cal).flatMap { book.task($0) }
check(watered?.due == day(2026, 11, 8, 9), "After it's done: 3 days from today, same time")

check(SnoozeOption.tomorrow.date(now: now, calendar: cal) == day(2026, 11, 6, 9), "Snooze until tomorrow, 9 am")
check(SnoozeOption.thisEvening.date(now: now, calendar: cal) == day(2026, 11, 5, 18), "Snooze until this evening")
check(SnoozeOption.thisEvening.date(now: day(2026, 11, 5, 19), calendar: cal) == nil, "No 'this evening' once it's evening")
check(SnoozeOption.thisWeekend.date(now: now, calendar: cal) == day(2026, 11, 7, 9), "This weekend is Saturday")
check(SnoozeOption.nextWeek.date(now: now, calendar: cal) == day(2026, 11, 9, 9), "Next week is Monday")
check(SnoozeOption.laterToday.date(now: now, calendar: cal) == day(2026, 11, 5, 13), "Later today is about three hours on")
book.snooze(dueToday, until: day(2026, 11, 6, 9), now: now)
check(!ids(.today).contains(dueToday) && ids(.upcoming).contains(dueToday), "A snoozed task leaves Today for Upcoming")

book.setStatus(plain, .doing, now: now, calendar: cal)
check(book.task(plain)?.status == .doing && book.task(plain)?.isDone == false, "Moving to Doing on the board")
book.setStatus(plain, .done, now: now, calendar: cal)
check(book.task(plain)?.isDone == true, "Moving to Done ticks it off")
book.reopen(plain, now: now)
check(book.task(plain)?.isDone == false && book.task(plain)?.status == .todo, "Reopening")

// MARK: Ordering, removing, tags

var small = TaskBook()
let a = small.add(TaskItem(title: "A"))
let b = small.add(TaskItem(title: "B"))
let c = small.add(TaskItem(title: "C"))
small.move(c, before: a, among: small.tasks, now: now)
check(small.tasks.sorted { $0.order < $1.order }.map(\.id) == [c, a, b], "Dragging C to the top")
small.move(c, before: nil, among: small.tasks.sorted { $0.order < $1.order }, now: now)
check(small.tasks.sorted { $0.order < $1.order }.map(\.id) == [a, b, c], "…and back to the end")
small.remove(b)
check(small.task(b) == nil && small.removed.first?.id == b, "Removing keeps it for undo")
check(small.undoRemove() == b && small.task(b) != nil, "Undo brings it back")

var tagged = TaskBook()
tagged.add(TaskItem(title: "1", tags: ["home"]))
tagged.add(TaskItem(title: "2", tags: ["Work", "home"]))
tagged.add(TaskItem(title: "3", tags: ["work"]))
check(tagged.tags.count == 2 && Set(tagged.tags.map { $0.lowercased() }) == ["home", "work"], "Tags ignore case")
check(tagged.tasks(in: .tag("WORK"), now: now, calendar: cal).count == 2, "A tag list matches any case")
check(book.progress(of: project.id).done == 0 && book.progress(of: project.id).total == 2, "Project progress")

let minimal = #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "title": "From an older version"}"#
let decoded = try? JSONDecoder().decode(TaskItem.self, from: Data(minimal.utf8))
check(decoded?.title == "From an older version" && decoded?.tags == [] && decoded?.status == .todo, "Tasks saved by older versions still load")

// MARK: Promises in sent mail

let sent = """
Hi Tom,

Thanks for this. I'll send you the deck by Friday.
Sure, I'll get back to you tomorrow about the budget. Let me know if that works.
I'll be in the office all week. Will you bring the contracts?

Cheers
Sam

On Tue, 3 Nov 2026 at 9:00 am, Tom Baker wrote:
> I'll call you on Monday
"""
let promises = PromiseFinder.promises(in: sent, to: "Tom Baker <tom@example.com>", sent: now, calendar: cal)
check(promises.count == 2, "Two promises found, none from the quoted reply or 'I'll be': \(promises.map(\.title))")
check(promises.first?.title == "Send Tom the deck" && promises.first?.due == day(2026, 11, 6), "\"I'll send you the deck by Friday\" → Send Tom the deck, due Friday")
check(promises.last?.title == "Get back to Tom about the budget" && promises.last?.due == day(2026, 11, 6), "\"I'll get back to you tomorrow\" → Get back to Tom, due tomorrow")
check(PromiseFinder.firstName("Tom Baker <tom@example.com>") == "Tom", "First name from a display name")
check(PromiseFinder.firstName("tom.baker@example.com") == "Tom", "First name from an address")
check(PromiseFinder.firstName("Baker, Tom") == "Tom", "First name from 'Last, First'")
check(PromiseFinder.promises(in: "Shall I send it over?", to: "Tom", sent: now, calendar: cal).isEmpty, "Questions aren't promises")

// MARK: Syncing with Reminders

let oldEdit = day(2026, 11, 1)
let newEdit = day(2026, 11, 4)
var p1 = TaskProject(name: "House")
p1.reminderListID = "list-house"
func linked(_ title: String, _ id: String, modified: Date = oldEdit) -> TaskItem {
    var task = TaskItem(title: title, modified: modified)
    task.reminderID = id
    return task
}
func snap(_ id: String, _ title: String, list: String = "list-inbox", modified: Date = oldEdit, completed: Date? = nil) -> ReminderSnapshot {
    ReminderSnapshot(id: id, listID: list, title: title, notes: "", due: nil, dueHasTime: false, priority: .none, completed: completed, modified: modified)
}
let same = linked("Same", "r1")
let changedThere = linked("Old title", "r2")
let changedHere = linked("New title here", "r3", modified: newEdit)
let deleted = linked("Deleted there", "r4")
let unsynced = TaskItem(title: "Not in Reminders yet")
let doneThere = linked("Done in Reminders", "r7")
let plan = ReminderSync.plan(
    tasks: [same, changedThere, changedHere, deleted, unsynced, doneThere],
    projects: [p1],
    reminders: [snap("r1", "Same"), snap("r2", "New title there", modified: newEdit), snap("r3", "Old title"),
                snap("r5", "New from Siri", list: "list-house"), snap("r6", "Old and done", completed: oldEdit),
                snap("r7", "Done in Reminders", modified: newEdit, completed: newEdit)],
    missing: ["r4"], defaultListID: "list-inbox", now: now)
check(plan.updateLocal.map(\.title).sorted() == ["Done in Reminders", "New title there"], "Newer changes in Reminders come in")
check(plan.updateLocal.first { $0.id == doneThere.id }?.isDone == true, "Ticked off in Reminders is ticked off here")
check(plan.updateRemote.map(\.id) == [changedHere.id], "Newer changes here go out")
check(plan.removeLocal == [deleted.id], "Deleted in Reminders is removed here")
check(plan.addRemote.map(\.id) == [unsynced.id], "New tasks are added to Reminders")
check(plan.addLocal.count == 1 && plan.addLocal.first?.title == "New from Siri" && plan.addLocal.first?.projectID == p1.id,
      "New reminders come in, into the project for their list")
check(plan.addLocal.first?.origin?.kind == .reminders, "…marked as from Reminders")
check(ReminderSnapshot.priority(fromEventKit: 1) == .high && ReminderSnapshot.priority(fromEventKit: 5) == .medium
      && ReminderSnapshot.priority(fromEventKit: 9) == .low && ReminderSnapshot.priority(fromEventKit: 0) == TaskPriority.none, "Reminders priorities")
check(TaskPriority.allCases.allSatisfy { ReminderSnapshot.priority(fromEventKit: ReminderSnapshot.eventKitPriority($0)) == $0 }, "Priorities round-trip")
check(ReminderSync.plan(tasks: [same], projects: [], reminders: [snap("r1", "Same")], missing: [], defaultListID: "x", now: now).isEmpty,
      "Nothing to do when nothing changed")

// MARK: Labels

check(TaskDates.label(day(2026, 11, 6, 15), hasTime: true, now: now, calendar: cal) == "Tomorrow, 3 pm", "Tomorrow, 3 pm")
check(TaskDates.label(day(2026, 11, 10), hasTime: false, now: now, calendar: cal) == "Tuesday", "Days this week by name")
check(TaskDates.label(day(2026, 11, 20), hasTime: false, now: now, calendar: cal).contains("20 Nov"), "Later dates in full")
check(TaskDates.time(day(2026, 11, 5, 9, 30), calendar: cal) == "9:30 am", "9:30 am")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
