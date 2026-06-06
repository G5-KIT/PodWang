// SidebarAdditions.swift
// Sidebar management controls and the OPML file document type.
//
// Podcast section (unchanged from v3.3):
//   ManagementPopover → PodcastSearchPopover / addPodcastPopover / Import / Export / Reset
//
// Radio section (new):
//   RadioManagementPopover → RadioSearchPopover (radio-browser.info) / AddStationPopover
//
// radio-browser.info is a free, open API requiring no key.
// We resolve the nearest mirror at startup via the DNS SRV helper endpoint, then hit
//   GET /json/stations/search?name=...&limit=40&hidebroken=true&order=votes&reverse=true
// Responses are JSON arrays of station objects.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - iTunes Search Result

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

private struct iTunesResponse: Decodable {
    let results: [iTunesPodcast]
}

// MARK: - Management Popover (Podcasts)

struct ManagementPopover: View {
    @ObservedObject var manager: PodWangManager

    @State private var showingSearchPopover = false
    @State private var showingAddPopover    = false
    @State private var newTitle             = ""
    @State private var newURL               = ""
    @State private var newCategory          = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            Button { showingSearchPopover = true } label: {
                Label("Find Podcasts…", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingSearchPopover, arrowEdge: .trailing) {
                PodcastSearchPopover(manager: manager)
            }

            Button { showingAddPopover = true } label: {
                Label("Add Podcast…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingAddPopover, arrowEdge: .trailing) {
                addPodcastPopover
            }

            Divider().padding(.horizontal, 8)

            Button(role: .destructive) {
                manager.resetStorageLocation()
            } label: {
                Label("Reset Storage", systemImage: "folder.badge.minus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }

    private var addPodcastPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Podcast").font(.headline)
            TextField("Name",               text: $newTitle)
            TextField("RSS URL",            text: $newURL)
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

private struct PodcastSearchPopover: View {
    @ObservedObject var manager: PodWangManager

    @State private var searchText  = ""
    @State private var results     = [iTunesPodcast]()
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var addedIDs    = Set<Int>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                Text(error).foregroundColor(.secondary).font(.caption).padding()
            } else if results.isEmpty && !isSearching && !searchText.isEmpty {
                Text("No results found.").foregroundColor(.secondary).font(.caption).padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { podcast in
                            PodcastSearchRow(
                                podcast: podcast,
                                isAdded: addedIDs.contains(podcast.id)
                            ) { addPodcast(podcast) }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            Divider()

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
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else { results = []; return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if newValue == searchText { performSearch() }
            }
        }
    }

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
                    URLQueryItem(name: "country", value: "us")
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

    private func addPodcast(_ podcast: iTunesPodcast) {
        guard let feedUrl = podcast.feedUrl else { return }
        manager.addFeed(title: podcast.trackName, url: feedUrl, category: "")
        addedIDs.insert(podcast.id)
    }
}

// MARK: - Podcast Search Row

private struct PodcastSearchRow: View {
    let podcast: iTunesPodcast
    let isAdded: Bool
    let onAdd: () -> Void

    @State private var showingDescription = false

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
                .frame(width: 44, height: 44).cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.trackName).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(podcast.artistName).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            Spacer()

            Button { showingDescription = true } label: {
                Image(systemName: "info.circle").foregroundColor(.secondary).font(.body)
            }
            .buttonStyle(.plain)
            .help("Show podcast description")
            .popover(isPresented: $showingDescription, arrowEdge: .leading) {
                PodcastDescriptionPopover(podcast: podcast)
            }

            Button { if !isAdded { onAdd() } } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isAdded ? .green : .accentColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isAdded ? "Already added" : "Add to PodWang")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Podcast Description Popover

private struct PodcastDescriptionPopover: View {
    let podcast: iTunesPodcast

    @State private var description: String?
    @State private var isLoading = true
    @State private var failed    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let artworkURLString = podcast.artworkUrl100, let url = URL(string: artworkURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: Color(NSColor.controlBackgroundColor)
                        }
                    }
                    .frame(width: 44, height: 44).cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(podcast.trackName).font(.headline).lineLimit(2)
                    Text(podcast.artistName).font(.caption).foregroundColor(.secondary)
                }
            }
            Divider()
            if isLoading {
                HStack { Spacer(); ProgressView("Loading…"); Spacer() }.padding(.vertical, 8)
            } else if failed {
                Text("Could not load description.").font(.caption).foregroundColor(.secondary)
            } else {
                ScrollView {
                    Text(description ?? "No description available.")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 260)
        .task { await fetchDescription() }
    }

    private func fetchDescription() async {
        guard let feedURLString = podcast.feedUrl, let feedURL = URL(string: feedURLString) else {
            isLoading = false; failed = true; return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let parser    = XMLParser(data: data)
            let delegate  = ChannelDescriptionParser()
            parser.delegate = delegate
            parser.parse()
            await MainActor.run {
                let raw = delegate.channelDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                description = raw.isEmpty ? nil : raw
                isLoading   = false
            }
        } catch {
            await MainActor.run { failed = true; isLoading = false }
        }
    }
}

// MARK: - Channel Description Parser

private class ChannelDescriptionParser: NSObject, XMLParserDelegate {
    var channelDescription: String?
    private var currentElement = ""
    private var collectedText  = ""
    private var insideItem     = false

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        currentElement = el
        if el == "item" { insideItem = true; parser.abortParsing() }
        if el == "description" && !insideItem { collectedText = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        if currentElement == "description" && !insideItem { collectedText += s }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "description" && !insideItem {
            let stripped = collectedText
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            channelDescription = stripped.isEmpty ? nil : stripped
        }
        currentElement = ""
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Radio Management Popover
// ═══════════════════════════════════════════════════════════════════════

/// Gear-menu popover shown in radio mode.
struct RadioManagementPopover: View {
    @ObservedObject var manager: PodWangManager

    @State private var showingSearch = false
    @State private var showingAdd    = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            Button { showingSearch = true } label: {
                Label("Find Stations…", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingSearch, arrowEdge: .trailing) {
                RadioSearchPopover(manager: manager)
            }

            Button { showingAdd = true } label: {
                Label("Add Station…", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
            .popover(isPresented: $showingAdd, arrowEdge: .trailing) {
                AddStationPopover(manager: manager, isPresented: $showingAdd)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }
}

// MARK: - Radio-Browser Station Model

/// A single station result from the radio-browser.info API.
private struct RadioBrowserStation: Identifiable, Decodable {
    let id: String
    let name: String
    let url_resolved: String   // The resolved, playable stream URL.
    let favicon: String?
    let tags: String?
    let country: String?
    let bitrate: Int?
    let votes: Int?

    enum CodingKeys: String, CodingKey {
        case id           = "stationuuid"
        case name
        case url_resolved
        case favicon
        case tags
        case country
        case bitrate
        case votes
    }
}

// MARK: - Radio Search Popover

/// Searches radio-browser.info by station name as the user types.
/// Results are ranked by votes (most popular first).
struct RadioSearchPopover: View {
    @ObservedObject var manager: PodWangManager

    @State private var searchText  = ""
    @State private var results     = [RadioBrowserStation]()
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var addedIDs    = Set<String>()

    /// The radio-browser.info API mirror to use. Resolved once on appear.
    @State private var apiBase = "https://de1.api.radio-browser.info"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search stations…", text: $searchText)
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
                Text(error).foregroundColor(.secondary).font(.caption).padding()
            } else if results.isEmpty && !isSearching && !searchText.isEmpty {
                Text("No stations found.").foregroundColor(.secondary).font(.caption).padding()
            } else if results.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "radio").font(.largeTitle).foregroundColor(.secondary)
                    Text("Type to search stations worldwide")
                        .font(.caption).foregroundColor(.secondary)
                    Text("Powered by radio-browser.info")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { station in
                            RadioSearchRow(
                                station: station,
                                isAdded: addedIDs.contains(station.id) ||
                                         manager.radioStations.contains(where: { $0.streamURL == station.url_resolved })
                            ) { addStation(station) }
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }

            Divider()

            Button {
                NSWorkspace.shared.open(URL(string: "https://www.radio-browser.info/")!)
            } label: {
                HStack {
                    Image(systemName: "safari").foregroundColor(.secondary)
                    Text("Browse radio-browser.info…").font(.caption).foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: 380, height: 500)
        .task { await resolveAPIBase() }
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty else { results = []; return }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if newValue == searchText { performSearch() }
            }
        }
    }

    // MARK: - API mirror resolution

    /// radio-browser.info recommends resolving the DNS round-robin to pick a nearby mirror.
    /// We just use a stable known mirror; if it fails we fall back to the community default.
    private func resolveAPIBase() async {
        let candidates = [
            "https://de1.api.radio-browser.info",
            "https://nl1.api.radio-browser.info",
            "https://at1.api.radio-browser.info"
        ]
        for candidate in candidates {
            guard let url = URL(string: "\(candidate)/json/stats") else { continue }
            if let _ = try? await URLSession.shared.data(from: url) {
                await MainActor.run { apiBase = candidate }
                return
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching  = true
        errorMessage = nil

        Task {
            do {
                var components = URLComponents(string: "\(apiBase)/json/stations/search")!
                components.queryItems = [
                    URLQueryItem(name: "name",        value: query),
                    URLQueryItem(name: "limit",       value: "40"),
                    URLQueryItem(name: "hidebroken",  value: "true"),
                    URLQueryItem(name: "order",       value: "votes"),
                    URLQueryItem(name: "reverse",     value: "true"),
                ]
                var request = URLRequest(url: components.url!)
                // radio-browser.info requires a User-Agent.
                request.setValue("PodWang/1.0", forHTTPHeaderField: "User-Agent")

                let (data, _) = try await URLSession.shared.data(for: request)
                let stations  = try JSONDecoder().decode([RadioBrowserStation].self, from: data)

                await MainActor.run {
                    // Filter out stations without a usable stream URL.
                    results     = stations.filter { !$0.url_resolved.isEmpty }
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

    private func addStation(_ station: RadioBrowserStation) {
        let newStation = RadioStation(
            name:       station.name,
            streamURL:  station.url_resolved,
            faviconURL: station.favicon.flatMap { $0.isEmpty ? nil : $0 },
            tags:       station.tags ?? "",
            country:    station.country.flatMap { $0.isEmpty ? nil : $0 },
            bitrate:    station.bitrate
        )
        manager.addRadioStation(newStation)
        addedIDs.insert(station.id)
    }
}

// MARK: - Radio Search Row

private struct RadioSearchRow: View {
    let station: RadioBrowserStation
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Favicon or placeholder
            Group {
                if let faviconString = station.favicon,
                   !faviconString.isEmpty,
                   let url = URL(string: faviconString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                        default: radioPlaceholder
                        }
                    }
                } else {
                    radioPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    if let country = station.country, !country.isEmpty {
                        Text(country).font(.caption).foregroundColor(.secondary)
                    }
                    if let bitrate = station.bitrate, bitrate > 0 {
                        Text("·").font(.caption).foregroundColor(.secondary)
                        Text("\(bitrate) kbps").font(.caption).foregroundColor(.secondary)
                    }
                }

                if let tags = station.tags, !tags.isEmpty {
                    Text(tags.split(separator: ",").prefix(3).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button { if !isAdded { onAdd() } } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundColor(isAdded ? .green : .accentColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isAdded ? "Already added" : "Add station")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var radioPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor))
            Image(systemName: "radio").foregroundColor(.accentColor)
        }
    }
}

// MARK: - Add Station Popover (manual entry)

/// Manual form for adding a station by name and direct stream URL.
struct AddStationPopover: View {
    @ObservedObject var manager: PodWangManager
    @Binding var isPresented: Bool

    @State private var name       = ""
    @State private var streamURL  = ""
    @State private var tags       = ""
    @State private var country    = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Station").font(.headline)

            TextField("Station name",             text: $name)
            TextField("Stream URL (mp3, aac…)",  text: $streamURL)
            TextField("Genre / tags (optional)", text: $tags)
            TextField("Country (optional)",      text: $country)

            HStack {
                Button("Cancel") {
                    isPresented = false
                    clearFields()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    let station = RadioStation(
                        name:      name,
                        streamURL: streamURL,
                        tags:      tags,
                        country:   country.isEmpty ? nil : country
                    )
                    manager.addRadioStation(station)
                    isPresented = false
                    clearFields()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || streamURL.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(width: 300)
    }

    private func clearFields() {
        name = ""; streamURL = ""; tags = ""; country = ""
    }
}

// MARK: - OPML Document

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
