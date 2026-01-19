//
//  Models.swift
//  HealthOS
//
//  Created by Matt DePillis on 1/4/26.
//

import Foundation
import HealthKit

struct WorkoutSummary: Identifiable, Hashable {
    let id: UUID
    let activityType: HKWorkoutActivityType
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalEnergyBurnedKcal: Double?
    let totalDistanceMeters: Double?

    var activityName: String {
        activityType.displayName
    }
}

struct RingsSummary: Hashable {
    let move: Double
    let exercise: Double
    let stand: Double
}
