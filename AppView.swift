// AppView.swift v3.2
// Root view and all episode-related views for PodWang.
//
// View hierarchy:
//   AppView
//   ├── SetupView          — shown on first launch before a downloads folder is chosen
//   └── NavigationSplitView
//       ├── SidebarView    — feed list (defined in SidebarView.swift)
//       └── EpisodeDetailView
//           ├── EpisodeRowView      — one row per episode
//           ├── DownloadButtonView  — idle / downloading / downloaded states
//           └── PlayerBarView       — persistent playback controls at the bottom

import SwiftUI
import UniformTypeIdentifiers

// MARK: - App View

/// Root view. Switches between SetupView (no folder chosen) and the main
/// NavigationSplitView once storage is configured.
struct AppView: View {
    @StateObject var manager = PodWangManager()
    @State private var selectedFeed: Feed?
    @State private var searchText = ""

    @State private var showingFilePicker   = false
    @State private var showingFileExporter = false
    @State private var opmlDoc: OPMLDocument?

    var body: some View {
        Group {
            if manager.isStorageConfigured {
                NavigationSplitView {
                    SidebarView(
                        manager: manager,
                        selectedFeed: $selectedFeed,
                        searchText: $searchText,
                        showingFilePicker: $showingFilePicker,
                        showingFileExporter: $showingFileExporter,
                        opmlDoc: $opmlDoc
                    )
                    .searchable(text: $searchText, placement: .sidebar)
                } detail: {
                    if let feed = selectedFeed {
                        EpisodeDetailView(manager: manager, feed: feed)
                    } else {
                        EmptyDetailView()
                    }
                }
                .navigationTitle(selectedFeed?.title ?? "PodWang")
            } else {
                SetupView(manager: manager)
            }
        }
        // File importer for OPML/XML import — presented from the sidebar button.
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.xml],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first { manager.importFromOPML(url: url) }
        }
        // File exporter for OPML/XML export — document is prepared by the sidebar button.
        .fileExporter(
            isPresented: $showingFileExporter,
            document: opmlDoc,
            contentType: .xml,
            defaultFilename: "PodWang Backup"
        ) { _ in }
    }
}

// MARK: - Setup View

/// Shown on first launch. Prompts the user to choose a parent folder for downloads.
/// Required for sandboxed file access via security-scoped bookmarks.
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

/// Placeholder shown in the detail column when no feed is selected.
/// Uses the app icon as a subtle blurred background for visual continuity.
private struct EmptyDetailView: View {
    var body: some View {
        ZStack {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(100)
                    .opacity(0.1)
                    .blur(radius: 5)
            }
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a Podcast")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Episode Detail View

/// Shows the episode list for a selected feed, with a blurred artwork background,
/// toolbar sort/download controls, and the persistent player bar at the bottom.
struct EpisodeDetailView: View {
    @ObservedObject var manager: PodWangManager
    let feed: Feed
    @State private var showingDownloadAllAlert = false

    var body: some View {
        ZStack {
            // Blurred feed artwork shown subtly behind the episode list.
            if let imageURL = manager.currentFeedImageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                            .padding(100).opacity(0.1).blur(radius: 5)
                    case .failure:
                        Image(systemName: "photo").opacity(0.05)
                    case .empty:
                        ProgressView().opacity(0.2)
                    @unknown default:
                        EmptyView()
                    }
                }
                .id(imageURL) // Forces a refresh when switching between podcasts.
            }

            VStack(spacing: 0) {
                if manager.isFetching {
                    Spacer()
                    ProgressView("Fetching Episodes…")
                    Spacer()
                } else {
                    List(manager.sortedEpisodes) { episode in
                        EpisodeRowView(manager: manager, episode: episode, feedTitle: feed.title)
                    }
                    .scrollContentBackground(.hidden) // Lets the artwork background show through.
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingDownloadAllAlert = true } label: {
                                Text("Download All")
                            }
                            .buttonStyle(.bordered)
                            .disabled(manager.sortedEpisodes.isEmpty)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button { manager.sortNewestFirst.toggle() } label: {
                                Label("Sort", systemImage: manager.sortNewestFirst ? "arrow.up.circle" : "arrow.down.circle")
                            }
                        }
                    }
                    .alert("Download All Episodes?", isPresented: $showingDownloadAllAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Download") {
                            for episode in manager.sortedEpisodes where episode.localFileName == nil {
                                manager.download(episode, from: feed.title)
                            }
                        }
                    } message: {
                        Text("This will attempt to download all episodes for '\(feed.title)'.")
                    }
                }

                PlayerBarView(manager: manager)
            }
        }
        .onAppear { manager.fetchEpisodes(for: feed) }
        .onChange(of: feed) { _, newFeed in manager.fetchEpisodes(for: newFeed) }
    }
}

// MARK: - Episode Row View

/// A single row in the episode list, showing title, date, download state, and play button.
private struct EpisodeRowView: View {
    @ObservedObject var manager: PodWangManager
    let episode: Episode
    let feedTitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title).font(.headline).lineLimit(2)
                if let date = episode.pubDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            DownloadButtonView(manager: manager, episode: episode, feedTitle: feedTitle)
                .padding(.trailing, 8)

            let isCurrentAndPlaying = manager.currentPlayingEpisode?.id == episode.id && manager.isPlaying
            Button { manager.play(episode) } label: {
                Image(systemName: isCurrentAndPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Download Button View

/// Renders one of three states for an episode's download control:
///   1. Downloaded  — green checkmark + Finder reveal button
///   2. Downloading — circular progress ring with percentage label + cancel button
///   3. Idle        — download arrow button
private struct DownloadButtonView: View {
    @ObservedObject var manager: PodWangManager
    let episode: Episode
    let feedTitle: String

    var body: some View {
        if let relativePath = episode.localFileName {
            // State 1: file is on disk.
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Button {
                    let url = manager.effectiveDownloadsURL().appendingPathComponent(relativePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }

        } else if let progress = manager.downloadProgress[episode.id] {
            // State 2: download in progress — show ring + cancel.
            HStack(spacing: 8) {
                ZStack {
                    // Track ring
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
                    // Progress ring, starting from 12 o'clock
                    Circle()
                        .trim(from: 0, to: progress.fractionCompleted)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress.fractionCompleted)
                    // Percentage label
                    Text("\(Int(progress.fractionCompleted * 100))%")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 28, height: 28)

                Button { manager.cancelDownload(for: episode) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel download")
            }

        } else {
            // State 3: not yet downloaded.
            Button { manager.download(episode, from: feedTitle) } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .help("Download episode")
        }
    }
}

// MARK: - Player Bar View

/// Persistent playback bar shown at the bottom of the detail view whenever
/// an episode is loaded. Includes title, scrubber, time labels, and transport controls.
struct PlayerBarView: View {
    @ObservedObject var manager: PodWangManager

    var body: some View {
        if let playing = manager.currentPlayingEpisode {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 8) {

                    // Episode title and dismiss button
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

                    // Scrubber and time labels
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(get: { manager.currentTime }, set: { manager.seek(to: $0) }),
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

                    // Transport controls: skip back 60s, skip back 30s, play/pause, skip forward 30s, skip forward 60s
                    HStack(spacing: 25) {
                        Button { manager.skip(seconds: -60) } label: { Image(systemName: "gobackward.60").font(.title3) }
                        Button { manager.skip(seconds: -30) } label: { Image(systemName: "gobackward.30").font(.title3) }
                        Button { manager.play(playing) } label: {
                            Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title).frame(width: 40)
                        }
                        Button { manager.skip(seconds: 30) } label: { Image(systemName: "goforward.30").font(.title3) }
                        Button { manager.skip(seconds: 60) } label: { Image(systemName: "goforward.60").font(.title3) }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 15)
                }
                .background(.ultraThinMaterial)
            }
        }
    }
}
