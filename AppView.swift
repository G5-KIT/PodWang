// AppView.swift
// PodWang — a native macOS podcast client.
//
// View hierarchy:
//   AppView
//   ├── SetupView                — first-run folder selection
//   └── NavigationSplitView
//       ├── SidebarView          — Podcasts / Radio mode toggle + lists
//       └── detail pane
//           ├── EpisodeDetailView    — podcast episode list + player bar
//           ├── RadioDetailView      — radio station now-playing view + radio bar
//           └── EmptyDetailView      — placeholder when nothing is selected

import SwiftUI
import UniformTypeIdentifiers

// MARK: - AppView

struct AppView: View {
    @StateObject var manager = PodWangManager()

    // Podcast selection
    @State private var selectedFeed: Feed?
    @State private var searchText = ""

    // Radio selection
    @State private var selectedStation: RadioStation?
    @State private var radioSearchText = ""

    var body: some View {
        Group {
            if manager.isStorageConfigured {
                NavigationSplitView {
                    SidebarView(
                        manager:            manager,
                        selectedFeed:       $selectedFeed,
                        searchText:         $searchText,
                        selectedStation:    $selectedStation,
                        radioSearchText:    $radioSearchText
                    )
                    .searchable(text: $searchText, placement: .sidebar, prompt: "Search Feeds")
                } detail: {
                    if let station = selectedStation {
                        RadioDetailView(manager: manager, station: station)
                    } else if let feed = selectedFeed {
                        EpisodeDetailView(manager: manager, feed: feed)
                    } else {
                        EmptyDetailView()
                    }
                }
                .navigationTitle(
                    selectedStation?.name ?? selectedFeed?.title ?? "PodWang"
                )
            } else {
                SetupView(manager: manager)
            }
        }
        .focusedSceneObject(manager)
        // When user taps a station in the sidebar, clear the feed selection (and vice versa),
        // so only one detail view is active at a time.
        .onChange(of: selectedStation) { _, newValue in
            if newValue != nil { selectedFeed = nil }
        }
        .onChange(of: selectedFeed) { _, newValue in
            if newValue != nil { selectedStation = nil }
        }
    }
}

// MARK: - Setup View

private struct SetupView: View {
    let manager: PodWangManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Setup Storage Location").font(.largeTitle).bold()
                Text("Select a folder for PodWang to keep your podcasts organized.")
                    .foregroundColor(.secondary)
            }

            Button { manager.selectDownloadsFolder() } label: {
                Text("Choose Parent Folder…").frame(width: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Empty Detail View

private struct EmptyDetailView: View {
    var body: some View {
        ZStack {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding(100).opacity(0.1).blur(radius: 5)
            }
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48)).foregroundColor(.secondary)
                Text("Select a Podcast or Station")
                    .font(.title2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Episode Detail View

struct EpisodeDetailView: View {
    @ObservedObject var manager: PodWangManager
    let feed: Feed
    @State private var showingDownloadAllAlert = false
    @State private var episodeSearchText = ""

    private var filteredEpisodes: [Episode] {
        guard !episodeSearchText.isEmpty else { return manager.sortedEpisodes }
        return manager.sortedEpisodes.filter {
            $0.title.localizedCaseInsensitiveContains(episodeSearchText)
        }
    }

    var body: some View {
        ZStack {
            // Blurred artwork background.
            if let imageURL = manager.currentFeedImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                            .padding(100).opacity(0.1).blur(radius: 5)
                    case .failure: appIconBackground
                    case .empty:   ProgressView().opacity(0.2)
                    @unknown default: EmptyView()
                    }
                }
                .id(imageURL)
            } else {
                appIconBackground
            }

            VStack(spacing: 0) {
                if manager.isFetching {
                    Spacer()
                    ProgressView("Fetching Episodes…")
                    Spacer()
                } else {
                    List(filteredEpisodes) { episode in
                        EpisodeRowView(manager: manager, episode: episode, feedTitle: feed.title)
                    }
                    .searchable(text: $episodeSearchText, placement: .toolbar, prompt: "Search Episodes")
                    .scrollContentBackground(.hidden)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingDownloadAllAlert = true } label: {
                                Text("Download All")
                            }
                            .buttonStyle(.bordered)
                            .disabled(filteredEpisodes.isEmpty)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button { manager.sortNewestFirst.toggle() } label: {
                                Label("Sort", systemImage: manager.sortNewestFirst
                                      ? "arrow.up.circle" : "arrow.down.circle")
                            }
                        }
                    }
                    .alert("Download All Episodes?", isPresented: $showingDownloadAllAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Download") {
                            for episode in filteredEpisodes {
                                manager.download(episode, from: feed.title)
                            }
                        }
                    } message: {
                        Text("This will download \(filteredEpisodes.count) episode(s). Downloads run in the background.")
                    }
                }

                // Podcast player bar — shown only when a podcast is playing.
                PodcastPlayerBar(manager: manager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { manager.fetchEpisodes(for: feed) }
        // Re-fetch when the user selects a different feed. onAppear alone is not enough
        // because SwiftUI reuses EpisodeDetailView across feed changes without unmounting it.
        .onChange(of: feed) { _, newFeed in manager.fetchEpisodes(for: newFeed) }
    }

    private var appIconBackground: some View {
        Group {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding(100).opacity(0.1).blur(radius: 5)
            }
        }
    }
}

// MARK: - Radio Detail View

/// Shown when a radio station is selected. Displays station info and playback controls.
/// No scrubber or skip controls — live streams have no seekable duration.
struct RadioDetailView: View {
    @ObservedObject var manager: PodWangManager
    let station: RadioStation

    /// True when this specific station is the current one.
    private var isCurrent: Bool { manager.currentRadioStation?.id == station.id }

    var body: some View {
        ZStack {
            // Blurred favicon background, or app icon fallback.
            if let faviconURL = station.faviconURL, let url = URL(string: faviconURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                            .padding(120).opacity(0.12).blur(radius: 8)
                    default: appIconBackground
                    }
                }
                .id(faviconURL)
            } else {
                appIconBackground
            }

            VStack(spacing: 0) {
                Spacer()

                // Station artwork
                Group {
                    if let faviconURL = station.faviconURL, let url = URL(string: faviconURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                radioArtworkPlaceholder
                            }
                        }
                    } else {
                        radioArtworkPlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .cornerRadius(16)
                .shadow(radius: 6)

                Spacer().frame(height: 24)

                // Station name & metadata
                Text(station.name)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)

                if let country = station.country, !country.isEmpty {
                    Text(country)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                if !station.tags.isEmpty {
                    Text(station.tags.split(separator: ",").prefix(4)
                            .map { $0.trimmingCharacters(in: .whitespaces).capitalized }
                            .joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                if let bitrate = station.bitrate, bitrate > 0 {
                    Text("\(bitrate) kbps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                Spacer().frame(height: 40)

                // Play / pause button
                Button {
                    manager.playRadio(station)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 72, height: 72)
                            .shadow(color: .accentColor.opacity(0.4), radius: 8)
                        Image(systemName: isCurrent && manager.isRadioPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .help(isCurrent && manager.isRadioPlaying ? "Pause" : "Play")

                Spacer().frame(height: 16)

                // Live indicator badge
                HStack(spacing: 5) {
                    Circle().fill(isCurrent && manager.isRadioPlaying ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption).bold()
                        .foregroundColor(isCurrent && manager.isRadioPlaying ? .red : .secondary)
                }

                Spacer()

                // Radio player bar at the bottom (only when this station is active).
                RadioPlayerBar(manager: manager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appIconBackground: some View {
        Group {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable().aspectRatio(contentMode: .fit)
                    .padding(100).opacity(0.08).blur(radius: 5)
            }
        }
    }

    private var radioArtworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.accentColor.opacity(0.15))
            Image(systemName: "radio")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Episode Row View

struct EpisodeRowView: View {
    @ObservedObject var manager: PodWangManager
    let episode: Episode
    let feedTitle: String

    @State private var showingNotes = false

    private func formattedDuration(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if raw.contains(":") { return raw }
        guard let seconds = Double(raw) else { return nil }
        return seconds.formattedAsPlaybackTime
    }

    var body: some View {
        HStack {
            // Episode title and metadata — left side.
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    if let date = episode.pubDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if let dur = formattedDuration(episode.duration) {
                        if episode.pubDate != nil {
                            Text("·").font(.caption).foregroundColor(.secondary)
                        }
                        Text(dur).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Action buttons — right side, matching original order.
            DownloadButtonView(manager: manager, episode: episode, feedTitle: feedTitle)
                .padding(.trailing, 8)

            let isCurrentAndPlaying = manager.currentPlayingEpisode?.id == episode.id && manager.isPlaying
            Button { manager.play(episode) } label: {
                Image(systemName: isCurrentAndPlaying ? "pause.circle" : "play.circle")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            if !episode.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { showingNotes = true } label: {
                    Image(systemName: "info.circle").font(.title).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Show notes")
                .popover(isPresented: $showingNotes, arrowEdge: .trailing) {
                    ShowNotesPopover(episode: episode)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Download Button View

private struct DownloadButtonView: View {
    @ObservedObject var manager: PodWangManager
    let episode: Episode
    let feedTitle: String

    var body: some View {
        if let relativePath = episode.localFileName {
            Button {
                let url = manager.effectiveDownloadsURL().appendingPathComponent(relativePath)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder").font(.title).foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

        } else if let progress = manager.downloadProgress[episode.id] {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progress.fractionCompleted)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress.fractionCompleted)
                    Text("\(Int(progress.fractionCompleted * 100))%")
                        .font(.system(size: 7, weight: .medium)).foregroundColor(.secondary)
                }
                .frame(width: 28, height: 28)

                Button { manager.cancelDownload(for: episode) } label: {
                    Image(systemName: "xmark.circle").font(.title).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }

        } else {
            Button { manager.download(episode, from: feedTitle) } label: {
                Image(systemName: "arrow.down.circle").font(.title).foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Download episode")
        }
    }
}

// MARK: - Podcast Player Bar

/// Persistent playback bar for podcast episodes.
/// Shows title, scrubber, elapsed/remaining time, and skip controls.
/// Only visible when an episode is loaded.
struct PodcastPlayerBar: View {
    @ObservedObject var manager: PodWangManager

    var body: some View {
        if let playing = manager.currentPlayingEpisode {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 8) {
                    HStack {
                        Text(playing.title)
                            .font(.caption).bold().lineLimit(1).foregroundColor(.secondary)
                        Spacer()
                        Button { manager.stop() } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Stop playback")
                    }
                    .padding([.horizontal, .top])

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { manager.currentTime },
                                set: { manager.seek(to: $0) }
                            ),
                            in: 0...max(1, manager.duration)
                        )
                        .controlSize(.small)

                        HStack {
                            Text(manager.currentTime.formattedAsPlaybackTime)
                            Spacer()
                            Text(manager.duration.formattedAsPlaybackTime)
                        }
                        .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 25) {
                        Button { manager.skip(seconds: -60) } label: { Image(systemName: "gobackward.60").font(.title3) }
                        Button { manager.skip(seconds: -30) } label: { Image(systemName: "gobackward.30").font(.title3) }
                        Button { manager.play(playing) } label: {
                            Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title).frame(width: 40)
                        }
                        Button { manager.skip(seconds: 30)  } label: { Image(systemName: "goforward.30").font(.title3) }
                        Button { manager.skip(seconds: 60)  } label: { Image(systemName: "goforward.60").font(.title3) }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 15)
                }
                .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Radio Player Bar

/// Minimal playback bar shown at the bottom of RadioDetailView when a station is active.
/// Live streams have no duration so there is no scrubber or skip controls — just the
/// station name, a live badge, and a stop button.
struct RadioPlayerBar: View {
    @ObservedObject var manager: PodWangManager

    var body: some View {
        if let station = manager.currentRadioStation {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {

                    // Live indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(manager.isRadioPlaying ? Color.red : Color.gray)
                            .frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.caption2).bold()
                            .foregroundColor(manager.isRadioPlaying ? .red : .secondary)
                    }

                    Text(station.name)
                        .font(.caption).bold()
                        .lineLimit(1)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Play / pause
                    Button {
                        manager.playRadio(station)
                    } label: {
                        Image(systemName: manager.isRadioPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help(manager.isRadioPlaying ? "Pause" : "Resume")

                    // Stop
                    Button { manager.stopRadio() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Stop radio")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Show Notes Popover

private struct ShowNotesPopover: View {
    let episode: Episode

    private var cleanedNotes: String {
        var text = episode.description
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&lsquo;", "'"), ("&rsquo;", "'"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(episode.title).font(.headline).lineLimit(3)
            Divider()
            ScrollView {
                Text(cleanedNotes.isEmpty ? "No show notes available." : cleanedNotes)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 380, height: 320)
    }
}
