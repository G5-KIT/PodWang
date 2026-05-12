// SidebarAdditions.swift
// PodWang — a native macOS podcast client.
//
// Contains all feed management UI presented from the gear toolbar button in SidebarView:
//   - ManagementPopover  — compact vertical menu of management actions
//   - PodcastSearchPopover — iTunes API search with one-tap add
//   - PodcastSearchRow   — a single search result row
//   - OPMLDocument       — FileDocument wrapper for OPML/XML export

import SwiftUI
import UniformTypeIdentifiers

// MARK: - iTunes Search Models

/// A single podcast result decoded from the iTunes Search API response.
/// Only the fields used for display and feed creation are decoded.
struct iTunesPodcast: Identifiable, Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let feedUrl: String?
    let artworkUrl100: String?

    enum CodingKeys: String, CodingKey {
        case id           = "trackId"
        case trackName
        case artistName
        case feedUrl
        case artworkUrl100
    }
}

/// Top-level wrapper for the iTunes Search API JSON response.
private struct iTunesResponse: Decodable {
    let results: [iTunesPodcast]
}

// MARK: - Management Popover

/// Presented from the gear toolbar button in SidebarView.
/// Provides all feed management actions in a compact native-style menu.
struct ManagementPopover: View {
    @ObservedObject var manager: PodWangManager
    @Binding var showingFilePicker: Bool
    @Binding var showingFileExporter: Bool
    @Binding var opmlDoc: OPMLDocument?

    @State private var showingSearchPopover = false
    @State private var showingAddPopover    = false
    @State private var newTitle             = ""
    @State private var newURL               = ""
    @State private var newCategory          = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Opens the iTunes podcast search popover.
            Button { showingSearchPopover = true } label: {
                Label("Find Podcasts…", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingSearchPopover, arrowEdge: .trailing) {
                PodcastSearchPopover(manager: manager)
            }

            // Opens the manual RSS URL entry form.
            Button { showingAddPopover = true } label: {
                Label("Add Podcast…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingAddPopover, arrowEdge: .trailing) {
                addPodcastPopover
            }

            Divider().padding(.horizontal, 8)

            // Triggers the fileImporter modifier in AppView.
            Button { showingFilePicker = true } label: {
                Label("Import XML", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())

            // Generates OPML XML and triggers the fileExporter modifier in AppView.
            Button {
                opmlDoc = OPMLDocument(text: manager.generateOPMLString())
                showingFileExporter = true
            } label: {
                Label("Export XML", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())

            Divider().padding(.horizontal, 8)

            // Clears the security-scoped bookmark, returning the app to the setup screen.
            Button(role: .destructive) {
                manager.resetStorageLocation()
            } label: {
                Label("Reset Storage", systemImage: "folder.badge.minus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }

    // MARK: - Add Podcast Popover

    /// Manual RSS URL entry form. The Add button stays disabled until both
    /// the Name and RSS URL fields contain text.
    private var addPodcastPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Podcast").font(.headline)

            TextField("Name", text: $newTitle)
            TextField("RSS URL", text: $newURL)
            TextField("Category (optional)", text: $newCategory)

            HStack {
                Button("Cancel") {
                    showingAddPopover = false
                    newTitle = ""; newURL = ""; newCategory = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    manager.addFeed(title: newTitle, url: newURL, category: newCategory)
                    showingAddPopover = false
                    newTitle = ""; newURL = ""; newCategory = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.isEmpty || newURL.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(width: 280)
    }
}

// MARK: - Podcast Search Popover

/// Searches the iTunes Search API as the user types and displays results with artwork.
/// A 500ms debounce prevents excessive API calls on every keystroke.
/// Results with no RSS feed URL are filtered out before display.
/// A "Browse Podcast Index…" link at the bottom provides a fallback for unlisted podcasts.
private struct PodcastSearchPopover: View {
    @ObservedObject var manager: PodWangManager

    @State private var searchText   = ""
    @State private var results      = [iTunesPodcast]()
    @State private var isSearching  = false
    @State private var errorMessage: String?
    @State private var addedIDs     = Set<Int>()  // Tracks additions within this session.

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Search field with inline spinner and clear button.
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search podcasts…", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }
                if isSearching {
                    ProgressView().scaleEffect(0.7)
                } else if !searchText.isEmpty {
                    Button { searchText = ""; results = []; errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding([.horizontal, .top], 12)

            Divider().padding(.top, 8)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.secondary).font(.caption).padding()
            } else if results.isEmpty && !isSearching && !searchText.isEmpty {
                Text("No results found.")
                    .foregroundColor(.secondary).font(.caption).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { podcast in
                            PodcastSearchRow(
                                podcast: podcast,
                                isAdded: addedIDs.contains(podcast.id)
                            ) {
                                addPodcast(podcast)
                            }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            Divider()

            // Fallback link for podcasts not in the Apple catalogue.
            Button {
                NSWorkspace.shared.open(URL(string: "https://podcastindex.org/")!)
            } label: {
                HStack {
                    Image(systemName: "safari").foregroundColor(.secondary)
                    Text("Browse Podcast Index…").font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: 360, height: 480)
        // Debounced search: waits 500ms after the user stops typing before firing.
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else { results = []; return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if newValue == searchText { performSearch() }
            }
        }
    }

    /// Queries the iTunes Search API and populates `results`.
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching  = true
        errorMessage = nil

        Task {
            do {
                var components = URLComponents(string: "https://itunes.apple.com/search")!
                components.queryItems = [
                    URLQueryItem(name: "term",    value: searchText),
                    URLQueryItem(name: "media",   value: "podcast"),
                    URLQueryItem(name: "entity",  value: "podcast"),
                    URLQueryItem(name: "limit",   value: "25"),
                    URLQueryItem(name: "country", value: "us"),
                ]
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let response  = try JSONDecoder().decode(iTunesResponse.self, from: data)
                await MainActor.run {
                    results     = response.results.filter { $0.feedUrl != nil }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Search failed. Please check your connection."
                    isSearching  = false
                }
            }
        }
    }

    /// Adds the selected podcast to the feed list and marks it as added for this session.
    private func addPodcast(_ podcast: iTunesPodcast) {
        guard let feedUrl = podcast.feedUrl else { return }
        manager.addFeed(title: podcast.trackName, url: feedUrl, category: "")
        addedIDs.insert(podcast.id)
    }
}

// MARK: - Podcast Search Row

/// A single row in the search results list, showing artwork, title, author, and an add button.
/// The add button switches to a green checkmark once the podcast has been added this session.
private struct PodcastSearchRow: View {
    let podcast: iTunesPodcast
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let artworkURLString = podcast.artworkUrl100, let url = URL(string: artworkURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color(NSColor.controlBackgroundColor)
                    }
                }
                .frame(width: 44, height: 44)
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.trackName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(podcast.artistName)
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Button {
                if !isAdded { onAdd() }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isAdded ? .green : .accentColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isAdded ? "Already added" : "Add to PodWang")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - OPML Document

/// A `FileDocument` wrapping an OPML XML string for use with SwiftUI's `fileExporter`.
/// Saved as `.xml` for maximum compatibility with other podcast applications.
struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
