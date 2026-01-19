//
//  ActivityRingView.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/29/25.
//

import SwiftUI
import HealthKit
import HealthKitUI

/// Wraps HKActivityRingView for SwiftUI.
struct ActivityRingsView: UIViewRepresentable {
    let summary: HKActivitySummary?

    func makeUIView(context: Context) -> HKActivityRingView {
        HKActivityRingView()
    }

    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        if let summary {
            uiView.setActivitySummary(summary, animated: true)
        }
    }
}
