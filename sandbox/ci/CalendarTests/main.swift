import Foundation

// Checks Leo's calendar extras: the forecast read from Open-Meteo, where you travel from and when to leave, sets of
// calendars, ISO week numbers, room between meetings, and repeats and alerts as Outlook wants them.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func same<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("PASS", name)
    } else {
        print("FAIL", name, "· expected", expected, "· got", actual)
        failures += 1
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
func event(_ id: String, _ start: Date, _ minutes: Int, _ location: String?) -> CalEvent {
    CalEvent(id: id, calendarID: "c", source: .sample, title: id, start: start, end: start.addingTimeInterval(Double(minutes) * 60), location: location)
}

// MARK: Weather

let forecast = """
{"daily":{"time":["2026-11-09","2026-11-10","2026-11-11"],"weather_code":[0,80,95],
"temperature_2m_max":[24.4,19.6,27.1],"temperature_2m_min":[15.2,14.9,null],"precipitation_probability_max":[5,70,null]}}
"""
let days = Weather.parse(Data(forecast.utf8), calendar: calendar)
same(days.count, 2, "weather: a day with no low is left out")
same(days.first?.day, calendar.startOfDay(for: at(2026, 11, 9, 12)), "weather: each at the start of its day")
same(days.first?.short, "24°", "weather: the high, rounded")
same(days.first?.line, "Sunny, 15–24°", "weather: no rain mentioned under 20%")
same(days.last?.line, "Showers, 15–20°, 70% chance of rain", "weather: showers with the chance of rain")
same(Weather.symbol(95), "cloud.bolt.rain", "weather: storms")
same(Weather.parse(Data("{}".utf8), calendar: calendar).count, 0, "weather: nothing from an empty answer")
let place = Weather.parsePlace(Data(#"{"results":[{"name":"Newcastle","latitude":-32.93,"longitude":151.78,"country":"Australia"}]}"#.utf8))
same(place?.name, "Newcastle", "weather: a town found")
same(Weather.parsePlace(Data(#"{"generationtime_ms":0.2}"#.utf8)), nil, "weather: no town, nothing found")
same(Weather.city(from: TimeZone(identifier: "America/New_York")!), "New York", "weather: a city from the time zone")
let url = place.flatMap { Weather.forecastURL($0) }?.absoluteString ?? ""
check(url.contains("latitude=-32.930") && url.contains("forecast_days=14") && url.contains("timezone=auto"), "weather: the forecast address")

// MARK: Travel

check(Travel.isPlace("Lune") && !Travel.isPlace("https://zoom.us/j/1") && !Travel.isPlace("Microsoft Teams Meeting") && !Travel.isPlace("  "),
      "travel: places, not video calls")
let dinner = event("dinner", at(2026, 11, 9, 19), 120, "Mum's")
let dentist = event("dentist", at(2026, 11, 10, 9, 45), 30, "Surry Hills Dental")
let call = event("call", at(2026, 11, 10, 10), 30, "https://zoom.us/j/1")
let lunch = event("lunch", at(2026, 11, 10, 12, 30), 60, "Lune")
let late = event("late", at(2026, 11, 10, 17), 30, "Studio")
let day = [dinner, dentist, call, lunch, late]
same(Travel.origin(for: lunch, in: day, home: "Paddington", calendar: calendar), "Surry Hills Dental", "travel: from the last place before (not the video call)")
same(Travel.origin(for: dentist, in: day, home: "Paddington", calendar: calendar), "Paddington", "travel: from home first thing (not last night's dinner)")
same(Travel.origin(for: late, in: day, home: nil, calendar: calendar), nil, "travel: more than three hours later, and no home")
same(Travel.leaveBy(start: at(2026, 11, 10, 12, 30), travel: 18 * 60, calendar: calendar), at(2026, 11, 10, 12, 5), "travel: leave by, five minutes to spare, rounded down")
same([Travel.duration(18 * 60), Travel.duration(65 * 60), Travel.duration(120 * 60)], ["18 min", "1 hr 5 min", "2 hr"], "travel: how long, in words")
let leave = at(2026, 11, 10, 12, 5), start = at(2026, 11, 10, 12, 30)
check(Travel.nudge(now: at(2026, 11, 10, 11, 57), leaveBy: leave, start: start) && !Travel.nudge(now: at(2026, 11, 10, 11, 50), leaveBy: leave, start: start)
      && !Travel.nudge(now: start, leaveBy: leave, start: start), "travel: the notch nudges from ten minutes before leaving until it starts")

// MARK: Calendar sets

let all = ["work", "home", "kids"]
let work = CalendarSet(name: "Work", shown: ["work"])
same(CalendarSets.hidden(applying: work, all: all, current: []), ["home", "kids"], "sets: the rest hidden")
same(CalendarSets.hidden(applying: CalendarSet(name: "All", shown: all), all: all, current: ["home"]), [], "sets: everything shown again")
same(CalendarSets.hidden(applying: work, all: all + ["new"], current: [], known: Set(all)), ["home", "kids"], "sets: a calendar added since stays as it was")
same(CalendarSets.active([work], hidden: ["home", "kids"], all: all)?.name, "Work", "sets: the one showing")
same(CalendarSets.active([work], hidden: ["home"], all: all)?.name, nil, "sets: none when what's showing doesn't match")

// MARK: Week numbers

same(calendar.isoWeek(of: at(2026, 11, 9, 12)), 46, "week numbers: 9 November 2026 is week 46")
same(calendar.isoWeek(of: at(2026, 1, 1, 12)), 1, "week numbers: 1 January 2026 (a Thursday) is week 1")
same(calendar.isoWeek(of: at(2027, 1, 1, 12)), 53, "week numbers: 1 January 2027 is still week 53")

// MARK: Room between meetings

let a = event("a", at(2026, 11, 10, 9), 60, nil), b = event("b", at(2026, 11, 10, 10, 5), 30, nil)
let c = event("c", at(2026, 11, 10, 11), 30, nil), d = event("d", at(2026, 11, 10, 11, 15), 30, nil)
same(Buffers.tight([d, c, b, a], minutes: 10).map { $0.0.id + $0.1.id }, ["ab"], "buffers: five minutes is tight, 25 isn't, a clash is a clash")
same(Buffers.tight([a, b], minutes: 0).count, 0, "buffers: none wanted, none flagged")
let padded = Buffers.padded([a], minutes: 10)
same(padded.first.map { [$0.start, $0.end] }, [at(2026, 11, 10, 8, 50), at(2026, 11, 10, 10, 10)], "buffers: busy time stretched either side")
let slots = FreeTime.slots(busy: Buffers.padded([a], minutes: 15), from: at(2026, 11, 10, 0), days: 1, minimum: 30 * 60, calendar: calendar,
                           now: at(2026, 11, 9, 12))
same(slots.first?.start, at(2026, 11, 10, 10, 15), "buffers: free time starts after the buffer")

// MARK: Repeats and alerts

let weekly = EventRepeat.weekly.graph(start: at(2026, 11, 10, 9), until: nil, calendar: calendar)
same((weekly?["pattern"] as? [String: Any])?["daysOfWeek"] as? [String], ["tuesday"], "repeats: weekly on the day it starts")
same((weekly?["range"] as? [String: Any])?["type"] as? String, "noEnd", "repeats: no end")
let fortnight = EventRepeat.fortnightly.graph(start: at(2026, 11, 10, 9), until: at(2027, 2, 1, 12), calendar: calendar)
same((fortnight?["pattern"] as? [String: Any])?["interval"] as? Int, 2, "repeats: every second week")
same((fortnight?["range"] as? [String: Any])?["endDate"] as? String, "2027-02-01", "repeats: until a date")
same((EventRepeat.monthly.graph(start: at(2026, 11, 10, 9), until: nil, calendar: calendar)?["pattern"] as? [String: Any])?["dayOfMonth"] as? Int, 10,
     "repeats: monthly on the same date")
check(EventRepeat.never.graph(start: at(2026, 11, 10, 9), until: nil, calendar: calendar) == nil, "repeats: never is nothing")
same(EventAlert.choices.map { EventAlert.title($0) }, ["None", "When it starts", "5 minutes before", "10 minutes before", "15 minutes before",
                                                      "30 minutes before", "1 hour before", "2 hours before", "A day before"], "alerts: in words")

var fields = MicrosoftCalendar.EventFields(title: "Standup", start: at(2026, 11, 10, 9), end: at(2026, 11, 10, 9, 15), isAllDay: false, location: nil, notes: nil)
fields.repeats = .weekdays
fields.alert = 5
let body = MicrosoftCalendar.body(for: fields, calendar: calendar)
same(((body["recurrence"] as? [String: Any])?["pattern"] as? [String: Any])?["daysOfWeek"] as? [String],
     ["monday", "tuesday", "wednesday", "thursday", "friday"], "outlook: every weekday")
same(body["reminderMinutesBeforeStart"] as? Int, 5, "outlook: the reminder")
let plain = MicrosoftCalendar.body(for: MicrosoftCalendar.EventFields(title: "x", start: at(2026, 11, 10, 9), end: at(2026, 11, 10, 10), isAllDay: false,
                                                                     location: nil, notes: nil), calendar: calendar)
check(plain["recurrence"] == nil && plain["isReminderOn"] == nil, "outlook: nothing sent for repeats or alerts you didn't set")

print(failures == 0 ? "All calendar checks passed." : "\(failures) calendar checks failed.")
exit(failures == 0 ? 0 : 1)
