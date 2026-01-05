//
//  ContentView.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import HealthKit
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

    // Build a fast lookup map (day -> HKActivitySummary) to avoid O(n^2) scans during rendering.
    private var ringSummaryByDay: [Date: HKActivitySummary] {
        let cal = Calendar.current
        return Dictionary(uniqueKeysWithValues: hk.ringSummaries7d.compactMap { s in
            guard let d = cal.date(from: s.dateComponents(for: cal)) else { return nil }
            return (cal.startOfDay(for: d), s)
        })
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
                        .disabled(hk.isFetching)

                        Button("Fetch Core Snapshot") {
                            Task { await hk.fetchCoreSnapshot() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!hk.isAuthorized || hk.isFetching)
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
                                    let cal = Calendar.current
                                    let key = cal.startOfDay(for: r.date)
                                    let s = ringSummaryByDay[key]

                                    HStack(alignment: .top, spacing: 12) {
                                        if let s {
                                            ActivityRingView(summary: s)
                                                .frame(width: 56, height: 56)
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(.secondary.opacity(0.15))
                                                .frame(width: 56, height: 56)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(r.date, style: .date)
                                                .font(.headline)

                                            Text("Move: \(Int(r.move))/\(Int(r.moveGoal)) kcal")
                                                .foregroundStyle(.secondary)

                                            Text("Exercise: \(Int(r.exerciseMinutes))/\(Int(r.exerciseGoalMinutes)) min")
                                                .foregroundStyle(.secondary)

                                            Text("Stand: \(Int(r.standHours))/\(Int(r.standGoalHours)) hr")
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                    }

                    Divider()

                    // Steps
                    MetricSection(
                        title: "Steps (last 7 days)",
                        points: hk.steps7d.map { (date: $0.date, value: $0.value) },
                        bigValue: { v in "\(Int(v))" },
                        rowRight: { v in "\(Int(v)) steps" },
                        deltaSuffix: "steps"
                    )

                    // Distance
                    MetricSection(
                        title: "Distance (last 7 days)",
                        points: hk.distance7dMeters.map { (date: $0.date, value: $0.value) },
                        bigValue: { meters in milesString(fromMeters: meters) },
                        rowRight: { meters in milesString(fromMeters: meters) },
                        deltaSuffix: "mi",
                        deltaTransform: { meters in meters / 1609.34 }
                    )

                    // Resting Heart Rate
                    MetricSection(
                        title: "Resting Heart Rate (last 7 days)",
                        points: hk.restingHR7d.map { (date: $0.date, value: $0.value) },
                        bigValue: { v in "\(Int(v)) bpm" },
                        rowRight: { v in "\(Int(v)) bpm resting" },
                        deltaSuffix: "bpm"
                    )

                    // HRV
                    MetricSection(
                        title: "HRV (SDNN) (last 7 days)",
                        points: hk.hrv7d.map { (date: $0.date, value: $0.value) },
                        bigValue: { v in "\(Int(v)) ms" },
                        rowRight: { v in "\(Int(v)) ms SDNN" },
                        deltaSuffix: "ms"
                    )

                    // Sleep (optional: show explanatory empty state if basically all zeros)
                    let sleepPoints: [(date: Date, value: Double)] =
                        hk.sleep7dHours.map { (date: $0.date, value: $0.value) }

                    if sleepPoints.allSatisfy({ $0.value == 0 }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sleep (last 7 days)")
                                .font(.title3)
                                .bold()

                            Text("No sleep data found. (Common if you don’t wear your watch to bed.)")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        MetricSection(
                            title: "Sleep (last 7 days)",
                            points: sleepPoints,
                            bigValue: { hours in String(format: "%.1f hr", hours) },
                            rowRight: { hours in String(format: "%.1f hr asleep", hours) },
                            deltaSuffix: "hr"
                        )
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
            .overlay {
                if hk.isFetching {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView("Loading HealthKit…")
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Metric Section

private struct MetricSection: View {
    let title: String
    let points: [(date: Date, value: Double)]
    let bigValue: (Double) -> String
    let rowRight: (Double) -> String
    let deltaSuffix: String

    // Optional transform if you want delta displayed in different unit than stored (e.g. meters -> miles)
    var deltaTransform: (Double) -> Double = { $0 }

    private func latest() -> Double? { points.last?.value }

    private func delta() -> Double? {
        guard points.count >= 2 else { return nil }
        return deltaTransform(points[points.count - 1].value) - deltaTransform(points[points.count - 2].value)
    }

    private func deltaView(_ d: Double?) -> some View {
        guard let d else { return AnyView(EmptyView()) }
        let isNeg = d < 0
        let absVal = abs(d)

        let formatted: String = (absVal >= 10 || deltaSuffix.contains("steps") || deltaSuffix.contains("bpm"))
            ? "\(Int(absVal))"
            : String(format: "%.2f", absVal)

        return AnyView(
            Text("\(isNeg ? "−" : "+")\(formatted) \(deltaSuffix)")
                .foregroundStyle(isNeg ? .red : .green)
                .font(.subheadline)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3)
                .bold()

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(latest().map(bigValue) ?? "—")
                    .font(.title)
                    .bold()

                deltaView(delta())
            }

            VStack(spacing: 12) {
                ForEach(points, id: \.date) { p in
                    HStack {
                        Text(p.date.formatted(date: .long, time: .omitted))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(p.value == 0 ? "—" : rowRight(p.value))
                            .font(.headline)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
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
