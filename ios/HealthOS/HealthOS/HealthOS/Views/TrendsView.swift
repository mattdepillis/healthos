//
//  TrendsView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import Charts
import SwiftUI

struct TrendsView: View {
    @ObservedObject var hk: HealthKitManager

    @State private var selectedMetric: TrendMetric = .moveRing
    @State private var selectedRange: TrendRange = .days30

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HealthHeaderView(hk: hk)

                    metricPicker

                    rangePicker

                    trendChartSection

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .navigationTitle("Trends")
            .overlay {
                if hk.isFetching {
                    LoadingOverlay(text: "Loading HealthKit…")
                }
            }
        }
    }

    private var metricPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metric")
                .font(.headline)

            Picker("Metric", selection: $selectedMetric) {
                ForEach(TrendMetric.allCases, id: \.self) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Range")
                .font(.headline)

            Picker("Range", selection: $selectedRange) {
                ForEach(TrendRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var trendChartSection: some View {
        let config = trendChartConfig()
        let series = config.series
        let flatPoints = series.flatMap { $0.points }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Trend")
                .font(.title3)
                .bold()

            if flatPoints.isEmpty {
                Text("No data available for this range.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                chartView(config: config)

                if let summary = trendSummary(for: series) {
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private func chartView(config: TrendChartConfig) -> some View {
        let chart = Chart {
            ForEach(config.series) { s in
                ForEach(s.points, id: \.date) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Value", p.value)
                    )
                    .foregroundStyle(s.color)
                    .interpolationMethod(.linear)
                }
            }
        }
        .frame(height: 220)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))

        if let domain = config.yDomain {
            chart.chartYScale(domain: domain)
        } else {
            chart
        }
    }

    private func trendChartConfig() -> TrendChartConfig {
        let rangeStart = selectedRange.startDate
        let filterPoints: ([(date: Date, value: Double)]) -> [(date: Date, value: Double)] = { points in
            points
                .filter { $0.date >= rangeStart }
                .sorted { $0.date < $1.date }
        }

        switch selectedMetric {
        case .moveRing:
            return TrendChartConfig(
                series: [TrendSeries(name: "Move", color: .red, points: filterPoints(hk.activeEnergy7dKcal))],
                yDomain: nil
            )
        case .exerciseRing:
            return TrendChartConfig(
                series: [TrendSeries(name: "Exercise", color: .green, points: filterPoints(hk.exerciseMinutes7d))],
                yDomain: nil
            )
        case .standRing:
            return TrendChartConfig(
                series: [TrendSeries(name: "Stand", color: .blue, points: filterPoints(hk.standHours7d))],
                yDomain: nil
            )
        case .sleep:
            return TrendChartConfig(
                series: [TrendSeries(name: "Sleep", color: .indigo, points: filterPoints(hk.sleep7dHours))],
                yDomain: nil
            )
        case .vo2Max:
            return TrendChartConfig(
                series: [TrendSeries(name: "VO2 Max", color: .pink, points: filterPoints(hk.vo2MaxRecent))],
                yDomain: nil
            )
        case .steps:
            return TrendChartConfig(
                series: [TrendSeries(name: "Steps", color: .orange, points: filterPoints(hk.steps7d))],
                yDomain: nil
            )
        }
    }

    private func trendSummary(for series: [TrendSeries]) -> String? {
        guard series.count == 1, let points = series.first?.points, points.count >= 2 else {
            return nil
        }
        guard let first = points.first, let last = points.last else { return nil }
        let delta = last.value - first.value
        let sign = delta >= 0 ? "+" : "−"
        return "Change: \(sign)\(String(format: "%.1f", abs(delta))) over \(selectedRange.title.lowercased())"
    }
}

private enum TrendMetric: String, CaseIterable {
    case moveRing
    case exerciseRing
    case standRing
    case sleep
    case vo2Max
    case steps

    var title: String {
        switch self {
        case .moveRing: return "Move Ring"
        case .exerciseRing: return "Exercise Ring"
        case .standRing: return "Stand Ring"
        case .sleep: return "Sleep"
        case .vo2Max: return "VO2 Max"
        case .steps: return "Steps"
        }
    }
}

private enum TrendRange: Int, CaseIterable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var title: String {
        switch self {
        case .days7: return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        }
    }

    var startDate: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -self.rawValue + 1, to: Date()) ?? Date()
    }
}

private struct TrendSeries: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let points: [(date: Date, value: Double)]
}

private struct TrendChartConfig {
    let series: [TrendSeries]
    let yDomain: ClosedRange<Double>?
}
