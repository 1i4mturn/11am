import Foundation
import HealthKit

/// Reads the little that Energy needs from Apple Health. Read only: 11am never writes to Health.
final class HealthReader: @unchecked Sendable {
    enum State: Equatable {
        case unknown, unavailable, allowed
    }

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime),
            HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis), HKCategoryType(.appleStandHour), HKObjectType.workoutType(),
        ]
    }

    /// Health never says whether you allowed reading (that's private), only whether it has asked. Having asked is enough.
    var state: State {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        return UserDefaults.standard.bool(forKey: "health.asked") ? .allowed : .unknown
    }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        UserDefaults.standard.set(true, forKey: "health.asked")
    }

    /// The last `count` days, oldest first.
    func days(_ count: Int, calendar: Calendar = .current) async -> [DayEnergy] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) else { return [] }
        var days: [String: DayEnergy] = [:]
        for offset in 0..<count {
            if let date = calendar.date(byAdding: .day, value: offset, to: start) {
                let key = EnergyDay.key(date, calendar: calendar)
                days[key] = DayEnergy(day: key)
            }
        }

        func fill(_ identifier: HKQuantityTypeIdentifier, _ options: HKStatisticsOptions, unit: HKUnit,
                  _ apply: @escaping (inout DayEnergy, Double) -> Void) async {
            let type = HKQuantityType(identifier)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
            let query = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate), options: options,
                                                              anchorDate: start, intervalComponents: DateComponents(day: 1))
            guard let collection = try? await query.result(for: store) else { return }
            collection.enumerateStatistics(from: start, to: now) { statistics, _ in
                let quantity = options.contains(.cumulativeSum) ? statistics.sumQuantity() : statistics.averageQuantity()
                guard let value = quantity?.doubleValue(for: unit) else { return }
                let key = EnergyDay.key(statistics.startDate, calendar: calendar)
                if var day = days[key] {
                    apply(&day, value)
                    days[key] = day
                }
            }
        }

        await fill(.stepCount, .cumulativeSum, unit: .count()) { $0.steps = $1.rounded() }
        await fill(.activeEnergyBurned, .cumulativeSum, unit: .kilocalorie()) { $0.activeEnergy = $1.rounded() }
        await fill(.appleExerciseTime, .cumulativeSum, unit: .minute()) { $0.exerciseMinutes = $1.rounded() }
        await fill(.restingHeartRate, .discreteAverage, unit: HKUnit.count().unitDivided(by: .minute())) { $0.restingHeartRate = $1.rounded() }
        await fill(.heartRateVariabilitySDNN, .discreteAverage, unit: .secondUnit(with: .milli)) { $0.heartRateVariability = $1.rounded() }

        // Stand hours: hours marked "stood".
        let standPredicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let standQuery = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.appleStandHour), predicate: standPredicate)],
                                                 sortDescriptors: [])
        if let stands = try? await standQuery.result(for: store) {
            for sample in stands where sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
                let key = EnergyDay.key(sample.startDate, calendar: calendar)
                let stood = days[key]?.standHours ?? 0
                days[key]?.standHours = stood + 1
            }
        }

        // Sleep: each night belongs to the day you woke up. Watch and iPhone can both record the same night,
        // so the times asleep are merged before they're added up.
        let sleepStart = start.addingTimeInterval(-12 * 3_600)
        let sleepPredicate = HKQuery.predicateForSamples(withStart: sleepStart, end: now)
        let sleepQuery = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: sleepPredicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        if let samples = try? await sleepQuery.result(for: store) {
            var nights: [String: [DateInterval]] = [:]
            for sample in samples where asleep.contains(sample.value) {
                // Waking before 6pm counts for that day; later sleep (an evening nap) for the next.
                let wakeDay = calendar.component(.hour, from: sample.endDate) < 18
                    ? sample.endDate : (calendar.date(byAdding: .day, value: 1, to: sample.endDate) ?? sample.endDate)
                nights[EnergyDay.key(wakeDay, calendar: calendar), default: []].append(DateInterval(start: sample.startDate, end: sample.endDate))
            }
            for (key, intervals) in nights where days[key] != nil {
                let merged = Self.merge(intervals)
                days[key]?.sleepMinutes = (merged.reduce(0) { $0 + $1.duration } / 60).rounded()
                days[key]?.bedtime = merged.first?.start
                days[key]?.wakeTime = merged.last?.end
            }
        }

        let workoutPredicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let workoutQuery = HKSampleQueryDescriptor(predicates: [.workout(workoutPredicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        if let workouts = try? await workoutQuery.result(for: store) {
            for workout in workouts {
                let key = EnergyDay.key(workout.startDate, calendar: calendar)
                let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                days[key]?.workouts.append(EnergyWorkout(kind: Self.name(workout.workoutActivityType), minutes: (workout.duration / 60).rounded(),
                                                         energy: energy?.rounded()))
            }
        }

        return days.values.filter { !$0.isEmpty }.sorted { $0.day < $1.day }
    }

    /// Overlapping times joined into one.
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    static func name(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Cycling"
        case .swimming: return "Swim"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .tennis: return "Tennis"
        case .soccer: return "Football"
        case .golf: return "Golf"
        case .dance: return "Dance"
        default: return "Workout"
        }
    }
}
