//
//  HealthKitManager.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import Foundation
import HealthKit
internal import Combine

final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var stepsToday: Int? = nil
    @Published var lastError: String? = nil

    func requestAuthorizationAndLoad() {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "Health data not available on this device."
            return
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            lastError = "StepCount type not available."
            return
        }

        let toRead: Set<HKObjectType> = [stepType]

        store.requestAuthorization(toShare: [], read: toRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = error.localizedDescription
                    self?.isAuthorized = false
                    return
                }

                self?.isAuthorized = success
                if success {
                    self?.loadStepsToday()
                }
            }
        }
    }

    func loadStepsToday() {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            self.lastError = "StepCount type not available."
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)

        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = error.localizedDescription
                    return
                }

                let sum = result?.sumQuantity()
                let steps = sum?.doubleValue(for: HKUnit.count()) ?? 0
                self?.stepsToday = Int(steps)
            }
        }

        store.execute(query)
    }
}
