// PodWangManager.swift
// PodWang — a native macOS podcast client.
//
// Central manager for all application state and business logic.
// Marked @MainActor so every @Published update happens on the main thread.
// Inherits from NSObject to satisfy URLSessionDownloadDelegate conformance.

import Foundation
import SwiftUI
import Combine
import AVFoundation

// MARK: - Download Progress

/// A snapshot of a single episode's in-flight download state.
/// Keyed by episode UUID in `PodWangManager.downloadProgress` and
/// consumed by `DownloadButtonView` to drive the progress ring UI.
struct DownloadProgress {
    var fractionCompleted: Double   // 0.0 – 1.0
    var bytesWritten: Int64
    var bytesExpected: Int64
}

// MARK: - PodWangManager

@MainActor
class PodWangManager: NSObject, ObservableObject {

    // MARK: - Published state

    /// The user's saved podcast feeds. Written to disk automatically on every change.
    @Published var feeds: [Feed] = [] {
        didSet { saveFeeds() }
    }

    /// Episodes for the currently selected feed, populated by `fetchEpisodes(for:)`.
    @Published var selectedFeedEpisodes: [Episode] = []

    /// Artwork URL for the currently selected feed, used as the blurred detail-view background.
    @Published var currentFeedImageURL: String?

    /// True while an RSS fetch network request is in progress.
    @Published var isFetching = false

    /// Controls episode list sort order. `true` = newest first.
    @Published var sortNewestFirst = true

    /// The episode currently loaded into the player (may be paused).
    @Published var currentPlayingEpisode: Episode?

    /// True when the player is actively playing audio.
    @Published var isPlaying = false

    /// Current playback position in seconds, updated every 0.5s by the time observer.
    @Published var currentTime: Double = 0

    /// Total duration of the current player item in seconds.
    @Published var duration: Double = 0

    /// The user-selected parent folder for downloads, held as a security-scoped URL.
    @Published var downloadsFolderURL: URL?

    /// Per-episode download progress, keyed by episode UUID.
    /// Entries are inserted when a download starts and removed on completion or cancellation.
    @Published var downloadProgress: [UUID: DownloadProgress] = [:]

    // MARK: - Private state

    private var player: AVPlayer?
    private var timeObserver: Any?

    /// Active download tasks keyed by episode UUID, used for cancellation support.
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]

    /// Delegate-based URLSession for downloads. Lazy so `self` is available as delegate.
    /// `delegateQueue: .main` keeps all delegate callbacks on the main thread,
    /// which is safe and correct for a @MainActor class.
    private lazy var downloadSession: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }()

    // MARK: - Computed properties

    /// True once the user has selected a downloads folder.
    var isStorageConfigured: Bool { downloadsFolderURL != nil }

    /// Episodes sorted by publication date according to `sortNewestFirst`.
    var sortedEpisodes: [Episode] {
        selectedFeedEpisodes.sorted { a, b in
            guard let dateA = a.pubDate, let dateB = b.pubDate else { return false }
            return sortNewestFirst ? dateA > dateB : dateA < dateB
        }
    }

    /// Returns a sorted, deduplicated list of category names for a given feed list.
    /// Feeds with a blank category are placed in "Uncategorized".
    func getCategories(for feedList: [Feed]) -> [String] {
        let allCats = feedList.map {
            $0.category.trimmingCharacters(in: .whitespaces).isEmpty ? "Uncategorized" : $0.category
        }
        let unique = Array(Set(allCats)).sorted()
        return unique.isEmpty && !feedList.isEmpty ? ["Uncategorized"] : unique
    }

    // MARK: - Storage paths

    /// Application Support/PodWang — created lazily on first access.
    lazy var saveFolderURL: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PodWang")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    /// Full path to the JSON file where feeds are persisted.
    private var saveURL: URL { saveFolderURL.appendingPathComponent("feeds.json") }

    // MARK: - Initialisation

    override init() {
        super.init()
        loadSavedFolderPermission()
        loadFeeds()
    }

    // MARK: - Folder permission

    /// Presents an NSOpenPanel so the user can choose a parent downloads folder,
    /// then saves a security-scoped bookmark so access persists across app restarts.
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

    /// Clears the saved bookmark and resets the app to the first-run setup screen.
    func resetStorageLocation() {
        downloadsFolderURL?.stopAccessingSecurityScopedResource()
        UserDefaults.standard.removeObject(forKey: "DownloadsFolderBookmark")
        downloadsFolderURL = nil
    }

    /// Persists a security-scoped bookmark for `url` to UserDefaults.
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

    /// Restores folder access from a previously saved security-scoped bookmark.
    /// Refreshes the bookmark automatically if it has gone stale.
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

    /// Returns the effective downloads directory, creating it if it doesn't yet exist.
    /// Episodes are stored inside a `PodWang_Downloads` subfolder within the user-chosen
    /// parent, or inside ~/Documents if no folder has been selected.
    func effectiveDownloadsURL() -> URL {
        let base = downloadsFolderURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("PodWang_Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Filename helpers

    /// Strips characters that are invalid in macOS file and folder names.
    private func sanitized(_ string: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return string.components(separatedBy: invalidChars).joined(separator: "_")
    }

    /// Infers the correct audio file extension from a URL.
    ///
    /// Some feeds (e.g. OneDrive share links) use redirect URLs whose path extension
    /// is `.aspx` rather than an audio format. This method checks the `filedisplay`
    /// query parameter first (which usually contains the real filename), then falls
    /// back to the path extension if it's a known audio format, and finally to `mp3`.
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

    // MARK: - Download

    /// Starts a download for `episode`, saving the file into a subfolder named after
    /// `feedTitle` within the downloads directory.
    /// Duplicate download requests for the same episode are silently ignored.
    func download(_ episode: Episode, from feedTitle: String) {
        guard let remoteURL = URL(string: episode.audioURL),
              activeTasks[episode.id] == nil
        else { return }

        let sanitizedFeed    = sanitized(feedTitle)
        let sanitizedEpisode = sanitized(episode.title)
        let ext              = audioExtension(from: remoteURL)
        let destinationName  = "\(sanitizedEpisode).\(ext)"
        let relativePath     = "\(sanitizedFeed)/\(destinationName)"

        // Create the podcast subfolder before the task starts.
        let podcastFolder = effectiveDownloadsURL().appendingPathComponent(sanitizedFeed, isDirectory: true)
        try? FileManager.default.createDirectory(at: podcastFolder, withIntermediateDirectories: true)

        // Encode the episode ID and relative destination path into taskDescription.
        // The delegate reads this to resolve the file location without shared mutable state.
        let task = downloadSession.downloadTask(with: remoteURL)
        task.taskDescription = "\(episode.id.uuidString)|\(relativePath)"

        activeTasks[episode.id]      = task
        downloadProgress[episode.id] = DownloadProgress(fractionCompleted: 0, bytesWritten: 0, bytesExpected: 0)

        task.resume()
    }

    /// Cancels an in-flight download and removes its progress entry immediately.
    func cancelDownload(for episode: Episode) {
        activeTasks[episode.id]?.cancel()
        activeTasks.removeValue(forKey: episode.id)
        downloadProgress.removeValue(forKey: episode.id)
    }

    // MARK: - Playback

    /// Plays `episode`, or toggles play/pause if it is already the current episode.
    /// Prefers a local downloaded file if one exists; falls back to streaming.
    func play(_ episode: Episode) {
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

    /// Attaches a periodic time observer to the player, publishing `currentTime`
    /// and `duration` updates every 0.5 seconds.
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

    /// Seeks the player to `time` (in seconds).
    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    /// Skips forward or backward by `seconds` relative to the current playback position.
    func skip(seconds: Double) {
        seek(to: max(0, min(currentTime + seconds, duration)))
    }

    /// Stops playback and resets all player state.
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

    // MARK: - Feed fetching

    /// Fetches and parses the RSS feed for `feed`, updating `selectedFeedEpisodes`,
    /// `currentFeedImageURL`, and the feed's stored `artworkURL` on completion.
    func fetchEpisodes(for feed: Feed) {
        guard let url = URL(string: feed.url) else { return }
        isFetching           = true
        selectedFeedEpisodes = []
        currentFeedImageURL  = nil

        Task {
            do {
                let (data, _)  = try await URLSession.shared.data(from: url)
                let parser     = XMLParser(data: data)
                let delegate   = RSSParserDelegate()
                parser.delegate = delegate

                if parser.parse() {
                    let episodes = checkLocalFiles(for: delegate.episodes, feedTitle: feed.title)
                    await MainActor.run {
                        self.selectedFeedEpisodes = episodes
                        self.currentFeedImageURL  = delegate.feedImageURL

                        // Persist the artwork URL on the feed so the sidebar can show it
                        // on subsequent launches without re-fetching.
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

    /// Checks the local filesystem for already-downloaded files matching each episode,
    /// setting `localFileName` on any episode whose file is found on disk.
    private func checkLocalFiles(for episodes: [Episode], feedTitle: String) -> [Episode] {
        let sanitizedFeed = sanitized(feedTitle)
        let podcastFolder = effectiveDownloadsURL().appendingPathComponent(sanitizedFeed, isDirectory: true)

        return episodes.map { episode in
            var updated = episode
            let sanitizedEpisode = sanitized(episode.title)
            if let url = URL(string: episode.audioURL) {
                let ext       = audioExtension(from: url)
                let fileName  = "\(sanitizedEpisode).\(ext)"
                let localPath = podcastFolder.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: localPath.path) {
                    updated.localFileName = "\(sanitizedFeed)/\(fileName)"
                }
            }
            return updated
        }
    }

    // MARK: - Persistence

    /// Encodes `feeds` to JSON and writes it to Application Support.
    func saveFeeds() {
        do {
            let data = try JSONEncoder().encode(feeds)
            try data.write(to: saveURL)
        } catch {
            print("Save error: \(error)")
        }
    }

    /// Loads feeds from the JSON file in Application Support, if it exists.
    func loadFeeds() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data   = try Data(contentsOf: saveURL)
            self.feeds = try JSONDecoder().decode([Feed].self, from: data)
        } catch {
            print("Load error: \(error)")
        }
    }

    func addFeed(title: String, url: String, category: String) {
        feeds.append(Feed(title: title, url: url, category: category))
    }

    func removeFeed(at offsets: IndexSet) { feeds.remove(atOffsets: offsets) }
    func moveFeed(from src: IndexSet, to dst: Int) { feeds.move(fromOffsets: src, toOffset: dst) }

    // MARK: - OPML

    /// Generates an OPML 1.1 XML string from the current feed list.
    /// Special characters in feed titles are escaped for valid XML.
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
        xml += "\n</body></opml>"
        return xml
    }

    /// Parses an OPML file and appends any new feeds (matched by URL) to the feed list.
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
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension PodWangManager: URLSessionDownloadDelegate {

    /// Called repeatedly as data arrives. Updates `downloadProgress` for the episode.
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

    /// Called once when the download finishes. The file must be moved synchronously here —
    /// the system deletes the temp file as soon as this method returns.
    ///
    /// Because this delegate is `nonisolated`, we resolve the bookmark directly from
    /// UserDefaults rather than calling `effectiveDownloadsURL()` (which requires MainActor).
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

    /// Called when a task ends with an error. Cancellations are intentional and not logged.
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

/// SAX-style delegate that parses a podcast RSS feed into `Episode` objects.
///
/// Artwork priority: `itunes:image` (preferred, higher resolution) over the standard
/// RSS `<image><url>` fallback. Characters are accumulated across multiple
/// `foundCharacters` callbacks and finalised in `didEndElement`.
///
/// Duration is read from `itunes:duration` and stored as a raw string, since the
/// format varies by producer (seconds, mm:ss, or hh:mm:ss).
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

        // itunes:image is preferred for feed artwork (higher resolution than RSS <image>).
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
            // Standard RSS <image><url> fallback — only used when itunes:image is absent.
            // Characters may arrive in multiple chunks; accumulated here, finalised below.
            if feedImageURL == nil { feedImageURL = (feedImageURL ?? "") + s }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        // Finalise the RSS image URL once all character chunks have been delivered.
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

/// Parses an OPML file and extracts feed entries from `<outline>` elements.
class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var foundFeeds: [Feed] = []

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        guard el == "outline",
              let title = attrs["text"] ?? attrs["title"],
              let url   = attrs["xmlUrl"]
        else { return }
        foundFeeds.append(Feed(title: title, url: url, category: attrs["category"] ?? "Uncategorized"))
    }
}
