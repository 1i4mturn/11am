import Foundation

// Leo's calendar, finished: the weather on each day, when to leave for something across town, sets of calendars to
// switch between, week numbers, room between meetings, and events that repeat or remind you. Plain data, tested on CI.

// MARK: - Weather

/// One day's forecast.
struct DayWeather: Equatable, Hashable, Sendable {
    /// Midnight at the start of the day, in the calendar's time zone.
    var day: Date
    /// The WMO weather code Open-Meteo uses.
    var code: Int
    var high: Double
    var low: Double
    /// Chance of rain, in percent.
    var rain: Int?

    var symbol: String { Weather.symbol(code) }
    var words: String { Weather.words(code) }
    /// "24°"
    var short: String { "\(Int(high.rounded()))°" }
    /// "Showers, 16–24°, 70% chance of rain"
    var line: String {
        var text = "\(words), \(Int(low.rounded()))–\(Int(high.rounded()))°"
        if let rain, rain >= 20 { text += ", \(rain)% chance of rain" }
        return text
    }
}

/// A place to show the weather for.
struct WeatherPlace: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String = ""
}

/// The forecast from Open-Meteo: free, no account, and only the place's coordinates are sent.
enum Weather {
    static func forecastURL(_ place: WeatherPlace, days: Int = 14) -> URL? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", place.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(min(max(days, 1), 16))),
        ]
        return parts?.url
    }

    static func placeURL(_ name: String) -> URL? {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        parts?.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1"),
                             URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        return parts?.url
    }

    /// The days in a forecast answer, each at the start of its day.
    static func parse(_ data: Data, calendar: Calendar) -> [DayWeather] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = root["daily"] as? [String: Any], let days = daily["time"] as? [String] else { return [] }
        func numbers(_ key: String) -> [Double?] {
            (daily[key] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let codes = numbers("weather_code"), highs = numbers("temperature_2m_max"), lows = numbers("temperature_2m_min")
        let rain = numbers("precipitation_probability_max")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var result: [DayWeather] = []
        for (index, text) in days.enumerated() {
            guard let date = formatter.date(from: text),
                  let code = codes.indices.contains(index) ? codes[index] : nil,
                  let high = highs.indices.contains(index) ? highs[index] : nil,
                  let low = lows.indices.contains(index) ? lows[index] : nil else { continue }
            let chance = rain.indices.contains(index) ? rain[index].map { Int($0.rounded()) } : nil
            result.append(DayWeather(day: calendar.startOfDay(for: date), code: Int(code), high: high, low: low, rain: chance))
        }
        return result
    }

    static func parsePlace(_ data: Data) -> WeatherPlace? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["results"] as? [[String: Any]])?.first,
              let name = first["name"] as? String,
              let latitude = (first["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (first["longitude"] as? NSNumber)?.doubleValue else { return nil }
        return WeatherPlace(name: name, latitude: latitude, longitude: longitude, country: first["country"] as? String ?? "")
    }

    /// A guess at your city from the Mac's time zone ("Australia/Sydney" → "Sydney").
    static func city(from zone: TimeZone) -> String? {
        let parts = zone.identifier.split(separator: "/")
        guard parts.count >= 2, let last = parts.last else { return nil }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// SF Symbols for the WMO codes.
    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67, 80...82: return "cloud.rain"
        case 71...77, 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }

    static func words(_ code: Int) -> String {
        switch code {
        case 0: return "Sunny"
        case 1: return "Mostly sunny"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61, 63, 66: return "Rain"
        case 65, 67: return "Heavy rain"
        case 71...77, 85, 86: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Storms"
        default: return "Cloudy"
        }
    }
}

// MARK: - Travel

/// Getting to things that happen somewhere: from where you were before, with a few minutes to spare.
enum Travel {
    static let onlineWords = ["zoom", "teams", "meet.google", "google meet", "webex", "online", "video call", "phone call", "facetime", "http://", "https://"]

    /// A place you'd have to travel to, not a video call.
    static func isPlace(_ location: String?) -> Bool {
        guard let text = location?.trimmingCharacters(in: .whitespacesAndNewlines), text.count >= 3 else { return false }
        let lower = text.lowercased()
        return !onlineWords.contains { lower.contains($0) }
    }

    /// Where you're coming from: the place of the last event that ends within three hours before this one on the same
    /// day, or home.
    static func origin(for event: CalEvent, in events: [CalEvent], home: String?, calendar: Calendar) -> String? {
        let window = event.start.addingTimeInterval(-3 * 3_600)
        let before = events.filter { other in
            other.id != event.id && !other.isAllDay && other.response != .declined && isPlace(other.location)
                && other.end <= event.start && other.end > window && calendar.isDate(other.end, inSameDayAs: event.start)
        }
        if let last = before.max(by: { $0.end < $1.end }) { return last.location }
        return home.flatMap { isPlace($0) ? $0 : nil }
    }

    /// When to set off: the travel time and a margin before the start, rounded down to five minutes.
    static func leaveBy(start: Date, travel: TimeInterval, margin: TimeInterval = 5 * 60, calendar: Calendar) -> Date {
        let raw = start.addingTimeInterval(-travel - margin)
        let minute = calendar.component(.minute, from: raw)
        let second = calendar.component(.second, from: raw)
        return raw.addingTimeInterval(-Double((minute % 5) * 60 + second))
    }

    /// "18 min", "1 hr 5 min"
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// The notch's nudge: from ten minutes before you need to leave until the event starts.
    static func nudge(now: Date, leaveBy: Date, start: Date) -> Bool {
        now >= leaveBy.addingTimeInterval(-10 * 60) && now < start
    }
}

// MARK: - Calendar sets

/// Calendars shown together, like "Work" or "Home", to switch between in one click.
struct CalendarSet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// The calendars it shows.
    var shown: [String]
}

enum CalendarSets {
    /// Everything not in the set is hidden. Calendars that weren't there when the set was made stay as they were.
    static func hidden(applying set: CalendarSet, all: [String], current: Set<String>, known: Set<String>? = nil) -> Set<String> {
        var result = current
        for id in all {
            if set.shown.contains(id) {
                result.remove(id)
            } else if known.map({ $0.contains(id) }) ?? true {
                result.insert(id)
            }
        }
        return result
    }

    /// The set that matches what's showing, if one does.
    static func active(_ sets: [CalendarSet], hidden: Set<String>, all: [String]) -> CalendarSet? {
        let showing = Set(all.filter { !hidden.contains($0) })
        return sets.first { Set($0.shown).intersection(all) == showing }
    }
}

// MARK: - Week numbers

extension Calendar {
    /// The ISO 8601 week number (weeks start on Monday; week 1 holds the year's first Thursday).
    func isoWeek(of date: Date) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        return iso.component(.weekOfYear, from: date)
    }
}

// MARK: - Room between meetings

enum Buffers {
    /// Meetings that run into each other with less than `minutes` between them (clashes are flagged separately).
    static func tight(_ events: [CalEvent], minutes: Int) -> [(CalEvent, CalEvent)] {
        guard minutes > 0 else { return [] }
        let timed = events.filter { !$0.isAllDay && $0.response != .declined }.sorted { $0.start < $1.start }
        var pairs: [(CalEvent, CalEvent)] = []
        for (first, second) in zip(timed, timed.dropFirst()) {
            let gap = second.start.timeIntervalSince(first.end)
            if gap >= 0, gap < Double(minutes) * 60 { pairs.append((first, second)) }
        }
        return pairs
    }

    /// The busy events stretched by the buffer either side, for finding free time that leaves room.
    static func padded(_ events: [CalEvent], minutes: Int) -> [CalEvent] {
        guard minutes > 0 else { return events }
        return events.map { event in
            guard !event.isAllDay else { return event }
            var padded = event
            padded.start = event.start.addingTimeInterval(-Double(minutes) * 60)
            padded.end = event.end.addingTimeInterval(Double(minutes) * 60)
            return padded
        }
    }
}

// MARK: - Repeats and alerts

enum EventRepeat: String, CaseIterable, Identifiable, Codable, Sendable {
    case never, daily, weekdays, weekly, fortnightly, monthly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .fortnightly: return "Every fortnight"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }

    /// Microsoft Graph's recurrence for an event starting on `start`, until `until` (or with no end).
    func graph(start: Date, until: Date?, calendar: Calendar) -> [String: Any]? {
        guard self != .never else { return nil }
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let weekday = names[calendar.component(.weekday, from: start) - 1]
        var pattern: [String: Any]
        switch self {
        case .never: return nil
        case .daily: pattern = ["type": "daily", "interval": 1]
        case .weekdays: pattern = ["type": "weekly", "interval": 1, "daysOfWeek": Array(names[1...5])]
        case .weekly: pattern = ["type": "weekly", "interval": 1, "daysOfWeek": [weekday]]
        case .fortnightly: pattern = ["type": "weekly", "interval": 2, "daysOfWeek": [weekday]]
        case .monthly: pattern = ["type": "absoluteMonthly", "interval": 1, "dayOfMonth": calendar.component(.day, from: start)]
        case .yearly:
            pattern = ["type": "absoluteYearly", "interval": 1, "dayOfMonth": calendar.component(.day, from: start),
                       "month": calendar.component(.month, from: start)]
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var range: [String: Any] = ["startDate": formatter.string(from: start), "recurrenceTimeZone": calendar.timeZone.identifier]
        if let until {
            range["type"] = "endDate"
            range["endDate"] = formatter.string(from: until)
        } else {
            range["type"] = "noEnd"
        }
        return ["pattern": pattern, "range": range]
    }
}

/// How long before an event to be reminded.
enum EventAlert {
    static let choices: [Int?] = [nil, 0, 5, 10, 15, 30, 60, 120, 1_440]

    static func title(_ minutes: Int?) -> String {
        guard let minutes else { return "None" }
        switch minutes {
        case 0: return "When it starts"
        case 1_440: return "A day before"
        case let hours where hours >= 60 && hours % 60 == 0: return "\(hours / 60) \(hours == 60 ? "hour" : "hours") before"
        default: return "\(minutes) minutes before"
        }
    }
}
