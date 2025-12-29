//
//  ContentView.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var hk = HealthKitManager()

    private var energyKcalText: String {
        "\(Int(hk.activeEnergyToday ?? 0)) kcal"
    }

    private func milesString(fromMeters meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.2f mi", miles)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Status
                    Text(hk.statusText)
                        .font(.headline)
                        .foregroundStyle(hk.isAuthorized ? .primary : .secondary)

                    // Buttons (no overlap with title)
                    HStack(spacing: 12) {
                        Button("Authorize HealthKit") {
                            Task { await hk.requestAuthorization() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Fetch Core Snapshot") {
                            Task { await hk.fetchCoreSnapshot() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hk.isAuthorized)
                    }

                    Divider()

                    // Active Energy
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Energy Today")
                            .font(.title3)
                            .bold()

                        Text(energyKcalText)
                            .font(.title)
                            .bold()
                    }

                    Divider()

                    // Rings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Rings (last 7 days)")
                            .font(.title3)
                            .bold()

                        if hk.rings7d.isEmpty {
                            Text("No ring summaries found.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(hk.rings7d.suffix(7)) { r in
                                    RingsCard(ring: r)
                                }
                            }
                        }
                    }

                    Divider()

                    // Workouts
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Workouts (last 7 days)")
                            .font(.title3)
                            .bold()

                        if hk.workouts7d.isEmpty {
                            Text("No workouts found.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(hk.workouts7d.prefix(10)) { w in
                                    WorkoutRow(
                                        workout: w,
                                        milesString: milesString(fromMeters:)
                                    )
                                    .padding()
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("HealthOS Explorer")
        }
    }
}

// MARK: - Rings Card

private struct RingsCard: View {
    let ring: RingsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ring.date.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)

            ringRow(label: "Move", value: ring.move, goal: ring.moveGoal, unit: "kcal", tint: .red)
            ringRow(label: "Exercise", value: ring.exerciseMinutes, goal: ring.exerciseGoalMinutes, unit: "min", tint: .green)
            ringRow(label: "Stand", value: ring.standHours, goal: ring.standGoalHours, unit: "hr", tint: .blue)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func ringRow(label: String, value: Double, goal: Double, unit: String, tint: Color) -> some View {
        let pct = (goal > 0) ? min(value / goal, 1.0) : 0.0

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.subheadline)
                    .bold()
            }

            ProgressView(value: pct)
                .tint(tint)

            Text("Goal: \(Int(goal)) \(unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout Row

private struct WorkoutRow: View {
    let workout: WorkoutSummary
    let milesString: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.type)
                    .font(.headline)
                Spacer()
                Text("\(Int(workout.durationMinutes)) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                if let kcal = workout.activeEnergy {
                    Label("\(Int(kcal)) kcal", systemImage: "flame")
                }
                if let meters = workout.distance {
                    Label(milesString(meters), systemImage: "figure.walk")
                }
            }
            .font(.subheadline)
        }
    }
}

