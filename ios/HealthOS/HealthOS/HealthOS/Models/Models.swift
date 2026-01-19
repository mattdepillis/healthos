//
//  Models.swift
//  HealthOS
//
//  Created by Matt DePillis on 1/4/26.
//

import Foundation
import HealthKit

// MARK: - UI models

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

struct WorkoutSummary: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let start: Date
    let end: Date
    let durationMinutes: Double
    let activeEnergy: Double?
    let distance: Double?
}

struct SleepStageBreakdown: Identifiable {
    let id = UUID()
    let date: Date
    let coreHours: Double
    let deepHours: Double
    let remHours: Double
    let unspecifiedHours: Double
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .traditionalStrengthTraining: return "Strength"
        case .functionalStrengthTraining: return "Functional Strength"
        case .cycling: return "Cycle"
        case .swimming: return "Swim"
        case .yoga: return "Yoga"
        case .hiking: return "Hike"
        case .elliptical: return "Elliptical"
        case .rowing: return "Row"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Workout"
        }
    }
}
