//
//  HealthKitManager.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import Foundation
import HealthKit
import Combine

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

@MainActor
final class HealthKitManager: ObservableObject {

    private let healthStore = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var statusText: String = "Not authorized"
    @Published var rings7d: [RingsSummary] = []
    @Published var activeEnergyToday: Double? = nil
    @Published var workouts7d: [WorkoutSummary] = []

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "Health data not available on this device."
            return
        }

        // Read types
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let workoutType = HKObjectType.workoutType()
        let activitySummaryType = HKObjectType.activitySummaryType()

        let toRead: Set<HKObjectType> = [
            stepType,
            activeEnergyType,
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

    func fetchCoreSnapshot() async {
        guard isAuthorized else {
            statusText = "Not authorized. Tap Authorize first."
            return
        }

        statusText = "Fetching…"

        async let rings = fetchRings(daysBack: 7)
        async let energy = fetchActiveEnergyBurnedToday()
        async let workouts = fetchWorkouts(daysBack: 7)

        do {
            let (ringsVal, energyVal, workoutsVal) = try await (rings, energy, workouts)
            rings7d = ringsVal
            activeEnergyToday = energyVal
            workouts7d = workoutsVal

            statusText = "Fetched ✅ (rings \(ringsVal.count), workouts \(workoutsVal.count))"
        } catch {
            statusText = "Fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Rings (Activity Summary)

    private func fetchRings(daysBack: Int) async throws -> [RingsSummary] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        var all: [RingsSummary] = []
        all.reserveCapacity(daysBack)

        for offset in 0..<daysBack {
            guard let date = cal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.calendar = cal

            let predicate = HKQuery.predicateForActivitySummary(with: comps)

            let daySummaries: [RingsSummary] = try await withCheckedThrowingContinuation { cont in
                let q = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                    if let error = error {
                        cont.resume(throwing: error)
                        return
                    }

                    let mapped: [RingsSummary] = (summaries ?? []).compactMap { summary in
                        guard let d = cal.date(from: summary.dateComponents(for: cal)) else { return nil }

                        let move = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                        let moveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())

                        let exercise = summary.appleExerciseTime.doubleValue(for: .minute())
                        let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: .minute())

                        let stand = summary.appleStandHours.doubleValue(for: .count())
                        let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())

                        return RingsSummary(
                            date: d,
                            move: move,
                            moveGoal: moveGoal,
                            exerciseMinutes: exercise,
                            exerciseGoalMinutes: exerciseGoal,
                            standHours: stand,
                            standGoalHours: standGoal
                        )
                    }

                    cont.resume(returning: mapped)
                }

                self.healthStore.execute(q)
            }

            all.append(contentsOf: daySummaries)
        }

        return all.sorted { $0.date < $1.date }
    }

    // MARK: - Active energy today

    private func fetchActiveEnergyBurnedToday() async throws -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = Date()

        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: [.cumulativeSum]) { _, stats, error in
                if let error = error {
                    cont.resume(throwing: error); return
                }
                let sum = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
                cont.resume(returning: sum)
            }
            self.healthStore.execute(q)
        }
    }

    // MARK: - Workouts last N days

    private func fetchWorkouts(daysBack: Int) async throws -> [WorkoutSummary] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date().addingTimeInterval(TimeInterval(-86400 * daysBack)))
        let end = Date()

        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 100, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    cont.resume(throwing: error); return
                }

                let workouts = (samples as? [HKWorkout] ?? []).map { (w: HKWorkout) -> WorkoutSummary in
                    let typeName = w.workoutActivityType.name
//                    let typeName = "Workout Type"
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

                    let distance = w.totalDistance?.doubleValue(for: .meter()) // keep meters for now

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
        // Add a default case to handle all other types gracefully
        default: return self.rawValue.description
        }
    }
}

