//
//  MetricSection.swift
//  HealthOS
//
//  Created by Matt DePillis on 1/4/26.
//

import SwiftUI


struct MetricSection: View {
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

