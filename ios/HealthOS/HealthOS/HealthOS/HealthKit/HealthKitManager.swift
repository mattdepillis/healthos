//
//  HealthKitManager.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import Foundation
import HealthKit
import Combine


// MARK: - HealthKit manager

@MainActor
final class HealthKitManager: ObservableObject {

    private let healthStore = HKHealthStore()
    private let dailyWindowDays = 90
    private let workoutsWindowDays = 30

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
    @Published var activeEnergy7dKcal: [(date: Date, value: Double)] = []
    @Published var exerciseMinutes7d: [(date: Date, value: Double)] = []
    @Published var standHours7d: [(date: Date, value: Double)] = []
    @Published var flightsClimbed7d: [(date: Date, value: Double)] = []
    @Published var mindfulMinutes7d: [(date: Date, value: Double)] = []
    @Published var vo2MaxRecent: [(date: Date, value: Double)] = []
    @Published var weight7dLbs: [(date: Date, value: Double)] = []
    @Published var bodyFat7dPct: [(date: Date, value: Double)] = []
    @Published var respiratoryRate7d: [(date: Date, value: Double)] = []
    @Published var bloodOxygen7dPct: [(date: Date, value: Double)] = []
    @Published var sleepStages7d: [SleepStageBreakdown] = []

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
        let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession)!
        let flightsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed)!
        let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max)!
        let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let bodyFatType = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!
        let respiratoryType = HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        let bloodOxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!
        let workoutType = HKObjectType.workoutType()
        let activitySummaryType = HKObjectType.activitySummaryType()

        let toRead: Set<HKObjectType> = [
            stepType,
            activeEnergyType,
            distanceType,
            restingHRType,
            hrvType,
            sleepType,
            mindfulType,
            flightsType,
            vo2Type,
            weightType,
            bodyFatType,
            respiratoryType,
            bloodOxygenType,
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
        async let ringsTask = fetchRings(daysBack: dailyWindowDays)
        async let energyTask = fetchActiveEnergyBurnedToday()
        async let workoutsTask = fetchWorkouts(daysBack: workoutsWindowDays)

        async let stepsTask = fetchDailyCumulativeSum(.stepCount, unit: .count(), daysBack: dailyWindowDays)
        async let distanceTask = fetchDailyCumulativeSum(.distanceWalkingRunning, unit: .meter(), daysBack: dailyWindowDays)
        async let sleepTask = fetchSleepHours7d(daysBack: dailyWindowDays)
        async let rhrTask = fetchDailyMostRecentPerDay(.restingHeartRate, unit: .count().unitDivided(by: .minute()), daysBack: dailyWindowDays)
        async let hrvTask = fetchDailyMostRecentPerDay(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), daysBack: dailyWindowDays)
        async let flightsTask = fetchDailyCumulativeSum(.flightsClimbed, unit: .count(), daysBack: dailyWindowDays)
        async let mindfulTask = fetchDailyCategoryMinutes(.mindfulSession, daysBack: dailyWindowDays)
        async let vo2Task = fetchRecentQuantitySamples(
            .vo2Max,
            unit: HKUnit.literUnit(with: .milli)
                .unitDivided(by: .gramUnit(with: .kilo))
                .unitDivided(by: .minute()),
            daysBack: 180,
            limit: 8
        )
        async let weightTask = fetchDailyMostRecentPerDay(.bodyMass, unit: .pound(), daysBack: dailyWindowDays)
        async let bodyFatTask = fetchDailyMostRecentPerDay(.bodyFatPercentage, unit: .percent(), daysBack: dailyWindowDays)
        async let respiratoryTask = fetchDailyMostRecentPerDay(.respiratoryRate, unit: .count().unitDivided(by: .minute()), daysBack: dailyWindowDays)
        async let bloodOxygenTask = fetchDailyMostRecentPerDay(.oxygenSaturation, unit: .percent(), daysBack: dailyWindowDays)
        async let sleepStagesTask = fetchSleepStageBreakdown(daysBack: dailyWindowDays)

        do {
            let ((ringsPretty, ringsHK),
                 energyVal,
                 workoutsVal,
                 stepsVal,
                 distanceVal,
                 sleepVal,
                 rhrVal,
                 hrvVal,
                 flightsVal,
                 mindfulVal,
                 vo2Val,
                 weightVal,
                 bodyFatVal,
                 respiratoryVal,
                 bloodOxygenVal,
                 sleepStagesVal) = try await (
                    ringsTask,
                    energyTask,
                    workoutsTask,
                    stepsTask,
                    distanceTask,
                    sleepTask,
                    rhrTask,
                    hrvTask,
                    flightsTask,
                    mindfulTask,
                    vo2Task,
                    weightTask,
                    bodyFatTask,
                    respiratoryTask,
                    bloodOxygenTask,
                    sleepStagesTask
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
            flightsClimbed7d = flightsVal
            mindfulMinutes7d = mindfulVal
            vo2MaxRecent = vo2Val
            weight7dLbs = weightVal
            bodyFat7dPct = bodyFatVal
            respiratoryRate7d = respiratoryVal
            bloodOxygen7dPct = bloodOxygenVal
            sleepStages7d = sleepStagesVal

            let activitySeries = buildActivitySeries(from: ringsPretty, daysBack: dailyWindowDays)
            activeEnergy7dKcal = activitySeries.move
            exerciseMinutes7d = activitySeries.exercise
            standHours7d = activitySeries.stand

            statusText = "Fetched ✅ (days \(dailyWindowDays), workouts \(workoutsVal.count))"
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

    private func buildActivitySeries(from rings: [RingsSummary], daysBack: Int)
        -> (move: [(date: Date, value: Double)],
            exercise: [(date: Date, value: Double)],
            stand: [(date: Date, value: Double)]) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let firstDay = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack + 1, to: todayStart)!)

        var byDay: [Date: RingsSummary] = [:]
        for r in rings {
            byDay[cal.startOfDay(for: r.date)] = r
        }

        var move: [(Date, Double)] = []
        var exercise: [(Date, Double)] = []
        var stand: [(Date, Double)] = []

        for i in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
            let r = byDay[day]
            move.append((day, r?.move ?? 0))
            exercise.append((day, r?.exerciseMinutes ?? 0))
            stand.append((day, r?.standHours ?? 0))
        }

        return (move, exercise, stand)
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

    // Fetches total minutes per day for category samples like Mindful Sessions.
    private func fetchDailyCategoryMinutes(
        _ identifier: HKCategoryTypeIdentifier,
        daysBack: Int
    ) async throws -> [(date: Date, value: Double)] {
        let (start, end, cal) = dayRange(daysBack: daysBack)
        let type = HKObjectType.categoryType(forIdentifier: identifier)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

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
        for s in samples {
            let day = cal.startOfDay(for: s.startDate)
            totals[day, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }

        var out: [(date: Date, value: Double)] = []
        out.reserveCapacity(daysBack)

        let firstDay = cal.startOfDay(for: start)
        for i in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
            let minutes = (totals[day] ?? 0) / 60.0
            out.append((date: day, value: minutes))
        }

        return out
    }

    // Fetches recent samples for metrics that are not guaranteed daily (e.g. VO2 Max).
    private func fetchRecentQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        daysBack: Int,
        limit: Int
    ) async throws -> [(date: Date, value: Double)] {
        let (start, end, _) = dayRange(daysBack: daysBack)
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            self.healthStore.execute(q)
        }

        return samples
            .reversed()
            .map { (date: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
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
                    let typeName = w.workoutActivityType.displayName
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

    // Fetches per-day sleep stage totals (hours) for the last N days.
    private func fetchSleepStageBreakdown(daysBack: Int) async throws -> [SleepStageBreakdown] {
        let (start, end, cal) = dayRange(daysBack: daysBack)
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

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

        struct Totals {
            var core: TimeInterval = 0
            var deep: TimeInterval = 0
            var rem: TimeInterval = 0
            var unspecified: TimeInterval = 0
        }

        var totalsByDay: [Date: Totals] = [:]
        for s in samples {
            let day = cal.startOfDay(for: s.startDate)
            let duration = s.endDate.timeIntervalSince(s.startDate)
            var totals = totalsByDay[day] ?? Totals()

            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                totals.core += duration
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                totals.deep += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                totals.rem += duration
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                totals.unspecified += duration
            default:
                break
            }

            totalsByDay[day] = totals
        }

        var out: [SleepStageBreakdown] = []
        out.reserveCapacity(daysBack)

        let firstDay = cal.startOfDay(for: start)
        for i in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: i, to: firstDay) else { continue }
            let totals = totalsByDay[day] ?? Totals()
            out.append(
                SleepStageBreakdown(
                    date: day,
                    coreHours: totals.core / 3600.0,
                    deepHours: totals.deep / 3600.0,
                    remHours: totals.rem / 3600.0,
                    unspecifiedHours: totals.unspecified / 3600.0
                )
            )
        }

        return out
    }
}

// MARK: - Helper for activity type names

//private extension HKWorkoutActivityType {
//    var name: String {
//        switch self {
//        case .running: return "Running"
//        case .walking: return "Walking"
//        case .traditionalStrengthTraining: return "Strength Training"
//        case .cycling: return "Cycling"
//        case .yoga: return "Yoga"
//        case .hiking: return "Hiking"
//        case .swimming: return "Swimming"
//        default: return self.rawValue.description
//        }
//    }
//}
