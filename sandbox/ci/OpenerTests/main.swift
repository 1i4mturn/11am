// Today's overprint opener: the day's number, its word, and the note's heading and line, from the calendar and tasks.
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
calendar.locale = Locale(identifier: "en_AU")

func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

let clock: (Date) -> String = { date in
    let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
    return String(format: "%d:%02d", hour > 12 ? hour - 12 : hour, minute)
}

func opener(_ now: Date, _ events: [TodayOpenerText.Event], due: Int = 0, overdue: Int = 0, brief: Bool = false) -> TodayOpenerText {
    TodayOpenerText.make(now: now, events: events, tasksDue: due, overdue: overdue, briefReady: brief, calendar: calendar, time: clock)
}

let day = [
    TodayOpenerText.Event(title: "Investor call", start: at(23, 9), end: at(23, 9, 45)),
    TodayOpenerText.Event(title: "The 11am check-in", start: at(23, 11), end: at(23, 11, 15)),
    TodayOpenerText.Event(title: "Deep work", start: at(23, 13), end: at(23, 15)),
    TodayOpenerText.Event(title: "Melbourne Cup", start: at(23, 0), end: at(24, 0), isAllDay: true),
]

let morning = opener(at(23, 8), day, due: 4, overdue: 1, brief: true)
check(morning.numeral == "23", "numeral: the day of the month")
check(morning.word == .solveIt, "word: a full day is solve it")
check(morning.heading == "Three meetings.", "heading: counts meetings left, all-day events aside")
check(morning.line == "Next, Investor call at 9:00. 4 tasks due, 1 overdue. Your brief is ready.", "line: next, tasks, brief")
check(morning.label == "monday · solve it", "label: weekday and the word, lowercase")

let midday = opener(at(23, 12), day, due: 1)
check(midday.word == .ownIt && midday.heading == "One meeting.", "midday: one left is own it")
check(midday.line == "Next, Deep work at 1:00. 1 task due.", "midday: singular task")

let during = opener(at(23, 13, 30), day)
check(during.line.hasPrefix("Deep work is on now."), "a meeting under way is on now")
check(during.line.hasSuffix("No tasks due."), "no tasks due says so")

let free = opener(at(24, 9), [])
check(free.word == .buildIt && free.heading == "Nothing booked.", "an open day is build it, nothing booked")
check(free.numeral == "24", "numeral follows the day")

let afterwards = opener(at(23, 15, 30), day)
check(afterwards.heading == "Meetings done." && afterwards.word == .buildIt, "after the last meeting: meetings done, build it")

let evening = opener(at(23, 18), day, overdue: 2)
check(evening.word == .keepIt, "evening is keep it")
check(evening.line == "2 overdue.", "evening: only the overdue count")

check(opener(at(7, 9), []).numeral == "07", "numeral: two digits")
check(TodayOpenerText.shortened("Quarterly planning with the whole leadership team", to: 28).count == 28, "long titles are shortened")
check(TodayOpenerText.shortened("Quarterly planning with the whole leadership team", to: 28).hasSuffix("…"), "with an ellipsis")
check(TodayOpenerText.spelled(12) == "12" && TodayOpenerText.spelled(10) == "Ten", "counts spelled to ten")
check(Set(OverprintWord.allCases.map(\.rawValue)) == ["own it", "build it", "solve it", "keep it"], "the four words")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
