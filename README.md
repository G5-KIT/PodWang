# PodWang 🎙️

A clean, native macOS podcast client built with SwiftUI. Add podcasts by RSS feed, browse episodes, stream or download them locally, and play them back — all from a simple two-panel interface.

---

## Screenshots

*Coming soon*

---

## Features

- **Browse by feed** — add any podcast via its RSS URL, organised into custom categories in the sidebar
- **Episode list** — sorted newest or oldest first, with publication dates
- **Stream or download** — play episodes directly from the internet, or download them locally for offline listening
- **Download progress** — live circular progress ring per episode, with individual cancel support
- **Playback controls** — play/pause, scrubber, time display, and skip ±30s / ±60s
- **Swipe to edit or delete** — manage feeds directly from the sidebar without entering a separate mode
- **Podcast search** — one-click link to [Podcast Index](https://podcastindex.org/) to find new shows
- **OPML import & export** — back up your feed list or migrate from another app (saved as `.xml` for maximum compatibility)
- **Dynamic background** — each podcast's artwork blurs subtly behind its episode list
- **Sandboxed file access** — downloads are stored in a user-chosen folder, with security-scoped bookmarks persisted across launches

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later

---

## Getting Started

1. Clone the repository
   ```bash
   git clone https://github.com/g0jps/PodWang.git
   ```
2. Open `PodWang.xcodeproj` in Xcode
3. Select your development team under **Signing & Capabilities**
4. Build and run with `⌘R`

On first launch, PodWang will ask you to choose a parent folder for downloads. This is required for sandboxed file access to work correctly. You can reset or change this folder at any time from the sidebar.

---

## Adding a Podcast

1. In the sidebar, click **Add Podcast…** to open the input form
2. Enter the podcast name, its RSS feed URL, and an optional category
3. Click **Add**

Not sure where to find RSS URLs? Use the **Find Podcasts…** button to search on [Podcast Index](https://podcastindex.org/).

---

## OPML Support

PodWang can import and export your podcast list as an OPML file (`.xml`).

- **Import XML** — adds any feeds from the file that aren't already in your list (matched by URL)
- **Export XML** — saves your full feed list as `PodWang Backup.xml`, readable by any podcast app that supports OPML

---

## Project Structure

```
PodWang/
├── PodWangApp.swift              # App entry point and window configuration
├── Models.swift                  # Episode and Feed data models
├── PodWangManager.swift          # Core logic — playback, downloads, RSS parsing, persistence
├── AppView.swift                 # Main layout, episode list, download controls, player bar
├── SidebarView.swift             # Feed list with search, inline edit, swipe actions
├── SidebarAdditions.swift        # Management section, Add Podcast popover, OPMLDocument
└── TimeInterval+Formatting.swift # Playback time formatting utility extension
```

### Key design decisions

- `PodWangManager` is a `@MainActor` `ObservableObject` — all published state lives in one place and is always updated on the main thread
- Downloads use a delegate-based `URLSession` rather than `async/await`, enabling per-episode progress tracking and cancellation without extra concurrency overhead
- File access uses security-scoped bookmarks persisted in `UserDefaults`, so the app retains sandbox permissions to the downloads folder across restarts
- The episode ID and destination path are encoded into each `URLSessionDownloadTask`'s `taskDescription`, avoiding shared mutable state between the manager and its delegate extension
- Feed data is persisted as JSON in Application Support; the `Feed` model uses a custom `Codable` initialiser with fallback defaults so older saved data loads safely

---

## Roadmap

- [ ] Background downloads
- [ ] Episode descriptions panel
- [ ] Playback speed control
- [ ] Per-feed unplayed episode count
- [ ] iCloud sync

---

## License

MIT License. See `LICENSE` for details.

