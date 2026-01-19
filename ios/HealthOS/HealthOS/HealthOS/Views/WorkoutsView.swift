//
//  WorkoutsView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import SwiftUI

struct WorkoutsView: View {
    @ObservedObject var hk: HealthKitManager
    @State private var showDetailsSheet: Bool = false
    @State private var selectedWorkout: WorkoutSummary? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Workouts")
                    .font(.largeTitle)
                    .bold()

                if hk.workouts7d.isEmpty {
                    Text("No workouts found in the last 30 days.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    VStack(spacing: 12) {
                        ForEach(hk.workouts7d) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutRow(workout: workout, milesString: milesString(fromMeters:))
                            }
                            .buttonStyle(.plain)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contextMenu {
                                Button("Fill out details") {
                                    selectedWorkout = workout
                                    showDetailsSheet = true
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Workouts")
        .sheet(isPresented: $showDetailsSheet) {
            WorkoutDetailsSheet(workout: selectedWorkout)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWorkoutDetails)) { _ in
            showDetailsSheet = true
        }
    }

    private func milesString(fromMeters meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.2f mi", miles)
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.type)
                        .font(.title)
                        .bold()
                    Text(workout.start, style: .date)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    detailRow(label: "Start", value: workout.start.formatted(date: .omitted, time: .shortened))
                    detailRow(label: "End", value: workout.end.formatted(date: .omitted, time: .shortened))
                    detailRow(label: "Duration", value: String(format: "%.0f min", workout.durationMinutes))

                    if let energy = workout.activeEnergy {
                        detailRow(label: "Active Energy", value: "\(Int(energy)) kcal")
                    }
                    if let distance = workout.distance {
                        detailRow(label: "Distance", value: String(format: "%.2f mi", distance / 1609.34))
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spotify (planned)")
                        .font(.headline)
                    Text("We’ll match this workout with your listening history once Spotify is connected.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button("Fill out details") {
                    NotificationCenter.default.post(name: .showWorkoutDetails, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.headline)
        }
    }
}

struct WorkoutDetailsSheet: View {
    let workout: WorkoutSummary?
    @State private var mode: EntryMode = .natural
    @State private var notes: String = ""
    @State private var movement: String = ""
    @State private var sets: String = ""
    @State private var reps: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add workout details")
                        .font(.title3)
                        .bold()

                    if let workout {
                        Text("\(workout.type) • \(workout.start.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Picker("Entry mode", selection: $mode) {
                        Text("Natural language").tag(EntryMode.natural)
                        Text("Form").tag(EntryMode.form)
                    }
                    .pickerStyle(.segmented)

                    if mode == .natural {
                        TextEditor(text: $notes)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Example: 3x10 bench, 3x8 rows, felt strong today…")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 16)
                                        .padding(.leading, 12)
                                }
                            }
                    } else {
                        VStack(spacing: 12) {
                            TextField("Movement", text: $movement)
                                .textFieldStyle(.roundedBorder)
                            TextField("Sets", text: $sets)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Reps", text: $reps)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button("Save details") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Workout details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private enum EntryMode {
        case natural
        case form
    }
}

extension Notification.Name {
    static let showWorkoutDetails = Notification.Name("showWorkoutDetails")
}
