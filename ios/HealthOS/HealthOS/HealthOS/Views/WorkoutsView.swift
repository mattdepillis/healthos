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
    @State private var showSpotifySheet: Bool = false
    @AppStorage("spotifyAccessToken") private var spotifyAccessToken: String = ""
    @AppStorage("spotifyTokenExpiresAt") private var spotifyTokenExpiresAt: Double = 0
    @State private var recentPlays: [SpotifyPlay] = []
    @State private var spotifyError: String? = nil
    @State private var isLoadingSpotify: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Workouts")
                    .font(.largeTitle)
                    .bold()

                spotifyConnectSection
                recentListeningSection

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
        .sheet(isPresented: $showSpotifySheet) {
            SpotifyAuthSheet(accessToken: $spotifyAccessToken, tokenExpiresAt: $spotifyTokenExpiresAt)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWorkoutDetails)) { _ in
            showDetailsSheet = true
        }
        .task {
            await refreshSpotifyRecentPlays()
        }
    }

    private func milesString(fromMeters meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.2f mi", miles)
    }

    private var spotifyConnectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spotify")
                .font(.headline)

            if spotifyAccessToken.isEmpty {
                Text("Connect Spotify to pair workouts with what you listened to.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Button("Connect Spotify") {
                    showSpotifySheet = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(tokenStatusText)
                        .font(.subheadline)
                    Spacer()
                    Button("Manage") {
                        showSpotifySheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var tokenStatusText: String {
        let expiry = Date(timeIntervalSince1970: spotifyTokenExpiresAt)
        if spotifyTokenExpiresAt == 0 {
            return "Connected"
        }
        return "Connected • expires \(expiry.formatted(date: .omitted, time: .shortened))"
    }

    private var recentListeningSection: some View {
        let recentWorkouts = Array(hk.workouts7d.prefix(3))

        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Listening Matches")
                .font(.headline)

            if spotifyAccessToken.isEmpty {
                Text("Connect Spotify to see listening matches for workouts.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if isLoadingSpotify {
                Text("Fetching listening history…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if let spotifyError {
                Text(spotifyError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            } else if recentPlays.isEmpty {
                Text("No recent listening found yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if recentWorkouts.isEmpty {
                Text("Log a workout to match listening history.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentWorkouts) { workout in
                        let matches = SpotifyAPI.plays(for: workout, from: recentPlays)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(workout.type) • \(workout.start.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .bold()
                            if matches.isEmpty {
                                Text("No listening matches in this workout window.")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                Text("Matches: \(matches.count) • \(matches.last?.trackName ?? "Track")")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func refreshSpotifyRecentPlays() async {
        guard !spotifyAccessToken.isEmpty else { return }
        isLoadingSpotify = true
        spotifyError = nil
        do {
            let plays = try await SpotifyAPI.fetchRecentlyPlayed(accessToken: spotifyAccessToken, limit: 50)
            recentPlays = plays
        } catch {
            spotifyError = error.localizedDescription
        }
        isLoadingSpotify = false
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    @AppStorage("spotifyAccessToken") private var spotifyAccessToken: String = ""
    @State private var plays: [SpotifyPlay] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

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

                SpotifyListeningSection(
                    plays: plays,
                    isLoading: isLoading,
                    errorMessage: errorMessage
                )
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
        .task {
            await loadListening()
        }
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

    private func loadListening() async {
        guard !spotifyAccessToken.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let recent = try await SpotifyAPI.fetchRecentlyPlayed(accessToken: spotifyAccessToken, limit: 50)
            plays = SpotifyAPI.plays(for: workout, from: recent)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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

struct SpotifyAuthSheet: View {
    @Binding var accessToken: String
    @Binding var tokenExpiresAt: Double
    @State private var tempToken: String = ""
    @StateObject private var authManager = SpotifyAuthManager()
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Connect Spotify") {
                    Text("Use the official login to connect your Spotify account.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)

                    Button(authManager.isAuthorizing ? "Connecting…" : "Connect Spotify") {
                        Task {
                            let result = await authManager.authorize()
                            switch result {
                            case .success(let tokens):
                                accessToken = tokens.accessToken
                                tokenExpiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn)).timeIntervalSince1970
                                tempToken = tokens.accessToken
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(authManager.isAuthorizing)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section("Status") {
                    if accessToken.isEmpty {
                        Text("Not connected")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Connected ✅")
                    }
                }

                if !accessToken.isEmpty {
                    Section {
                        Button("Disconnect Spotify", role: .destructive) {
                            accessToken = ""
                            tokenExpiresAt = 0
                            tempToken = ""
                        }
                    }
                }
            }
            .navigationTitle("Spotify")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempToken = accessToken
            }
        }
    }
}

struct SpotifyListeningSection: View {
    let plays: [SpotifyPlay]
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening (Spotify)")
                .font(.headline)

            if isLoading {
                Text("Fetching listening history…")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            } else if plays.isEmpty {
                Text("No listening matches during this workout.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 8) {
                    ForEach(plays.prefix(8)) { play in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(play.trackName)
                                    .font(.subheadline)
                                    .bold()
                                Text(play.artistName)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                            Text(play.playedAt, style: .time)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if plays.count > 8 {
                        Text("Showing 8 of \(plays.count) plays.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
    }
}
