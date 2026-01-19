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
                mainContent
                    .padding()
            }
            .navigationTitle("HealthOS Explorer")
            .toolbar { toolbarContent }
            .overlay { overlayContent }
        }
    }

    // MARK: - Sections (split up to avoid type-check timeout)

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusSection
            buttonsSection

            Divider()

            activeEnergySection

            Divider()

            ringsSection

            Divider()

            activitySummarySections

            Divider()

            stepsSection
            distanceSection
            flightsClimbedSection
            mindfulMinutesSection
            restingHRSection
            hrvSection
            vo2MaxSection
            sleepSection

            Divider()

            workoutsSection

            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Text(hk.statusText)
            .font(.headline)
            .foregroundStyle(hk.isAuthorized ? .primary : .secondary)
    }

    @ViewBuilder
    private var buttonsSection: some View {
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
    }

    @ViewBuilder
    private var activeEnergySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Energy Today")
                .font(.title3)
                .bold()

            Text(energyKcalText)
                .font(.title)
                .bold()
        }
    }

    @ViewBuilder
    private var ringsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rings (last 7 days)")
                .font(.title3)
                .bold()

            if hk.rings7d.isEmpty {
                Text("No ring summaries found.")
                    .foregroundStyle(.secondary)
            } else {
                ringsList
            }
        }
    }

    @ViewBuilder
    private var activitySummarySections: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Summary (last 7 days)")
                .font(.title3)
                .bold()

            MetricSection(
                title: "Active Energy",
                points: hk.activeEnergy7dKcal,
                bigValue: { v in "\(Int(v)) kcal" },
                rowRight: { v in "\(Int(v)) kcal" },
                deltaSuffix: "kcal"
            )

            MetricSection(
                title: "Exercise Minutes",
                points: hk.exerciseMinutes7d,
                bigValue: { v in "\(Int(v)) min" },
                rowRight: { v in "\(Int(v)) min exercise" },
                deltaSuffix: "min"
            )

            MetricSection(
                title: "Stand Hours",
                points: hk.standHours7d,
                bigValue: { v in "\(Int(v)) hr" },
                rowRight: { v in "\(Int(v)) hr standing" },
                deltaSuffix: "hr"
            )
        }
    }

    @ViewBuilder
    private var ringsList: some View {
        VStack(spacing: 12) {
            ForEach(hk.rings7d.suffix(7)) { r in
                ringRow(r)
            }
        }
    }

    @ViewBuilder
    private func ringRow(_ r: RingsSummary) -> some View {
        let cal = Calendar.current
        let key = cal.startOfDay(for: r.date)
        let s = ringSummaryByDay[key]

        HStack(alignment: .top, spacing: 12) {
            if let s {
                ActivityRingsView(summary: s)
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


    @ViewBuilder
    private var stepsSection: some View {
        MetricSection(
            title: "Steps (last 7 days)",
            points: hk.steps7d.map { (date: $0.date, value: $0.value) },
            bigValue: { v in "\(Int(v))" },
            rowRight: { v in "\(Int(v)) steps" },
            deltaSuffix: "steps"
        )
    }

    @ViewBuilder
    private var distanceSection: some View {
        MetricSection(
            title: "Distance (last 7 days)",
            points: hk.distance7dMeters.map { (date: $0.date, value: $0.value) },
            bigValue: { meters in milesString(fromMeters: meters) },
            rowRight: { meters in milesString(fromMeters: meters) },
            deltaSuffix: "mi",
            deltaTransform: { meters in meters / 1609.34 }
        )
    }

    @ViewBuilder
    private var flightsClimbedSection: some View {
        MetricSection(
            title: "Flights Climbed (last 7 days)",
            points: hk.flightsClimbed7d,
            bigValue: { v in "\(Int(v)) flights" },
            rowRight: { v in "\(Int(v)) flights" },
            deltaSuffix: "flights"
        )
    }

    @ViewBuilder
    private var mindfulMinutesSection: some View {
        MetricSection(
            title: "Mindful Minutes (last 7 days)",
            points: hk.mindfulMinutes7d,
            bigValue: { v in "\(Int(v)) min" },
            rowRight: { v in "\(Int(v)) min mindful" },
            deltaSuffix: "min"
        )
    }

    @ViewBuilder
    private var restingHRSection: some View {
        MetricSection(
            title: "Resting Heart Rate (last 7 days)",
            points: hk.restingHR7d.map { (date: $0.date, value: $0.value) },
            bigValue: { v in "\(Int(v)) bpm" },
            rowRight: { v in "\(Int(v)) bpm resting" },
            deltaSuffix: "bpm"
        )
    }

    @ViewBuilder
    private var hrvSection: some View {
        MetricSection(
            title: "HRV (SDNN) (last 7 days)",
            points: hk.hrv7d.map { (date: $0.date, value: $0.value) },
            bigValue: { v in "\(Int(v)) ms" },
            rowRight: { v in "\(Int(v)) ms SDNN" },
            deltaSuffix: "ms"
        )
    }

    @ViewBuilder
    private var vo2MaxSection: some View {
        let points = hk.vo2MaxRecent

        if points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("VO2 Max (recent)")
                    .font(.title3)
                    .bold()

                Text("No VO2 Max samples found. (Some devices don’t collect this.)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else {
            MetricSection(
                title: "VO2 Max (recent)",
                points: points,
                bigValue: { v in String(format: "%.1f ml/kg/min", v) },
                rowRight: { v in String(format: "%.1f ml/kg/min", v) },
                deltaSuffix: "ml/kg/min"
            )
        }
    }

    @ViewBuilder
    private var sleepSection: some View {
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
    }

    @ViewBuilder
    private var workoutsSection: some View {
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
    }

    // MARK: - Toolbar / Overlay

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // Use the same refresh path as "Fetch Core Snapshot" to avoid guessing manager API.
                Task { await hk.fetchCoreSnapshot() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!hk.isAuthorized || hk.isFetching)
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if hk.isFetching {
            LoadingOverlay(text: "Loading HealthKit…")
        }
    }
}
