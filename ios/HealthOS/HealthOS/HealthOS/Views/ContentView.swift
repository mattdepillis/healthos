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
        TabView {
            DailyView(hk: hk)
                .tabItem {
                    Label("Daily", systemImage: "calendar")
                }

            TrendsView(hk: hk)
                .tabItem {
                    Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }

            CoachView()
                .tabItem {
                    Label("Coach", systemImage: "sparkles")
                }
        }
    }
}
