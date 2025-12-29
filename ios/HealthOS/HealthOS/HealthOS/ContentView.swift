//
//  ContentView.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/28/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var hk = HealthKitManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("HealthOS")
                .font(.title)

            if let err = hk.lastError {
                Text("Error: \(err)")
                    .foregroundStyle(.red)
            }

            Text(hk.isAuthorized ? "HealthKit: Authorized ✅" : "HealthKit: Not Authorized ❌")

            if let steps = hk.stepsToday {
                Text("Steps today: \(steps)")
                    .font(.title2)
            } else {
                Text("Steps today: —")
                    .foregroundStyle(.secondary)
            }

            Button("Request Access + Load Steps") {
                hk.requestAuthorizationAndLoad()
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh Steps") {
                hk.loadStepsToday()
            }
            .buttonStyle(.bordered)
            .disabled(!hk.isAuthorized)
        }
        .padding()
    }
}

