//
//  LoadingOverlay.swift
//  HealthOS
//
//  Created by Matt DePillis on 1/4/26.
//

import SwiftUI

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 12)
        }
        .transition(.opacity)
    }
}
