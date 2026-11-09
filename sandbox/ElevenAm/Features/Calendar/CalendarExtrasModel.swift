import CoreLocation
import EventKit
import Foundation
import MapKit

/// How long it takes to get to an event, from where, and when to set off.
struct TravelInfo: Equatable {
    var from: String
    var seconds: TimeInterval
    var leaveBy: Date
}

extension CalendarModel {
    // MARK: Weather

    /// The forecast for the next fortnight, at most once an hour (or straight away when asked).
    func refreshWeather(force: Bool = false) {
        guard showsWeather else {
            weather = [:]
            return
        }
        if !force, let fetched = weatherFetched, Date().timeIntervalSince(fetched) < 3_600 { return }
        weatherFetched = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            var place = self.weatherPlace
            if place == nil, let city = Weather.city(from: .current) { place = await Self.findPlace(city) }
            guard let place, let url = Weather.forecastURL(place),
                  let answer = try? await URLSession.shared.data(from: url) else { return }
            if self.weatherPlace == nil { self.weatherPlace = place }
            let days = Weather.parse(answer.0, calendar: .current)
            guard !days.isEmpty else { return }
            self.weather = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    nonisolated static func findPlace(_ name: String) async -> WeatherPlace? {
        guard let url = Weather.placeURL(name), let answer = try? await URLSession.shared.data(from: url) else { return nil }
        return Weather.parsePlace(answer.0)
    }

    /// Weather for another town or city.
    func setWeatherCity(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let place = await Self.findPlace(clean) else {
                self?.notice = "Leo couldn't find \u{201C}\(clean)\u{201D}. Try the nearest city."
                return
            }
            self?.weatherPlace = place
            JSONStore.save(place, to: "calendar-weather-place")
            self?.travelCache = [:]
            self?.refreshWeather(force: true)
        }
    }

    func weather(on day: Date) -> DayWeather? { showsWeather ? weather[Calendar.current.startOfDay(for: day)] : nil }

    // MARK: Travel

    /// Travel times for what's coming up in the next day and a half that happens somewhere, from where you'll be before.
    func refreshTravel() {
        let now = Date()
        let calendar = Calendar.current
        let upcoming = events.filter { event in
            !event.isAllDay && event.response != .declined && Travel.isPlace(event.location)
                && (isSample || (event.start > now && event.start < now.addingTimeInterval(36 * 3_600)))
        }
        guard !upcoming.isEmpty else { return }
        let all = events
        let start = home.isEmpty ? nil : home
        Task { @MainActor [weak self] in
            guard let self else { return }
            var found: [String: TravelInfo] = [:]
            for event in upcoming.prefix(12) {
                guard let place = event.location else { continue }
                let from = Travel.origin(for: event, in: all, home: start ?? (self.isSample ? "Home" : nil), calendar: calendar)
                guard let from, from.caseInsensitiveCompare(place) != .orderedSame else { continue }
                let key = from.lowercased() + "→" + place.lowercased()
                var seconds = self.travelCache[key]
                if seconds == nil {
                    seconds = self.isSample ? Self.sampleTravel(from, place) : await self.estimate(from: from, to: place)
                    self.travelCache[key] = seconds ?? -1
                }
                guard let seconds, seconds > 0 else { continue }
                found[event.id] = TravelInfo(from: from, seconds: seconds, leaveBy: Travel.leaveBy(start: event.start, travel: seconds, calendar: calendar))
            }
            self.travel = found
            self.onToday?(self.isSample ? nil : self.events(on: Date()))
        }
    }

    /// Driving time from Apple Maps, with both places looked up near your weather town.
    private func estimate(from: String, to: String) async -> TimeInterval? {
        let region = weatherPlace.map { CLCircularRegion(center: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), radius: 60_000, identifier: "near") }
        guard let origin = try? await CLGeocoder().geocodeAddressString(from, in: region).first,
              let destination = try? await CLGeocoder().geocodeAddressString(to, in: region).first else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(placemark: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(placemark: destination))
        request.transportType = .automobile
        guard let response = try? await MKDirections(request: request).calculateETA() else { return nil }
        // A place found in the wrong city gives a silly answer; better none.
        return response.expectedTravelTime < 4 * 3_600 ? response.expectedTravelTime : nil
    }

    /// The sample week's made-up travel: somewhere between 10 and 25 minutes, the same each time.
    private static func sampleTravel(_ from: String, _ to: String) -> TimeInterval {
        let value = (from + to).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(10 + value % 16) * 60
    }

    // MARK: Calendar sets

    /// What's showing now, kept as a set to come back to.
    func saveCurrentAsSet(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let shown = calendars.filter { $0.source != .holidays && !hidden.contains($0.id) }.map(\.id)
        sets.removeAll { $0.name.caseInsensitiveCompare(clean) == .orderedSame }
        sets.append(CalendarSet(name: clean, shown: shown))
        JSONStore.save(sets, to: "calendar-sets")
    }

    func deleteSet(_ id: UUID) {
        sets.removeAll { $0.id == id }
        JSONStore.save(sets, to: "calendar-sets")
    }

    var activeSet: CalendarSet? {
        CalendarSets.active(sets, hidden: hidden, all: calendars.filter { $0.source != .holidays }.map(\.id))
    }

    // MARK: Room between meetings

    /// The meetings right before and after this one with less than your buffer between.
    func tightNeighbours(of event: CalEvent) -> (before: CalEvent?, after: CalEvent?) {
        guard bufferMinutes > 0, !event.isAllDay else { return (nil, nil) }
        let pairs = Buffers.tight(events(on: event.start), minutes: bufferMinutes)
        return (pairs.first { $0.1.id == event.id }?.0, pairs.first { $0.0.id == event.id }?.1)
    }

    // MARK: Repeats

    static func rule(_ repeats: EventRepeat, until: Date?) -> EKRecurrenceRule? {
        let end = until.map { EKRecurrenceEnd(end: $0) }
        switch repeats {
        case .never: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: end)
        case .weekdays:
            let days = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map { EKRecurrenceDayOfWeek($0) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil, monthsOfTheYear: nil,
                                    weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: end)
        case .fortnightly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: end)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: end)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: end)
        }
    }

    // MARK: Samples

    /// For screenshots: a week of weather, a buffer, week numbers and two sets, with lunch selected.
    func loadExtrasSample() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: visibleRange.start)
        let codes = [1, 2, 80, 3, 0, 61, 1, 2, 0, 3, 80, 1, 0, 2]
        var sample: [Date: DayWeather] = [:]
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let high = [24, 26, 21, 23, 28, 19, 22, 25, 27, 22, 20, 24, 29, 26][offset]
            sample[day] = DayWeather(day: day, code: codes[offset], high: Double(high), low: Double(high - 8), rain: [10, 20, 70, 30, 0, 80, 10, 20, 0, 30, 60, 10, 0, 20][offset])
        }
        weatherFetched = Date()
        weatherPlace = WeatherPlace(name: "Sydney", latitude: -33.87, longitude: 151.21, country: "Australia")
        weather = sample
        bufferMinutes = 10
        showsWeekNumbers = true
        // Only for this run: the next launch starts as you left it.
        UserDefaults.standard.removeObject(forKey: "calendar.buffer")
        UserDefaults.standard.removeObject(forKey: "calendar.weekNumbers")
        if sets.isEmpty {
            sets = [CalendarSet(name: "Work", shown: [CalendarModel.sampleCalendar.id]), CalendarSet(name: "Home", shown: [])]
        }
        travelCache = [:]
        refreshTravel()
        if let lunch = events.first(where: { $0.id == "sample:lunch" }) {
            show(day: lunch.start, as: mode)
            selectedID = lunch.id
        }
    }
}
