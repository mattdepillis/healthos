//
//  WorkoutRow.swift
//  HealthOS
//
//  Created by Matt DePillis on 1/4/26.
//

import SwiftUI

struct WorkoutRow: View {
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
