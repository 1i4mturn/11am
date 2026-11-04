import Foundation

// Energy: a small daily summary of Apple Health, made on the iPhone and shared only with your own Mac.
// Everything compares you with yourself; there are no scores and no medical claims.

/// One day of Health, summarised. Sleep counts for the day you woke up.
struct DayEnergy: Codable, Hashable, Identifiable, Sendable {
    /// yyyy-MM-dd in the phone's time zone.
    var day: String
    var sleepMinutes: Double?
    var bedtime: Date?
    var wakeTime: Date?
    var steps: Double?
    /// Kilocalories.
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var standHours: Double?
    /// Beats a minute.
    var restingHeartRate: Double?
    /// Heart-rate variability (SDNN), milliseconds.
    var heartRateVariability: Double?
    var workouts: [EnergyWorkout] = []

    var id: String { day }

    var date: Date? { EnergyDay.date(day) }

    var isEmpty: Bool {
        sleepMinutes == nil && steps == nil && activeEnergy == nil && exerciseMinutes == nil
            && restingHeartRate == nil && heartRateVariability == nil && workouts.isEmpty
    }
}

struct EnergyWorkout: Codable, Hashable, Sendable {
    var kind: String
    var minutes: Double
    /// Kilocalories, when Health has them.
    var energy: Double?
}

enum EnergyDay {
    static func formatter(_ calendar: Calendar = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: date)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        formatter(calendar).date(from: key)
    }

    /// Minutes after noon, so bedtimes either side of midnight average sensibly.
    static func minutesAfterNoon(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return (minutes - 720 + 1_440).truncatingRemainder(dividingBy: 1_440)
    }

    /// Merges days by date, newer values winning, oldest first.
    static func merge(_ old: [DayEnergy], _ new: [DayEnergy]) -> [DayEnergy] {
        var byDay = Dictionary(old.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        for day in new { byDay[day.day] = day }
        return byDay.values.sorted { $0.day < $1.day }
    }
}

/// Your usual, from the days you give it (normally the few weeks before today).
struct EnergyBaseline: Hashable, Sendable {
    var sleepMinutes: Double?
    /// Average bedtime, in minutes after noon.
    var bedtime: Double?
    /// How much bedtime moves about, in minutes (lower is steadier).
    var bedtimeSpread: Double?
    var steps: Double?
    var exerciseMinutes: Double?
    var restingHeartRate: Double?
    var heartRateVariability: Double?
    /// Nights with sleep in the average.
    var nights: Int

    init(_ days: [DayEnergy], calendar: Calendar = .current) {
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        let sleeps = days.compactMap(\.sleepMinutes).filter { $0 > 60 }
        sleepMinutes = mean(sleeps)
        nights = sleeps.count
        let bedtimes = days.compactMap(\.bedtime).map { EnergyDay.minutesAfterNoon($0, calendar: calendar) }
        bedtime = mean(bedtimes)
        if let average = bedtime, bedtimes.count >= 3 {
            bedtimeSpread = (bedtimes.map { ($0 - average) * ($0 - average) }.reduce(0, +) / Double(bedtimes.count)).squareRoot()
        }
        steps = mean(days.compactMap(\.steps))
        exerciseMinutes = mean(days.compactMap(\.exerciseMinutes))
        restingHeartRate = mean(days.compactMap(\.restingHeartRate))
        heartRateVariability = mean(days.compactMap(\.heartRateVariability))
    }
}

enum EnergyFormat {
    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let hours = total / 60, rest = total % 60
        if hours == 0 { return "\(rest) m" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) m"
    }

    static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// A time of day from minutes after noon.
    static func clock(minutesAfterNoon: Double) -> String {
        let minutes = (Int(minutesAfterNoon.rounded()) + 720) % 1_440
        let hour = minutes / 60, minute = minutes % 60
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", twelve, minute, hour < 12 ? "am" : "pm")
    }

    /// "about an hour", "40 minutes", for gaps between you and your usual.
    static func gap(_ minutes: Double) -> String {
        let value = abs(minutes)
        if value < 50 { return "\(Int((value / 5).rounded() * 5)) minutes" }
        if value < 75 { return "about an hour" }
        let halves = (value / 30).rounded() / 2
        return halves == halves.rounded() ? "about \(Int(halves)) hours" : String(format: "about %.1f hours", halves)
    }
}

/// What today's numbers mean for the day, in plain words.
enum EnergyInsight {
    enum Tone: String, Codable, Sendable { case good, usual, easy }

    struct Reading: Hashable, Sendable {
        var tone: Tone
        var headline: String
        var detail: String
        var suggestions: [String]
    }

    /// Reads last night (`today`) and yesterday's movement against your usual.
    static func reading(today: DayEnergy?, yesterday: DayEnergy?, baseline: EnergyBaseline) -> Reading? {
        var tone = Tone.usual
        var headline = ""
        var detail = ""
        var suggestions: [String] = []

        if let sleep = today?.sleepMinutes {
            let usual = baseline.nights >= 3 ? baseline.sleepMinutes : nil
            if sleep < 360 || (usual.map { sleep < $0 - 45 } ?? false) {
                tone = .easy
                headline = "Short night"
                detail = "\(EnergyFormat.duration(sleep)) asleep" + (usual.map { ", \(EnergyFormat.gap($0 - sleep)) less than your usual \(EnergyFormat.duration($0))." } ?? ".")
                suggestions.append("Put the hardest work after 10, when you've woken up properly.")
                suggestions.append("Keep the afternoon light and the evening early.")
            } else if let usual, sleep >= usual + 30, sleep >= 420 {
                tone = .good
                headline = "Good night's sleep"
                detail = "\(EnergyFormat.duration(sleep)) asleep, more than your usual \(EnergyFormat.duration(usual))."
                suggestions.append("A good day to do the hard thing first.")
            } else {
                headline = "Usual night"
                detail = "\(EnergyFormat.duration(sleep)) asleep" + (usual.map { ", close to your usual \(EnergyFormat.duration($0))." } ?? ".")
            }
            if let bed = today?.bedtime, let usualBed = baseline.bedtime, baseline.nights >= 3 {
                let late = EnergyDay.minutesAfterNoon(bed) - usualBed
                if late > 75 { detail += " Later to bed than usual." }
            }
        }

        if let resting = today?.restingHeartRate, let usualResting = baseline.restingHeartRate,
           let variability = today?.heartRateVariability, let usualVariability = baseline.heartRateVariability,
           resting >= usualResting + 4, variability <= usualVariability * 0.8 {
            tone = .easy
            if headline.isEmpty { headline = "Go easy today" }
            let drop = Int(((1 - variability / usualVariability) * 100).rounded())
            detail += (detail.isEmpty ? "" : " ") + "Your body's working harder than usual: resting heart rate \(Int(resting.rounded())) against your \(Int(usualResting.rounded())), heart-rate variability \(drop)% lower."
            suggestions.append("Fit a walk between meetings and go to bed a little earlier.")
        }

        if let steps = yesterday?.steps, let usualSteps = baseline.steps, usualSteps > 0, steps < usualSteps * 0.5 {
            suggestions.append("Yesterday was quiet on your feet (\(EnergyFormat.number(steps)) steps); a walk at lunch would help.")
        }

        guard !headline.isEmpty || !suggestions.isEmpty else { return nil }
        if headline.isEmpty { headline = "Move a little more" }
        return Reading(tone: tone, headline: headline, detail: detail.trimmingCharacters(in: .whitespaces), suggestions: suggestions)
    }

    /// Facts for Leo's brief. Plain numbers against your usual; Leo decides what to say.
    static func briefFacts(today: DayEnergy?, yesterday: DayEnergy?, baseline: EnergyBaseline) -> String? {
        var facts: [String] = []
        if let sleep = today?.sleepMinutes {
            facts.append("Slept \(EnergyFormat.duration(sleep))" + (baseline.sleepMinutes.map { " (usual \(EnergyFormat.duration($0)))" } ?? ""))
        }
        if let resting = today?.restingHeartRate {
            facts.append("resting heart rate \(Int(resting.rounded()))" + (baseline.restingHeartRate.map { " (usual \(Int($0.rounded())))" } ?? ""))
        }
        if let variability = today?.heartRateVariability {
            facts.append("heart-rate variability \(Int(variability.rounded())) ms" + (baseline.heartRateVariability.map { " (usual \(Int($0.rounded())))" } ?? ""))
        }
        if let steps = yesterday?.steps {
            facts.append("\(EnergyFormat.number(steps)) steps yesterday" + (baseline.steps.map { " (usual \(EnergyFormat.number($0)))" } ?? ""))
        }
        guard !facts.isEmpty else { return nil }
        var text = facts.joined(separator: ", ") + "."
        if let reading = reading(today: today, yesterday: yesterday, baseline: baseline) {
            text += " \(reading.headline)." + (reading.suggestions.first.map { " Suggestion: \($0)" } ?? "")
        }
        return text
    }

    /// Today's reading from a run of days (oldest first), using the four weeks before today as your usual.
    static func latest(_ days: [DayEnergy], today: Date = Date(), calendar: Calendar = .current) -> (today: DayEnergy?, yesterday: DayEnergy?, baseline: EnergyBaseline) {
        let todayKey = EnergyDay.key(today, calendar: calendar)
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: today).map { EnergyDay.key($0, calendar: calendar) } ?? ""
        let monthAgo = calendar.date(byAdding: .day, value: -28, to: today).map { EnergyDay.key($0, calendar: calendar) } ?? ""
        let history = days.filter { $0.day < todayKey && $0.day >= monthAgo }
        return (days.first { $0.day == todayKey }, days.first { $0.day == yesterdayKey }, EnergyBaseline(history, calendar: calendar))
    }
}

/// Believable made-up days for trying Energy without Health data (on a Mac, in the simulator, or before you allow it).
enum EnergySample {
    static func days(_ count: Int = 28, ending end: Date = Date(), calendar: Calendar = .current) -> [DayEnergy] {
        var seed: UInt64 = 0x11A3
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        var days: [DayEnergy] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: end)) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let weekend = weekday == 1 || weekday == 7
            var sleep = 420 + (random() - 0.5) * 60 + (weekend ? 35 : 0)
            var resting = 56 + (random() - 0.5) * 4
            var variability = 48 + (random() - 0.5) * 12
            // Last night was short, and the body shows it, so the sample has something to say.
            if offset == 0 {
                sleep = 340
                resting = 62
                variability = 35
            }
            let usualBed = 23.0 * 60 + 10 + (random() - 0.5) * 50 + (weekend ? 40 : 0)
            // Last night: in bed at half past one.
            let bedMinutes = offset == 0 ? 24.0 * 60 + 90 : usualBed
            let bedtime = calendar.date(byAdding: .minute, value: Int(bedMinutes) - 24 * 60, to: date)
            let wake = bedtime.map { $0.addingTimeInterval(sleep * 60 + 20 * 60) }
            let steps = offset == 1 ? 3_150 : 7_500 + (random() - 0.4) * 5_000 + (weekend ? 2_000 : 0)
            var workouts: [EnergyWorkout] = []
            if weekday == 3 || weekday == 5 { workouts.append(EnergyWorkout(kind: "Run", minutes: 32 + random() * 10, energy: 310 + random() * 60)) }
            if weekday == 7 { workouts.append(EnergyWorkout(kind: "Cycling", minutes: 60 + random() * 30, energy: 520 + random() * 120)) }
            days.append(DayEnergy(
                day: EnergyDay.key(date, calendar: calendar),
                sleepMinutes: sleep.rounded(),
                bedtime: bedtime,
                wakeTime: wake,
                steps: offset == 0 ? 1_840 : steps.rounded(),
                activeEnergy: (offset == 0 ? 120 : 380 + random() * 260).rounded(),
                exerciseMinutes: (offset == 0 ? 4 : 18 + random() * 30 + workouts.reduce(0) { $0 + $1.minutes }).rounded(),
                standHours: offset == 0 ? 3 : (9 + random() * 4).rounded(),
                restingHeartRate: resting.rounded(),
                heartRateVariability: variability.rounded(),
                workouts: workouts
            ))
        }
        return days
    }
}
