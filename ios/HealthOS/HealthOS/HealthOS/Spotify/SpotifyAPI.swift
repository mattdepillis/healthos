//
//  SpotifyAPI.swift
//  HealthOS
//
//  Created by Codex on 1/21/26.
//

import Foundation

struct SpotifyPlay: Identifiable {
    let id = UUID()
    let trackName: String
    let artistName: String
    let playedAt: Date
    let trackId: String
}

enum SpotifyAPI {
    static func fetchRecentlyPlayed(accessToken: String, limit: Int = 50) async throws -> [SpotifyPlay] {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/recently-played")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        let url = components.url!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.requestFailed
        }

        let decoded = try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
        return decoded.items.compactMap { item in
            guard let playedAt = iso8601Date(item.playedAt) else { return nil }
            let artists = item.track.artists.map { $0.name }.joined(separator: ", ")
            return SpotifyPlay(
                trackName: item.track.name,
                artistName: artists,
                playedAt: playedAt,
                trackId: item.track.id
            )
        }
    }

    static func plays(for workout: WorkoutSummary, from plays: [SpotifyPlay]) -> [SpotifyPlay] {
        plays.filter { $0.playedAt >= workout.start && $0.playedAt <= workout.end }
            .sorted { $0.playedAt < $1.playedAt }
    }

    private static func iso8601Date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

enum SpotifyAPIError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Spotify request failed."
        }
    }
}

private struct SpotifyRecentlyPlayedResponse: Decodable {
    let items: [SpotifyRecentlyPlayedItem]
}

private struct SpotifyRecentlyPlayedItem: Decodable {
    let playedAt: String
    let track: SpotifyTrack

    enum CodingKeys: String, CodingKey {
        case playedAt = "played_at"
        case track
    }
}

private struct SpotifyTrack: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
}

private struct SpotifyArtist: Decodable {
    let name: String
}
