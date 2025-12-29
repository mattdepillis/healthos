//
//  ActivityRingView.swift
//  HealthOS
//
//  Created by Matt DePillis on 12/29/25.
//

import SwiftUI
import HealthKit
import HealthKitUI

struct ActivityRingView: UIViewRepresentable {
    let summary: HKActivitySummary

    func makeUIView(context: Context) -> HKActivityRingView {
        let v = HKActivityRingView()
        v.setActivitySummary(summary, animated: false)
        return v
    }

    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        uiView.setActivitySummary(summary, animated: true)
    }
}
