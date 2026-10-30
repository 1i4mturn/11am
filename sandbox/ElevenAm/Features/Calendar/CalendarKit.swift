import Foundation

enum CalSource: Hashable, Codable, Sendable {
    /// Calendars macOS already syncs: iCloud, Google, Exchange (through EventKit).
    case eventKit
    /// An Outlook or Microsoft 365 account signed in with Microsoft (through Graph).
    case microsoft(accountID: String)
    case holidays
    case sample
}

struct CalCalendar: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// "#RRGGBB"
    var color: String
    var source: CalSource
    var account: String
    var writable: Bool
}

enum CalResponse: String, Codable, Sendable {
    case none, accepted, tentative, declined, organizer
}

struct CalAttendee: Hashable, Codable, Sendable {
    var name: String
    var email: String
    var response: CalResponse = .none
}

struct CalEvent: Identifiable, Hashable, Sendable {
    var id: String
    var calendarID: String
    var source: CalSource
    var title: String
    var start: Date
    var end: Date
    var isAllDay = false
    var location: String?
    var notes: String?
    var url: URL?
    var attendees: [CalAttendee] = []
    var organizer: String?
    /// Your own answer to the invitation.
    var response: CalResponse = .none
    var isRecurring = false
    var color = "#7A7A7A"
    var writable = false
    /// The provider's own ID (EventKit identifier or Graph ID).
    var externalID = ""

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// A Zoom, Teams, Meet or Webex link from the location, notes or URL.
    var joinURL: URL? { JoinLinks.find(in: [url?.absoluteString, location, notes].compactMap { $0 }.joined(separator: " ")) }

    func overlaps(_ other: CalEvent) -> Bool {
        !isAllDay && !other.isAllDay && start < other.end && other.start < end
    }

    var isOnThisMac: Bool {
        if case .eventKit = source { return true }
        return false
    }

    var isHoliday: Bool { source == .holidays }

    /// An invitation you haven't answered yet.
    var awaitsAnswer: Bool { response == .none && !attendees.isEmpty && organizer != nil }
}

// MARK: Join links

enum JoinLinks {
    private static let hosts = ["zoom.us", "teams.microsoft.com", "teams.live.com", "meet.google.com", "webex.com", "whereby.com", "around.co"]

    static func find(in text: String) -> URL? {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let host = url.host?.lowercased() else { continue }
            if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
        }
        return nil
    }

    static func service(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Teams" }
        if host.contains("meet.google") { return "Meet" }
        if host.contains("webex") { return "Webex" }
        return "call"
    }
}

// MARK: Quick add

/// "Lunch with Tom Fri 1pm at Lune for 90 min" → title, start, end, place. Dates are found by the system's own
/// date detector, so "tomorrow", "next Tue", "12 Dec" and "3-4pm" all work in English.
struct QuickAdd: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> QuickAdd? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        // An explicit length: "for 45 min", "for 2 hours", "for 1h".
        var minutes: Double?
        if let match = working.range(of: #"\s+for\s+(\d+(?:\.\d+)?)\s*(minutes|minute|mins|min|m|hours|hour|hrs|hr|h)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let phrase = String(working[match]).lowercased()
            let number = Double(phrase.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()) ?? 1
            minutes = phrase.contains("h") ? number * 60 : number
            working.removeSubrange(match)
        }

        let allDayWords = working.range(of: #"\ball[ -]day\b"#, options: [.regularExpression, .caseInsensitive])
        if let allDayWords { working.removeSubrange(allDayWords) }

        var start: Date?
        var detectedDuration: TimeInterval = 0
        var hasTime = false
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(working.startIndex..., in: working)
            if let match = detector.matches(in: working, range: range).first, let date = match.date, let swiftRange = Range(match.range, in: working) {
                let phrase = String(working[swiftRange])
                start = date
                detectedDuration = match.duration
                hasTime = phrase.range(of: #"\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|\bnoon\b|\bmidday\b|\bmidnight\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                working.removeSubrange(swiftRange)
            }
        }
        guard var begin = start else { return nil }

        // "at Lune" or "@ Lune": a place, once the time has been taken out.
        var location: String?
        if let match = working.range(of: #"\s+(at|@)\s+(.+)$"#, options: [.regularExpression, .caseInsensitive]) {
            let place = String(working[match]).replacingOccurrences(of: #"^\s+(at|@)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespaces)
            if !place.isEmpty {
                location = place
                working.removeSubrange(match)
            }
        }

        var title = working
            .replacingOccurrences(of: #"\s+(on|at|from|this|next)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",-–")))
        if title.isEmpty { title = "New event" }
        title = title.prefix(1).uppercased() + title.dropFirst()

        let allDay = allDayWords != nil || !hasTime
        if allDay {
            begin = calendar.startOfDay(for: begin)
            // Dates in the past mean the next one: "12 Dec" in January is next December.
            if begin < calendar.startOfDay(for: now), let next = calendar.date(byAdding: .year, value: 1, to: begin) { begin = next }
            let end = calendar.date(byAdding: .day, value: 1, to: begin) ?? begin.addingTimeInterval(86_400)
            return QuickAdd(title: title, start: begin, end: end, isAllDay: true, location: location)
        }
        let length = minutes.map { $0 * 60 } ?? (detectedDuration > 0 ? detectedDuration : 3_600)
        return QuickAdd(title: title, start: begin, end: begin.addingTimeInterval(length), isAllDay: false, location: location)
    }
}

// MARK: Free time

enum FreeTime {
    /// Gaps of at least `minimum` within working hours on each day, around the busy events (all-day events don't block).
    static func slots(busy: [CalEvent], from start: Date, days: Int, minimum: TimeInterval,
                      dayStart: Int = 9, dayEnd: Int = 17, calendar: Calendar = .current, now: Date = Date()) -> [DateInterval] {
        var result: [DateInterval] = []
        let blocks = busy.filter { !$0.isAllDay && $0.response != .declined }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start)) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            if weekday == 1 || weekday == 7 { continue }
            guard let open = calendar.date(bySettingHour: dayStart, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: dayEnd, minute: 0, second: 0, of: day) else { continue }
            // Round "now" up to the next quarter hour, so a slot never starts in the past.
            var cursor = max(open, roundUp(now, minutes: 15, calendar: calendar))
            let today = blocks.filter { $0.end > open && $0.start < close }.sorted { $0.start < $1.start }
            for block in today {
                if block.start.timeIntervalSince(cursor) >= minimum { result.append(DateInterval(start: cursor, end: block.start)) }
                cursor = max(cursor, block.end)
            }
            if close.timeIntervalSince(cursor) >= minimum { result.append(DateInterval(start: cursor, end: close)) }
        }
        return result
    }

    static func roundUp(_ date: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let extra = (minutes - minute % minutes) % minutes
        if extra == 0 && second == 0 { return date }
        let base = date.addingTimeInterval(-Double(second))
        return base.addingTimeInterval(Double(extra == 0 ? minutes : extra) * 60)
    }

    /// Ready to paste into an email: "Thu 30 Oct, 2:00–4:00 pm".
    static func text(_ slots: [DateInterval], calendar: Calendar = .current) -> String {
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.timeStyle = .short
        time.dateStyle = .none
        let zone = calendar.timeZone.abbreviation(for: slots.first?.start ?? Date()) ?? calendar.timeZone.identifier
        let lines = slots.map { "\(day.string(from: $0.start)), \(time.string(from: $0.start))–\(time.string(from: $0.end))" }
        return "Times that work for me (\(zone)):\n" + lines.map { "• \($0)" }.joined(separator: "\n")
    }
}

// MARK: Layout

enum EventLayout {
    struct Placed: Sendable {
        var event: CalEvent
        var column: Int
        var columns: Int
    }

    /// Side by side when they overlap, full width when they don't.
    static func place(_ events: [CalEvent]) -> [Placed] {
        let sorted = events.filter { !$0.isAllDay }.sorted { ($0.start, $1.duration) < ($1.start, $0.duration) }
        var placed: [Placed] = []
        var cluster: [Placed] = []
        var clusterEnd = Date.distantPast
        var columnEnds: [Date] = []

        func flush() {
            let width = (cluster.map(\.column).max() ?? 0) + 1
            placed += cluster.map { Placed(event: $0.event, column: $0.column, columns: width) }
            cluster = []
            columnEnds = []
        }

        for event in sorted {
            if event.start >= clusterEnd, !cluster.isEmpty { flush() }
            let column = columnEnds.firstIndex { $0 <= event.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(event.end) } else { columnEnds[column] = event.end }
            cluster.append(Placed(event: event, column: column, columns: 1))
            clusterEnd = max(clusterEnd, event.end)
        }
        if !cluster.isEmpty { flush() }
        return placed
    }

    /// Pairs of events that clash, for the double-booking warning.
    static func conflicts(_ events: [CalEvent]) -> [(CalEvent, CalEvent)] {
        let timed = events.filter { !$0.isAllDay && $0.response != .declined }.sorted { $0.start < $1.start }
        var pairs: [(CalEvent, CalEvent)] = []
        for (index, event) in timed.enumerated() {
            for other in timed[(index + 1)...] {
                if other.start >= event.end { break }
                pairs.append((event, other))
            }
        }
        return pairs
    }
}

// MARK: Australian public holidays

/// National public holidays, with the weekend substitutes most states observe. State-only days (Labour Day,
/// the King's Birthday, Melbourne Cup and so on) differ by state and are left to your own calendars.
enum AustralianHolidays {
    static func holidays(year: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> [(date: Date, name: String)] {
        var cal = calendar
        cal.timeZone = .current
        func date(_ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date.distantPast
        }
        func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) }
        func adding(_ days: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: days, to: d) ?? d }

        var list: [(Date, String)] = []
        let newYear = date(1, 1)
        list.append((newYear, "New Year's Day"))
        if weekday(newYear) == 7 { list.append((adding(2, to: newYear), "New Year's Day (observed)")) }
        if weekday(newYear) == 1 { list.append((adding(1, to: newYear), "New Year's Day (observed)")) }

        let australia = date(1, 26)
        if weekday(australia) == 7 { list.append((adding(2, to: australia), "Australia Day (observed)")) }
        else if weekday(australia) == 1 { list.append((adding(1, to: australia), "Australia Day (observed)")) }
        else { list.append((australia, "Australia Day")) }

        let easter = easterSunday(year, calendar: cal)
        list.append((adding(-2, to: easter), "Good Friday"))
        list.append((adding(1, to: easter), "Easter Monday"))
        list.append((date(4, 25), "Anzac Day"))

        let christmas = date(12, 25)
        let boxing = date(12, 26)
        list.append((christmas, "Christmas Day"))
        list.append((boxing, "Boxing Day"))
        switch weekday(christmas) {
        case 7: // Saturday: Monday and Tuesday
            list.append((adding(2, to: christmas), "Christmas Day (observed)"))
            list.append((adding(3, to: christmas), "Boxing Day (observed)"))
        case 1: // Sunday: Boxing Day is Monday, Christmas moves to Tuesday
            list.append((adding(2, to: christmas), "Christmas Day (observed)"))
        case 6: // Friday: Boxing Day falls on Saturday, observed Monday
            list.append((adding(3, to: christmas), "Boxing Day (observed)"))
        default:
            break
        }
        return list.sorted { $0.0 < $1.0 }.map { (date: $0.0, name: $0.1) }
    }

    /// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    static func easterSunday(_ year: Int, calendar: Calendar) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date.distantPast
    }

    static func events(in interval: DateInterval, calendar: Calendar = Calendar(identifier: .gregorian)) -> [CalEvent] {
        let startYear = calendar.component(.year, from: interval.start)
        let endYear = calendar.component(.year, from: interval.end)
        var events: [CalEvent] = []
        for year in startYear...max(startYear, endYear) {
            for holiday in holidays(year: year, calendar: calendar) where interval.contains(holiday.date) || holiday.date == interval.start {
                let end = calendar.date(byAdding: .day, value: 1, to: holiday.date) ?? holiday.date.addingTimeInterval(86_400)
                events.append(CalEvent(id: "holiday:\(year):\(holiday.name)", calendarID: "holidays", source: .holidays,
                                       title: holiday.name, start: holiday.date, end: end, isAllDay: true, color: "#9A9A9A"))
            }
        }
        return events
    }
}

extension Calendar {
    /// The days in an interval, each at the start of the day.
    func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
