import Foundation

/// The overprint's four words, from the brand's ownership story: own it for identity and outcomes, build it for the
/// work, solve it for the problem, keep it for what you walk away with.
enum OverprintWord: String, CaseIterable, Sendable {
    case ownIt = "own it"
    case buildIt = "build it"
    case solveIt = "solve it"
    case keepIt = "keep it"
}

/// What Today's opener says: the day's number in the square, its word behind, and on the note a label, a short heading
/// and a line about the day. Worked out from the calendar and the task list, the same every time for the same day.
struct TodayOpenerText: Equatable, Sendable {
    var numeral: String
    var word: OverprintWord
    var label: String
    var heading: String
    var line: String

    struct Event: Sendable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool

        init(title: String, start: Date, end: Date, isAllDay: Bool = false) {
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
        }
    }

    static func make(now: Date, events: [Event], tasksDue: Int, overdue: Int, briefReady: Bool,
                     calendar: Calendar = .current, time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }) -> TodayOpenerText {
        let day = calendar.component(.day, from: now)
        let hour = calendar.component(.hour, from: now)
        let timed = events.filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: now) }.sorted { $0.start < $1.start }
        let left = timed.filter { $0.end > now }

        // The word follows the shape of the day: evenings keep, open days build, full days solve, the rest own.
        let word: OverprintWord
        if hour >= 17 {
            word = .keepIt
        } else if left.isEmpty {
            word = .buildIt
        } else if left.count >= 3 {
            word = .solveIt
        } else {
            word = .ownIt
        }

        let heading: String
        if left.isEmpty {
            heading = timed.isEmpty ? "Nothing booked." : "Meetings done."
        } else {
            heading = "\(spelled(left.count)) \(left.count == 1 ? "meeting" : "meetings")."
        }

        var parts: [String] = []
        if let next = left.first {
            let title = shortened(next.title, to: 28)
            parts.append(next.start <= now ? "\(title) is on now." : "Next, \(title) at \(time(next.start)).")
        }
        if tasksDue == 0 {
            parts.append(overdue == 0 ? "No tasks due." : "\(overdue) overdue.")
        } else {
            var text = "\(tasksDue) \(tasksDue == 1 ? "task" : "tasks") due"
            if overdue > 0 { text += ", \(overdue) overdue" }
            parts.append(text + ".")
        }
        if briefReady { parts.append("Your brief is ready.") }

        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1].lowercased()
        let month = calendar.monthSymbols[calendar.component(.month, from: now) - 1].lowercased()
        return TodayOpenerText(numeral: String(format: "%02d", day), word: word, label: "\(weekday) · \(month) · \(word.rawValue)",
                               heading: heading, line: parts.joined(separator: " "))
    }

    static func spelled(_ count: Int) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"]
        return count < words.count ? words[count] : "\(count)"
    }

    static func shortened(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
