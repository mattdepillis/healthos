//
//  HealthKitManager.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import Foundation
import HealthKit
import Combine

// MARK: - UI models

struct RingsSummary: Identifiable {
    let id = UUID()
    let date: Date

    let move: Double
    let moveGoal: Double

    let exerciseMinutes: Double
    let exerciseGoalMinutes: Double

    let standHours: Double
    let standGoalHours: Double
}

struct WorkoutSummary: Identifiable {
    let id = UUID()
    let type: String
    let start: Date
    let end: Date
    let durationMinutes: Double
    let activeEnergy: Double?
    let distance: Double?
}

// MARK: - HealthKit manager

@MainActor
final class HealthKitManager: ObservableObject {

    private let healthStore = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var isFetching: Bool = false
    @Published var statusText: String = "Not authorized"

    // Rings
    @Published var rings7d: [RingsSummary] = []
    @Published var ringSummaries7d: [HKActivitySummary] = []

    // Snapshot metrics
    @Published var activeEnergyToday: Double? = nil
    @Published var workouts7d: [WorkoutSummary] = []

    // Day-bucketed time series (kept consistent as (date,value) everywhere)
    @Published var sleep7dHours: [(date: Date, value: Double)] = []
    @Published var restingHR7d: [(date: Date, value: Double)] = []
    @Published var hrv7d: [(date: Date, value: Double)] = []
    @Published var distance7dMeters: [(date: Date, value: Double)] = []
    @Published var steps7d: [(date: Date, value: Double)] = []

    // Requests HealthKit read authorization for all data types used by this manager.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "Health data not available on this device."
            return
        }

        // Read types (keep this in sync with queries below)
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let restingHRType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let workoutType = HKObjectType.workoutType()
        let activitySummaryType = HKObjectType.activitySummaryType()

        let toRead: Set<HKObjectType> = [
            stepType,
            activeEnergyType,
            distanceType,
            restingHRType,
            hrvType,
            sleepType,
            workoutType,
            activitySummaryType
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: toRead)
            isAuthorized = true
            statusText = "Authorized ✅"
        } catch {
            isAuthorized = false
            statusText = "Authorization failed: \(error.localizedDescription)"
        }
    }

    // Fetches the “core snapshot” in parallel and publishes everything at once (no partial UI updates).
    func fetchCoreSnapshot() async {
        guard isAuthorized else {
            statusText = "Not authorized. Tap Authorize first."
            return
        }

        isFetching = true
        statusText = "Fetching…"
        await Task.yield() // let SwiftUI paint the loading state immediately
        defer { isFetching = false }

        // Kick off requests in parallel
        async let ringsTask = fetchRings(daysBack: 7)
        async let energyTask = fetchActiveEnergyBurnedToday()
        async let workoutsTask = fetchWorkouts(daysBack: 7)

        async let stepsTask = fetchDailyCumulativeSum(.stepCount, unit: .count(), daysBack: 7)
        async let distanceTask = fetchDailyCumulativeSum(.distanceWalkingRunning, unit: .meter(), daysBack: 7)
        async let sleepTask = fetchSleepHours7d(daysBack: 7)
        async let rhrTask = fetchDailyMostRecentPerDay(.restingHeartRate, unit: .count().unitDivided(by: .minute()), daysBack: 7)
        async let hrvTask = fetchDailyMostRecentPerDay(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), daysBack: 7)

        do {
            let ((ringsPretty, ringsHK),
                 energyVal,
                 workoutsVal,
                 stepsVal,
                 distanceVal,
                 sleepVal,
                 rhrVal,
                 hrvVal) = try await (
                    ringsTask,
                    energyTask,
                    workoutsTask,
                    stepsTask,
                    distanceTask,
                    sleepTask,
                    rhrTask,
                    hrvTask
                 )

            // Publish in one “commit” block
            rings7d = ringsPretty
            ringSummaries7d = ringsHK
            activeEnergyToday = energyVal
            workouts7d = workoutsVal

            steps7d = stepsVal
            distance7dMeters = distanceVal
            sleep7dHours = sleepVal.map { (date: $0.date, value: $0.hours) }
            restingHR7d = rhrVal
            hrv7d = hrvVal

            statusText = "Fetched ✅ (rings \(ringsPretty.count), workouts \(workoutsVal.count))"
        } catch {
            statusText = "Fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    // Returns an inclusive day-bucketed date window for "last N days" style queries.
    private func dayRange(daysBack: Int) -> (start: Date, end: Date, cal: Calendar) {
        let cal = Calendar.current
        let end = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack + 1, to: end)!)
        return (start, end, cal)
    }

    // Fetches a per-day time series for quantity types that are meaningful as daily totals (steps, distance, etc).
    private func fetchDailyCumulativeSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        daysBack: Int
    ) async throws -> [(date: Date, value: Double)] {
        let (start, end, cal) = dayRange(daysBack: daysBack)
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!

        var interval = DateComponents()
        interval.day = 1

        let anchor = cal.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: anchor,
                intervalComponents: interval
            )

            q.initialResultsHandler = { _, results, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let results = results else { cont.resume(returning: []); return }

                var out: [(Date, Double)] = []
                results.enumerateStatistics(from: start, to: end) { stats, _ in
                    let day = cal.startOfDay(for: stats.startDate)
                    let value = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                    out.append((day, value))
                }
                cont.resume(returning: out.sorted { $0.0 < $1.0 }.map { (date: $0.0, value: $0.1) })
            }

            self.healthStore.execute(q)
        }
    }

    // Fetches one value per day: the most recent sample that day (good for RHR, HRV).
    // Missing days return 0.0 to keep charting simple (switch to Double? if you want gaps).
    private func fetchDailyMostRecentPerDay(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        daysBack: Int
    ) async throws -> [(date: Date, value: Double)] {
        let (start, end, cal) = dayRange(daysBack: daysBack)
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(q)
        }

        var latestByDay: [Date: HKQuantitySample] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.endDate)
            if let existing = latestByDay[day] {
                if s.endDate > existing.endDate { latestByDay[day] = s }
            } else {
                latestByDay[day] = s
            }
        }

        var out: [(date: Date, value: Double)] = []
        out.reserveCapacity(daysBack)

        let firstDay = cal.startOfDay(for: start)
        for i in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
            if let s = latestByDay[day] {
                out.append((date: day, value: s.quantity.doubleValue(for: unit)))
            } else {
                out.append((date: day, value: 0.0))
            }
        }

        return out
    }

    // MARK: - Rings (Activity Summary)

    // Fetches Activity ring summaries (move/exercise/stand) for each day in the last N days.
    private func fetchRings(daysBack: Int) async throws -> ([RingsSummary], [HKActivitySummary]) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        var allPretty: [RingsSummary] = []
        var allHK: [HKActivitySummary] = []

        for offset in 0..<daysBack {
            guard let date = cal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.calendar = cal

            let predicate = HKQuery.predicateForActivitySummary(with: comps)

            let summaries: [HKActivitySummary] = try await withCheckedThrowingContinuation { cont in
                let q = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                    if let error = error { cont.resume(throwing: error); return }
                    cont.resume(returning: summaries ?? [])
                }
                self.healthStore.execute(q)
            }

            allHK.append(contentsOf: summaries)

            let mapped = summaries.compactMap { s -> RingsSummary? in
                guard let d = cal.date(from: s.dateComponents(for: cal)) else { return nil }
                return RingsSummary(
                    date: d,
                    move: s.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal: s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: s.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoalMinutes: s.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    standHours: s.appleStandHours.doubleValue(for: .count()),
                    standGoalHours: s.appleStandHoursGoal.doubleValue(for: .count())
                )
            }

            allPretty.append(contentsOf: mapped)
        }

        allPretty.sort { $0.date < $1.date }
        allHK.sort {
            let d0 = cal.date(from: $0.dateComponents(for: cal)) ?? .distantPast
            let d1 = cal.date(from: $1.dateComponents(for: cal)) ?? .distantPast
            return d0 < d1
        }
        return (allPretty, allHK)
    }

    // MARK: - Active energy today

    // Fetches today's active energy burned (kcal) as a cumulative sum from start-of-day to now.
    private func fetchActiveEnergyBurnedToday() async throws -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = Date()

        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: [.cumulativeSum]) { _, stats, error in
                if let error = error { cont.resume(throwing: error); return }
                let sum = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
                cont.resume(returning: sum)
            }
            self.healthStore.execute(q)
        }
    }

    // MARK: - Workouts last N days

    // Fetches workouts in the last N days and maps them into a simplified summary model for display.
    private func fetchWorkouts(daysBack: Int) async throws -> [WorkoutSummary] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(TimeInterval(-86400 * daysBack)))
        let end = Date()

        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: 100,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }

                let workouts = (samples as? [HKWorkout] ?? []).map { (w: HKWorkout) -> WorkoutSummary in
                    let typeName = w.workoutActivityType.name
                    let durationMin = w.duration / 60.0

                    let energy: Double?
                    if #available(iOS 18.0, *) {
                        let activeEnergyType = HKQuantityType(.activeEnergyBurned)
                        energy = w.statistics(for: activeEnergyType)?
                            .sumQuantity()?
                            .doubleValue(for: .kilocalorie())
                    } else {
                        energy = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    }

                    let distance = w.totalDistance?.doubleValue(for: .meter()) // meters for now

                    return WorkoutSummary(
                        type: typeName,
                        start: w.startDate,
                        end: w.endDate,
                        durationMinutes: durationMin,
                        activeEnergy: energy,
                        distance: distance
                    )
                }

                cont.resume(returning: workouts)
            }
            self.healthStore.execute(q)
        }
    }

    // MARK: - Sleep

    // Fetches total "asleep" time per day (hours) for the last N days (simple v1 aggregation).
    // NOTE: This groups by sample.startDate's day; if you want “sleep belongs to wake-up day” we can refine later.
    private func fetchSleepHours7d(daysBack: Int) async throws -> [(date: Date, hours: Double)] {
        let (start, end, cal) = dayRange(daysBack: daysBack)
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            self.healthStore.execute(q)
        }

        var totals: [Date: TimeInterval] = [:]
        for s in samples where asleepValues.contains(s.value) {
            let day = cal.startOfDay(for: s.startDate)
            totals[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }

        var out: [(date: Date, hours: Double)] = []
        out.reserveCapacity(daysBack)

        let firstDay = cal.startOfDay(for: start)
        for i in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
            let hours = (totals[day] ?? 0) / 3600.0
            out.append((date: day, hours: hours))
        }

        return out
    }
}

// MARK: - Helper for activity type names

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .traditionalStrengthTraining: return "Strength Training"
        case .cycling: return "Cycling"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        default: return self.rawValue.description
        }
    }
}

