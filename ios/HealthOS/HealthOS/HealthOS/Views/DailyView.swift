//
//  DailyView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import HealthKit
import SwiftUI

struct DailyView: View {
    @ObservedObject var hk: HealthKitManager

    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showCalendar: Bool = false
    @State private var showWorkoutPrompt: Bool = false
    @State private var showWorkoutDetailsSheet: Bool = false
    @State private var detailsWorkout: WorkoutSummary? = nil
    @AppStorage("lastWorkoutPromptDate") private var lastWorkoutPromptDate: String = ""

    private let calendarDaysBack = 30

    private var days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<calendarDaysBack)
            .compactMap { cal.date(byAdding: .day, value: -($0), to: today) }
            .sorted()
    }

    private func pointsMap(_ points: [(date: Date, value: Double)]) -> [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for p in points {
            out[cal.startOfDay(for: p.date)] = p.value
        }
        return out
    }

    private var ringSummaryByDay: [Date: HKActivitySummary] {
        let cal = Calendar.current
        return Dictionary(uniqueKeysWithValues: hk.ringSummaries7d.compactMap { s in
            guard let d = cal.date(from: s.dateComponents(for: cal)) else { return nil }
            return (cal.startOfDay(for: d), s)
        })
    }

    private func milesString(fromMeters meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.2f mi", miles)
    }

    private func percentValue(_ v: Double) -> Double {
        v <= 1.1 ? v * 100.0 : v
    }

    private func dailyValue(_ map: [Date: Double], day: Date) -> Double? {
        let cal = Calendar.current
        return map[cal.startOfDay(for: day)]
    }

    private func dailyMetrics(for day: Date) -> ([DailyMetric], [String]) {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: day)

        let steps = dailyValue(pointsMap(hk.steps7d), day: dayKey)
        let sleep = dailyValue(pointsMap(hk.sleep7dHours), day: dayKey)
        let distanceMeters = dailyValue(pointsMap(hk.distance7dMeters), day: dayKey)
        let flights = dailyValue(pointsMap(hk.flightsClimbed7d), day: dayKey)
        let mindful = dailyValue(pointsMap(hk.mindfulMinutes7d), day: dayKey)
        let weight = dailyValue(pointsMap(hk.weight7dLbs), day: dayKey)
        let bodyFat = dailyValue(pointsMap(hk.bodyFat7dPct), day: dayKey)
        let respiratory = dailyValue(pointsMap(hk.respiratoryRate7d), day: dayKey)
        let bloodO2 = dailyValue(pointsMap(hk.bloodOxygen7dPct), day: dayKey)

        let metrics: [DailyMetric] = [
            DailyMetric(
                label: "Steps",
                valueText: steps.map { "\(Int($0))" } ?? "—",
                systemImage: "figure.walk",
                hasData: (steps ?? 0) > 0
            ),
            DailyMetric(
                label: "Sleep",
                valueText: sleep.map { String(format: "%.1f hr", $0) } ?? "—",
                systemImage: "bed.double.fill",
                hasData: (sleep ?? 0) > 0
            ),
            DailyMetric(
                label: "Distance",
                valueText: distanceMeters.map(milesString(fromMeters:)) ?? "—",
                systemImage: "figure.walk.motion",
                hasData: (distanceMeters ?? 0) > 0
            ),
            DailyMetric(
                label: "Flights",
                valueText: flights.map { "\(Int($0))" } ?? "—",
                systemImage: "stairs",
                hasData: (flights ?? 0) > 0
            ),
            DailyMetric(
                label: "Mindful",
                valueText: mindful.map { "\(Int($0)) min" } ?? "—",
                systemImage: "brain.head.profile",
                hasData: (mindful ?? 0) > 0
            ),
            DailyMetric(
                label: "Weight",
                valueText: weight.map { String(format: "%.1f lb", $0) } ?? "—",
                systemImage: "scalemass",
                hasData: (weight ?? 0) > 0
            ),
            DailyMetric(
                label: "Body Fat",
                valueText: bodyFat.map { String(format: "%.1f%%", percentValue($0)) } ?? "—",
                systemImage: "figure.arms.open",
                hasData: (bodyFat ?? 0) > 0
            ),
            DailyMetric(
                label: "Respiratory",
                valueText: respiratory.map { String(format: "%.1f bpm", $0) } ?? "—",
                systemImage: "lungs.fill",
                hasData: (respiratory ?? 0) > 0
            ),
            DailyMetric(
                label: "Blood O₂",
                valueText: bloodO2.map { String(format: "%.1f%%", percentValue($0)) } ?? "—",
                systemImage: "drop.fill",
                hasData: (bloodO2 ?? 0) > 0
            )
        ]

        let missing = metrics.filter { !$0.hasData }.map { $0.label }
        return (metrics.filter { $0.hasData }, missing)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HealthHeaderView(hk: hk)

                    dayStrip

                    swipeHint

                    dayPager

                    dailyMetricsSection

                    workoutsSection

                    vo2HighlightSection

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("Daily")
            .overlay {
                if hk.isFetching {
                    LoadingOverlay(text: "Loading HealthKit…")
                }
            }
        }
        .onAppear {
            let today = Calendar.current.startOfDay(for: Date())
            if selectedDay != today {
                selectedDay = today
            }
            maybePromptWorkoutDetails(for: today)
        }
        .onChange(of: hk.workouts7d) {
            let today = Calendar.current.startOfDay(for: Date())
            maybePromptWorkoutDetails(for: today)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWorkoutDetails)) { _ in
            detailsWorkout = workouts(on: selectedDay).first
            showWorkoutDetailsSheet = true
        }
        .sheet(isPresented: $showCalendar) {
            calendarSheet
        }
        .sheet(isPresented: $showWorkoutDetailsSheet) {
            WorkoutDetailsSheet(workout: detailsWorkout)
        }
        .alert("Add workout details?", isPresented: $showWorkoutPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Add details") {
                NotificationCenter.default.post(name: .showWorkoutDetails, object: nil)
            }
        } message: {
            Text("Looks like you have workouts today. Want to add sets, reps, or notes?")
        }
    }

    private var dayStrip: some View {
        HStack(alignment: .center, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days, id: \.self) { day in
                        DayChip(
                            date: day,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay)
                        ) {
                            selectedDay = day
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                showCalendar = true
            } label: {
                Image(systemName: "calendar")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pick date")
        }
    }

    private var swipeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
            Text("Swipe for more days")
                .font(.footnote)
            Image(systemName: "chevron.right")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dayPager: some View {
        TabView(selection: $selectedDay) {
            ForEach(days, id: \.self) { day in
                DailySummaryCard(
                    day: day,
                    ringSummary: ringSummaryByDay[Calendar.current.startOfDay(for: day)],
                    moveKcal: dailyValue(pointsMap(hk.activeEnergy7dKcal), day: day),
                    exerciseMinutes: dailyValue(pointsMap(hk.exerciseMinutes7d), day: day),
                    standHours: dailyValue(pointsMap(hk.standHours7d), day: day)
                )
                .tag(day)
            }
        }
        .frame(height: 220)
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private var dailyMetricsSection: some View {
        let (metrics, missing) = dailyMetrics(for: selectedDay)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Metrics")
                    .font(.title3)
                    .bold()
                Spacer()
                Text(selectedDay, style: .date)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            if metrics.isEmpty {
                Text("No metrics found for this day.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(metrics) { metric in
                        DailyMetricCard(metric: metric)
                    }
                }
            }

            if !missing.isEmpty {
                Text("Missing data: \(missing.joined(separator: ", "))")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private var vo2HighlightSection: some View {
        let latest = hk.vo2MaxRecent.last

        return VStack(alignment: .leading, spacing: 8) {
            Text("VO2 Max (recent)")
                .font(.title3)
                .bold()

            if let latest {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.1f ml/kg/min", latest.value))
                            .font(.title2)
                            .bold()
                        Text(latest.date, style: .date)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "heart.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("No VO2 Max samples found yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private var workoutsSection: some View {
        let todayWorkouts = workouts(on: selectedDay)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workouts")
                    .font(.title3)
                    .bold()
                Spacer()
                NavigationLink("See all") {
                    WorkoutsView(hk: hk)
                }
                .font(.subheadline)
            }

            if todayWorkouts.isEmpty {
                Text("No workouts logged for this day.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 12) {
                    ForEach(todayWorkouts.prefix(3)) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout, milesString: milesString(fromMeters:))
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button("Fill out details") {
                        NotificationCenter.default.post(name: .showWorkoutDetails, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func workouts(on day: Date) -> [WorkoutSummary] {
        let cal = Calendar.current
        return hk.workouts7d.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    private func maybePromptWorkoutDetails(for day: Date) {
        let cal = Calendar.current
        let todayKey = day.formatted(.dateTime.year().month().day())
        guard todayKey != lastWorkoutPromptDate else { return }
        if !workouts(on: day).isEmpty {
            lastWorkoutPromptDate = todayKey
            showWorkoutPrompt = true
        }
    }

    private var calendarSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                let bounds = calendarBounds()
                DatePicker(
                    "Select a day",
                    selection: $selectedDay,
                    in: bounds,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                Spacer()
            }
            .padding()
            .navigationTitle("Pick a date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showCalendar = false
                    }
                }
            }
        }
    }

    private func calendarBounds() -> ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(calendarDaysBack - 1), to: today) ?? today
        return start...today
    }
}

private struct DailyMetric: Identifiable {
    let id = UUID()
    let label: String
    let valueText: String
    let systemImage: String
    let hasData: Bool
}

private struct DailyMetricCard: View {
    let metric: DailyMetric

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: metric.systemImage)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(metric.valueText)
                    .font(.headline)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        let day = date.formatted(.dateTime.weekday(.narrow))
        let num = date.formatted(.dateTime.day())

        return Button(action: onTap) {
            VStack(spacing: 6) {
                Text(day)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(num)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(width: 44, height: 58)
            .background(isSelected ? Color.black : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct DailySummaryCard: View {
    let day: Date
    let ringSummary: HKActivitySummary?
    let moveKcal: Double?
    let exerciseMinutes: Double?
    let standHours: Double?

    var body: some View {
        HStack(spacing: 16) {
            if let ringSummary {
                ActivityRingsView(summary: ringSummary)
                    .frame(width: 80, height: 80)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.secondary.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(day, style: .date)
                    .font(.headline)

                HStack(spacing: 8) {
                    StatPill(label: "Move", value: moveKcal.map { "\(Int($0)) kcal" } ?? "—")
                    StatPill(label: "Exercise", value: exerciseMinutes.map { "\(Int($0)) min" } ?? "—")
                    StatPill(label: "Stand", value: standHours.map { "\(Int($0)) hr" } ?? "—")
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
