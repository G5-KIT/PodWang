// Models.swift v3.2
// Core data models for PodWang.
// Both structs are Codable for JSON persistence, Hashable for use in SwiftUI
// selection bindings, and Sendable for safe use across concurrency contexts.

import Foundation

// MARK: - Episode

/// Represents a single podcast episode parsed from an RSS feed.
/// `localFileName` is set once the episode has been downloaded — its presence
/// is used throughout the app to distinguish downloaded from streaming-only episodes.
struct Episode: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let title: String
    let pubDate: Date?
    let audioURL: String
    let description: String

    /// Relative path from the downloads root, e.g. "My Podcast/Episode Title.mp3".
    /// Nil if the episode has not been downloaded.
    var localFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        pubDate: Date?,
        audioURL: String,
        description: String,
        localFileName: String? = nil
    ) {
        self.id            = id
        self.title         = title
        self.pubDate       = pubDate
        self.audioURL      = audioURL
        self.description   = description
        self.localFileName = localFileName
    }
}

// MARK: - Feed

/// Represents a podcast RSS feed saved by the user.
/// The custom `init(from:)` provides safe decoding with fallback defaults,
/// so older saved data without a `category` or `id` field won't fail to load.
struct Feed: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var category: String

    init(id: UUID = UUID(), title: String, url: String, category: String) {
        self.id       = id
        self.title    = title
        self.url      = url
        self.category = category.isEmpty ? "Uncategorized" : category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id       = try container.decodeIfPresent(UUID.self,  forKey: .id)       ?? UUID()
        self.title    = try container.decode(String.self,          forKey: .title)
        self.url      = try container.decode(String.self,          forKey: .url)
        let raw       = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        self.category = raw.isEmpty ? "Uncategorized" : raw
    }
}
