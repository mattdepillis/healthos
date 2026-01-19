//
//  CoachView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import SwiftUI

struct CoachView: View {
    @State private var message: String = ""
    @State private var useOwnKey: Bool = true
    @State private var apiKey: String = ""
    @State private var memoryEnabled: Bool = true
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    chatSection
                    accessSection
                    safetySection

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isInputFocused = false
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personal Trainer (AI)")
                .font(.title2)
                .bold()
            Text("Prototype space for coaching, memory, and goal planning.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach Chat")
                .font(.title3)
                .bold()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isInputFocused)

                if message.isEmpty {
                    Text("Ask about today’s training or recovery…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                        .padding(.leading, 12)
                }
            }

            HStack {
                Toggle("Remember context", isOn: $memoryEnabled)
                Spacer()
                Button {
                    isInputFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var accessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Access")
                .font(.title3)
                .bold()

            Toggle("Bring your own API key", isOn: $useOwnKey)

            if useOwnKey {
                SecureField("Paste API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Using your own key keeps costs under your control and avoids server billing.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                Text("App-managed keys can support subscriptions or daily message limits.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy + Cost Guardrails")
                .font(.headline)
            Text("We can cache only local summaries, limit token budgets, and allow users to delete their coaching history.")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }
}
