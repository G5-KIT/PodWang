// Models.swift
// PodWang — a native macOS podcast client.
//
// Core data models. Both structs are:
//   - Codable   — for JSON persistence to Application Support
//   - Hashable  — for use in SwiftUI selection bindings
//   - Sendable  — for safe use across concurrency contexts

import Foundation

// MARK: - Episode

/// A single podcast episode parsed from an RSS feed.
///
/// `localFileName` is nil until the episode is downloaded, at which point it holds
/// a path relative to the downloads root (e.g. "My Podcast/Episode Title.mp3").
/// Its presence is used throughout the app to distinguish local from streaming-only playback.
///
/// `duration` stores the raw `itunes:duration` string as supplied by the feed producer.
/// It may be absent, or in any of three formats: total seconds, mm:ss, or hh:mm:ss.
/// Formatting for display is handled by `formattedDuration(_:)` in AppView.
struct Episode: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let title: String
    let pubDate: Date?
    let audioURL: String
    let description: String
    var localFileName: String?
    var duration: String?

    init(
        id: UUID = UUID(),
        title: String,
        pubDate: Date?,
        audioURL: String,
        description: String,
        localFileName: String? = nil,
        duration: String? = nil
    ) {
        self.id            = id
        self.title         = title
        self.pubDate       = pubDate
        self.audioURL      = audioURL
        self.description   = description
        self.localFileName = localFileName
        self.duration      = duration
    }
}

// MARK: - Feed

/// A podcast RSS feed saved by the user.
///
/// The custom `init(from:)` decoder provides safe fallback defaults so that
/// older persisted data (without `category`, `id`, or `artworkURL`) loads correctly.
///
/// `artworkURL` is populated the first time a feed's episodes are fetched and is then
/// persisted, so the sidebar can display artwork icons on subsequent launches without
/// re-fetching each feed.
struct Feed: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var category: String
    var artworkURL: String?

    init(id: UUID = UUID(), title: String, url: String, category: String, artworkURL: String? = nil) {
        self.id         = id
        self.title      = title
        self.url        = url
        self.category   = category.isEmpty ? "Uncategorized" : category
        self.artworkURL = artworkURL
    }

    init(from decoder: Decoder) throws {
        let container   = try decoder.container(keyedBy: CodingKeys.self)
        self.id         = try container.decodeIfPresent(UUID.self,   forKey: .id)         ?? UUID()
        self.title      = try container.decode(String.self,           forKey: .title)
        self.url        = try container.decode(String.self,           forKey: .url)
        let raw         = try container.decodeIfPresent(String.self,  forKey: .category)  ?? ""
        self.category   = raw.isEmpty ? "Uncategorized" : raw
        self.artworkURL = try container.decodeIfPresent(String.self,  forKey: .artworkURL)
    }
}
