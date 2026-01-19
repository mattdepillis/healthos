//
//  HealthHeaderView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import SwiftUI

struct HealthHeaderView: View {
    @ObservedObject var hk: HealthKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hk.statusText)
                .font(.headline)
                .foregroundStyle(hk.isAuthorized ? .primary : .secondary)

            HStack(spacing: 12) {
                Button("Authorize HealthKit") {
                    Task { await hk.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(hk.isFetching)

                Button("Fetch Snapshot") {
                    Task { await hk.fetchCoreSnapshot() }
                }
                .buttonStyle(.bordered)
                .disabled(!hk.isAuthorized || hk.isFetching)
            }
        }
    }
}
