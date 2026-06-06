// PodWangManager.swift
// Central manager for all app state and business logic.
// Marked @MainActor so all @Published state updates happen on the main thread.
// Inherits from NSObject to satisfy URLSessionDownloadDelegate conformance.

import Foundation
import SwiftUI
import Combine
import AVFoundation

// MARK: - Download Progress

/// Snapshot of a single episode's in-flight download state.
/// Published via `downloadProgress[episodeID]` and consumed by `DownloadButtonView`.
struct DownloadProgress {
    var fractionCompleted: Double  // 0.0 – 1.0
    var bytesWritten: Int64
    var bytesExpected: Int64
}

// MARK: - PodWangManager

@MainActor
class PodWangManager: NSObject, ObservableObject {

    // MARK: Published state — Podcasts

    /// The user's saved podcast feeds. Persisted to disk on every change via `didSet`.
    @Published var feeds: [Feed] = [] {
        didSet { saveFeeds() }
    }

    /// Episodes for the currently selected feed, populated by `fetchEpisodes(for:)`.
    @Published var selectedFeedEpisodes: [Episode] = []

    /// Artwork URL for the currently selected feed, used as the detail view background.
    @Published var currentFeedImageURL: String?

    /// True while an RSS fetch is in progress.
    @Published var isFetching = false

    /// Controls episode list sort order. True = newest first.
    @Published var sortNewestFirst = true

    /// Per-episode download progress. Entries are added when a download starts
    /// and removed when it completes or is cancelled.
    @Published var downloadProgress: [UUID: DownloadProgress] = [:]

    // MARK: Published state — Radio

    /// The user's saved radio stations. Persisted to disk on every change.
    @Published var radioStations: [RadioStation] = [] {
        didSet { saveRadioStations() }
    }

    /// The radio station currently being streamed, if any.
    @Published var currentRadioStation: RadioStation?

    /// True when radio is actively playing (distinct from podcast playback).
    @Published var isRadioPlaying = false

    // MARK: Published state — Shared playback

    /// The episode currently loaded into the player (may be paused). Nil during radio.
    @Published var currentPlayingEpisode: Episode?

    /// True when the podcast player is actively playing.
    @Published var isPlaying = false

    /// Current playback position in seconds (podcast only).
    @Published var currentTime: Double = 0

    /// Total duration of the current item in seconds (podcast only).
    @Published var duration: Double = 0

    /// The user-selected parent folder for downloads.
    @Published var downloadsFolderURL: URL?

    // MARK: Private state

    private var player: AVPlayer?
    private var radioPlayer: AVPlayer?
    private var timeObserver: Any?

    /// Maps episode ID → active URLSessionDownloadTask for cancellation support.
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]

    /// Delegate-based URLSession for downloads. Lazy so `self` is available as delegate.
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    // MARK: - Computed properties

    var isStorageConfigured: Bool { downloadsFolderURL != nil }

    var sortedEpisodes: [Episode] {
        selectedFeedEpisodes.sorted { a, b in
            guard let dateA = a.pubDate, let dateB = b.pubDate else { return false }
            return sortNewestFirst ? dateA > dateB : dateA < dateB
        }
    }

    func getCategories(for feedList: [Feed]) -> [String] {
        let allCats = feedList.map {
            $0.category.trimmingCharacters(in: .whitespaces).isEmpty ? "Uncategorized" : $0.category
        }
        let unique = Array(Set(allCats)).sorted()
        return unique.isEmpty && !feedList.isEmpty ? ["Uncategorized"] : unique
    }

    /// Sorted, deduplicated list of primary tags used across all saved radio stations.
    var radioTags: [String] {
        let allTags = radioStations.map { $0.primaryTag }
        return Array(Set(allTags)).sorted()
    }

    // MARK: - Storage paths

    lazy var saveFolderURL: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodWang")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    private var feedsSaveURL: URL         { saveFolderURL.appendingPathComponent("feeds.json") }
    private var radioStationsSaveURL: URL { saveFolderURL.appendingPathComponent("radio_stations.json") }

    // Keep the old name working for the download delegate which references it directly.
    private var saveURL: URL { feedsSaveURL }

    // MARK: - Init

    override init() {
        super.init()
        loadSavedFolderPermission()
        loadFeeds()
        loadRadioStations()
    }

    // MARK: - Folder permission

    func selectDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a parent folder for PodWang downloads."
        panel.prompt  = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            saveFolderPermission(url: url)
            loadSavedFolderPermission()
        }
    }

    func resetStorageLocation() {
        downloadsFolderURL?.stopAccessingSecurityScopedResource()
        UserDefaults.standard.removeObject(forKey: "DownloadsFolderBookmark")
        downloadsFolderURL = nil
    }

    private func saveFolderPermission(url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: "DownloadsFolderBookmark")
        } catch {
            print("Bookmark error: \(error)")
        }
    }

    private func loadSavedFolderPermission() {
        guard let data = UserDefaults.standard.data(forKey: "DownloadsFolderBookmark") else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveFolderPermission(url: url) }
            if url.startAccessingSecurityScopedResource() {
                downloadsFolderURL = url
            }
        } catch {
            print("Resolve error: \(error)")
        }
    }

    // MARK: - Downloads folder

    func effectiveDownloadsURL() -> URL {
        let base = downloadsFolderURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("PodWang_Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Filename sanitisation

    private func audioExtension(from url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let filedisplay = components?.queryItems?.first(where: { $0.name == "filedisplay" })?.value {
            let ext = (filedisplay as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }
        let pathExt = url.pathExtension.lowercased()
        let validExts = ["mp3", "m4a", "ogg", "aac", "mp4", "wav"]
        return validExts.contains(pathExt) ? pathExt : "mp3"
    }

    private func sanitized(_ string: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return string.components(separatedBy: invalidChars).joined(separator: "_")
    }

    // MARK: - Download

    func download(_ episode: Episode, from feedTitle: String) {
        guard let remoteURL = URL(string: episode.audioURL),
              activeTasks[episode.id] == nil
        else { return }

        let sanitizedFeed    = sanitized(feedTitle)
        let sanitizedEpisode = sanitized(episode.title)
        let ext              = audioExtension(from: remoteURL)
        let destinationName  = "\(sanitizedEpisode).\(ext)"
        let relativePath     = "\(sanitizedFeed)/\(destinationName)"

        let podcastFolder = effectiveDownloadsURL().appendingPathComponent(sanitizedFeed, isDirectory: true)
        try? FileManager.default.createDirectory(at: podcastFolder, withIntermediateDirectories: true)

        let task = downloadSession.downloadTask(with: remoteURL)
        task.taskDescription = "\(episode.id.uuidString)|\(relativePath)"

        activeTasks[episode.id]      = task
        downloadProgress[episode.id] = DownloadProgress(fractionCompleted: 0, bytesWritten: 0, bytesExpected: 0)

        task.resume()
    }

    func cancelDownload(for episode: Episode) {
        activeTasks[episode.id]?.cancel()
        activeTasks.removeValue(forKey: episode.id)
        downloadProgress.removeValue(forKey: episode.id)
    }

    // MARK: - Podcast Playback

    /// Plays the given episode, or toggles play/pause if it is already current.
    /// Stops any active radio stream before starting podcast playback.
    func play(_ episode: Episode) {
        // Only stop radio if it is actually running; don't touch it otherwise.
        if currentRadioStation != nil { stopRadio() }

        if currentPlayingEpisode?.id == episode.id {
            if isPlaying { player?.pause(); isPlaying = false }
            else         { player?.play();  isPlaying = true  }
            return
        }

        stop()
        currentPlayingEpisode = episode

        guard var playURL = URL(string: episode.audioURL) else {
            print("Invalid audio URL for episode: \(episode.title)")
            return
        }

        if let relativePath = episode.localFileName {
            let localURL = effectiveDownloadsURL().appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: localURL.path) {
                playURL = localURL
            }
        }

        player = AVPlayer(url: playURL)
        setupTimeObserver()
        player?.play()
        isPlaying = true
    }

    private func setupTimeObserver() {
        guard let currentPlayer = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        timeObserver = currentPlayer.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if let d = self.player?.currentItem?.duration.seconds, !d.isNaN {
                    self.duration = d
                }
            }
        }
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    func skip(seconds: Double) {
        seek(to: max(0, min(currentTime + seconds, duration)))
    }

    /// Stops podcast playback and resets all podcast player state.
    func stop() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player                = nil
        currentPlayingEpisode = nil
        isPlaying             = false
        currentTime           = 0
        duration              = 0
    }

    // MARK: - Radio Playback

    /// KVO observation token for radio player item status.
    private var radioStatusObservation: NSKeyValueObservation?

    /// Starts streaming `station`, or toggles play/pause if already the current station.
    /// Stops any active podcast playback before starting radio.
    func playRadio(_ station: RadioStation) {
        // Only stop the podcast player if it is actually running.
        if currentPlayingEpisode != nil { stop() }

        if currentRadioStation?.id == station.id {
            if isRadioPlaying {
                radioPlayer?.pause()
                isRadioPlaying = false
            } else {
                radioPlayer?.play()
                isRadioPlaying = true
            }
            return
        }

        stopRadio()

        guard let streamURL = URL(string: station.streamURL) else {
            print("Invalid stream URL for station: \(station.name)")
            return
        }

        currentRadioStation = station

        // Many radio-browser.info streams are plain HTTP. Try upgrading to HTTPS first;
        // if the player item reports .failed, retry with the original HTTP URL.
        // For HTTP-only streams to work you must also add NSAllowsArbitraryLoads to
        // your app's Info.plist (see the radio section of README).
        let playURL: URL
        if streamURL.scheme?.lowercased() == "http",
           var components = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            playURL = components.url ?? streamURL
        } else {
            playURL = streamURL
        }

        startRadioPlayer(with: playURL, fallbackURL: playURL != streamURL ? streamURL : nil)
    }

    /// Creates the AVPlayer for radio, wiring KVO to fall back to HTTP if HTTPS fails.
    private func startRadioPlayer(with url: URL, fallbackURL: URL?) {
        radioStatusObservation?.invalidate()
        radioStatusObservation = nil

        let item   = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        radioPlayer = player

        radioStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if item.status == .failed, let fallback = fallbackURL {
                    print("Radio HTTPS failed, retrying with HTTP: \(fallback)")
                    self.startRadioPlayer(with: fallback, fallbackURL: nil)
                }
            }
        }

        player.play()
        isRadioPlaying = true
    }

    /// Stops the radio player and resets all radio state.
    func stopRadio() {
        radioStatusObservation?.invalidate()
        radioStatusObservation = nil
        radioPlayer?.pause()
        radioPlayer         = nil
        currentRadioStation = nil
        isRadioPlaying      = false
    }

    // MARK: - Feed fetching

    func fetchEpisodes(for feed: Feed) {
        guard let url = URL(string: feed.url) else { return }
        isFetching           = true
        selectedFeedEpisodes = []
        currentFeedImageURL  = nil

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let parser    = XMLParser(data: data)
                let delegate  = RSSParserDelegate()
                parser.delegate = delegate

                if parser.parse() {
                    let episodes = checkLocalFiles(for: delegate.episodes, feedTitle: feed.title)
                    await MainActor.run {
                        self.selectedFeedEpisodes = episodes
                        self.currentFeedImageURL  = delegate.feedImageURL

                        if let imageURL = delegate.feedImageURL,
                           let idx = self.feeds.firstIndex(where: { $0.id == feed.id }) {
                            self.feeds[idx].artworkURL = imageURL
                        }

                        self.isFetching = false
                    }
                } else {
                    await MainActor.run { self.isFetching = false }
                }
            } catch {
                print("Fetch error: \(error)")
                await MainActor.run { self.isFetching = false }
            }
        }
    }

    private func checkLocalFiles(for episodes: [Episode], feedTitle: String) -> [Episode] {
        let sanitizedFeed = sanitized(feedTitle)
        let podcastFolder = effectiveDownloadsURL().appendingPathComponent(sanitizedFeed, isDirectory: true)

        return episodes.map { episode in
            var updated = episode
            let sanitizedEpisode = sanitized(episode.title)
            if let url = URL(string: episode.audioURL) {
                let ext      = audioExtension(from: url)
                let fileName = "\(sanitizedEpisode).\(ext)"
                let localPath = podcastFolder.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: localPath.path) {
                    updated.localFileName = "\(sanitizedFeed)/\(fileName)"
                }
            }
            return updated
        }
    }

    // MARK: - Persistence — Feeds

    func saveFeeds() {
        do {
            let data = try JSONEncoder().encode(feeds)
            try data.write(to: feedsSaveURL)
        } catch {
            print("Save feeds error: \(error)")
        }
    }

    func loadFeeds() {
        guard FileManager.default.fileExists(atPath: feedsSaveURL.path) else { return }
        do {
            let data   = try Data(contentsOf: feedsSaveURL)
            self.feeds = try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("Load feeds error: \(error)")
        }
    }

    func addFeed(title: String, url: String, category: String) {
        feeds.append(Feed(title: title, url: url, category: category))
    }

    func removeFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets) }
    func moveFeed(from src: IndexSet, to dst: Int) { feeds.move(fromOffsets: src, toOffset: dst) }

    // MARK: - Persistence — Radio Stations

    func saveRadioStations() {
        do {
            let data = try JSONEncoder().encode(radioStations)
            try data.write(to: radioStationsSaveURL)
        } catch {
            print("Save radio error: \(error)")
        }
    }

    func loadRadioStations() {
        guard FileManager.default.fileExists(atPath: radioStationsSaveURL.path) else { return }
        do {
            let data          = try Data(contentsOf: radioStationsSaveURL)
            self.radioStations = try JSONDecoder().decode([RadioStation].self, from: data)
        } catch {
            print("Load radio error: \(error)")
        }
    }

    func addRadioStation(_ station: RadioStation) {
        guard !radioStations.contains(where: { $0.streamURL == station.streamURL }) else { return }
        radioStations.append(station)
    }

    func removeRadioStation(at offsets: IndexSet) { radioStations.remove(atOffsets: offsets) }

    // MARK: - OPML

    func generateOPMLString() -> String {
        func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"1.1\"><body>"
        for feed in feeds {
            let t = escaped(feed.title)
            xml += "\n<outline text=\"\(t)\" title=\"\(t)\" type=\"rss\" xmlUrl=\"\(feed.url)\" category=\"\(feed.category)\"/>"
        }
        if !radioStations.isEmpty {
            xml += "\n<outline text=\"Radio Stations\" title=\"Radio Stations\">"
            for station in radioStations {
                let n = escaped(station.name)
                let t = escaped(station.tags)
                let c = escaped(station.country ?? "")
                let f = escaped(station.faviconURL ?? "")
                let b = station.bitrate.map { String($0) } ?? ""
                xml += "\n  <outline text=\"\(n)\" title=\"\(n)\" type=\"radio\" streamUrl=\"\(station.streamURL)\" tags=\"\(t)\" country=\"\(c)\" faviconUrl=\"\(f)\" bitrate=\"\(b)\"/>"
            }
            xml += "\n</outline>"
        }
        xml += "\n</body></opml>"
        return xml
    }

    func importFromOPML(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }

        let parser   = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate

        if parser.parse() {
            for feed in delegate.foundFeeds where !feeds.contains(where: { $0.url == feed.url }) {
                feeds.append(feed)
            }
            for station in delegate.foundStations where !radioStations.contains(where: { $0.streamURL == station.streamURL }) {
                radioStations.append(station)
            }
        }
    }

    /// Opens an NSOpenPanel and imports the chosen OPML/XML file.
    /// Called directly from the File menu command.
    func triggerImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes     = [.xml]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PodWang backup XML file to import."
        panel.prompt  = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFromOPML(url: url)
    }

    /// Opens an NSSavePanel and exports the current feeds and stations as OPML/XML.
    /// Called directly from the File menu command.
    func triggerExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.xml]
        panel.nameFieldStringValue = "PodWang Backup"
        panel.message = "Save your PodWang feeds and radio stations."
        panel.prompt  = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? generateOPMLString().data(using: .utf8)?.write(to: url)
    }
}

// MARK: - URLSessionDownloadDelegate

extension PodWangManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let desc      = downloadTask.taskDescription,
              let idString  = desc.split(separator: "|").first,
              let episodeID = UUID(uuidString: String(idString))
        else { return }

        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        let progress = DownloadProgress(
            fractionCompleted: fraction,
            bytesWritten:  totalBytesWritten,
            bytesExpected: totalBytesExpectedToWrite
        )

        Task { @MainActor in
            self.downloadProgress[episodeID] = progress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let desc = downloadTask.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1)
        guard parts.count == 2,
              let episodeID = UUID(uuidString: String(parts[0]))
        else { return }

        let relativePath = String(parts[1])
        let fm = FileManager.default

        var baseURL: URL
        var isStale = false
        if let bookmarkData = UserDefaults.standard.data(forKey: "DownloadsFolderBookmark"),
           let resolved = try? URL(
               resolvingBookmarkData: bookmarkData,
               options: .withSecurityScope,
               relativeTo: nil,
               bookmarkDataIsStale: &isStale
           ),
           resolved.startAccessingSecurityScopedResource() {
            baseURL = resolved.appendingPathComponent("PodWang_Downloads", isDirectory: true)
        } else {
            baseURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PodWang_Downloads", isDirectory: true)
        }

        let destinationURL = baseURL.appendingPathComponent(relativePath)
        try? fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }

        do {
            try fm.moveItem(at: location, to: destinationURL)
        } catch {
            print("Move error: \(error)")
        }

        Task { @MainActor in
            if let index = self.selectedFeedEpisodes.firstIndex(where: { $0.id == episodeID }) {
                self.selectedFeedEpisodes[index].localFileName = relativePath
            }
            self.activeTasks.removeValue(forKey: episodeID)
            self.downloadProgress.removeValue(forKey: episodeID)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        if let error { print("Download task error: \(error)") }
    }
}

// MARK: - RSS Parser

class RSSParserDelegate: NSObject, XMLParserDelegate {
    var episodes:     [Episode] = []
    var feedImageURL: String?

    private var currentElement  = ""
    private var currentTitle    = ""
    private var currentDesc     = ""
    private var currentAudioURL = ""
    private var currentPubDate  = ""
    private var currentDuration = ""
    private var isInsideItem    = false

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale     = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df
    }()

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        currentElement = el

        if el == "item" {
            isInsideItem    = true
            currentTitle    = ""
            currentDesc     = ""
            currentAudioURL = ""
            currentPubDate  = ""
            currentDuration = ""
        }

        if !isInsideItem, el == "itunes:image", let href = attrs["href"] {
            feedImageURL = href.replacingOccurrences(of: "http://", with: "https://")
        }

        if el == "enclosure", let url = attrs["url"] {
            currentAudioURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) {
        switch currentElement {
        case "title":           currentTitle    += s
        case "description":     currentDesc     += s
        case "pubDate":         currentPubDate  += s
        case "itunes:duration": currentDuration += s
        case "url" where !isInsideItem:
            if feedImageURL == nil { feedImageURL = (feedImageURL ?? "") + s }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        if el == "url" && !isInsideItem, let raw = feedImageURL {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            feedImageURL = trimmed.isEmpty ? nil : trimmed.replacingOccurrences(of: "http://", with: "https://")
        }

        if el == "item" {
            isInsideItem = false
            let rawDuration = currentDuration.trimmingCharacters(in: .whitespacesAndNewlines)
            episodes.append(Episode(
                title:       currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate:     dateFormatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                audioURL:    currentAudioURL,
                description: currentDesc.trimmingCharacters(in: .whitespacesAndNewlines),
                duration:    rawDuration.isEmpty ? nil : rawDuration
            ))
        }

        currentElement = ""
    }
}

// MARK: - OPML Parser

class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var foundFeeds:    [Feed]         = []
    var foundStations: [RadioStation] = []

    // Depth-based group tracking:
    // outlineDepth counts every <outline> open tag.
    // radioGroupDepth is set to outlineDepth when the "Radio Stations" container opens,
    // and cleared when that same depth is reached on a closing tag.
    // This correctly handles self-closing child station outlines, which each fire their
    // own didEndElement — the flag is only cleared when the container's closing tag fires.
    private var outlineDepth:    Int  = 0
    private var radioGroupDepth: Int  = 0
    private var insideRadioGroup: Bool { radioGroupDepth > 0 }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        guard el == "outline" else { return }
        outlineDepth += 1

        let type = attrs["type"] ?? ""

        // Detect the radio stations container — no type, title is "Radio Stations".
        if type.isEmpty, (attrs["text"] == "Radio Stations" || attrs["title"] == "Radio Stations") {
            radioGroupDepth = outlineDepth
            return
        }

        // Radio station child outline.
        if insideRadioGroup, type == "radio",
           let name      = attrs["text"] ?? attrs["title"],
           let streamURL = attrs["streamUrl"],
           !streamURL.isEmpty {
            foundStations.append(RadioStation(
                name:       name,
                streamURL:  streamURL,
                faviconURL: attrs["faviconUrl"].flatMap { $0.isEmpty ? nil : $0 },
                tags:       attrs["tags"] ?? "",
                country:    attrs["country"].flatMap { $0.isEmpty ? nil : $0 },
                bitrate:    attrs["bitrate"].flatMap { Int($0) }
            ))
            return
        }

        // Standard podcast feed outline (ignored when inside the radio group).
        guard !insideRadioGroup, type == "rss",
              let title = attrs["text"] ?? attrs["title"],
              let url   = attrs["xmlUrl"]
        else { return }
        foundFeeds.append(Feed(title: title, url: url, category: attrs["category"] ?? "Uncategorized"))
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        guard el == "outline" else { return }
        // Clear the radio group flag only when the container's own closing tag is reached.
        if outlineDepth == radioGroupDepth {
            radioGroupDepth = 0
        }
        outlineDepth -= 1
    }
}
