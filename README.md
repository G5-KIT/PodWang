# PodWang 🎙️

A clean, native macOS podcast client built with SwiftUI. Search for podcasts, add them by RSS feed, browse episodes, stream or download them locally, and play them back — all from a simple two-panel interface.

---

## Screenshots

*Coming soon*

---

## Features

- **Podcast search** — search the Apple Podcasts catalogue directly from the sidebar and add feeds with a single tap
- **Browse by feed** — podcasts organised into custom categories in the sidebar, each showing its own artwork
- **Search feeds and episodes** — quickly filter your feed list or narrow down episodes by title
- **Episode list** — sorted newest or oldest first, with publication dates and duration where available
- **Show notes** — tap the info button on any episode to read its show notes
- **Stream or download** — play episodes directly from the internet, or download them locally for offline listening
- **Download progress** — live circular progress ring per episode, with individual cancel support
- **Playback controls** — play/pause, scrubber, time display, and skip ±30s / ±60s
- **Swipe to edit or delete** — manage feeds directly from the sidebar without entering a separate mode
- **Drag to reorder** — rearrange feeds within a category by dragging
- **Gear menu** — all management actions tucked into a clean toolbar popover
- **OPML import & export** — back up your feed list or migrate from another app (saved as `.xml` for maximum compatibility)
- **Dynamic background** — each podcast's artwork blurs subtly behind its episode list
- **Sandboxed file access** — downloads are stored in a user-chosen folder, with security-scoped bookmarks persisted across launches
- **Built-in help** — accessible via ⌘? or the Help menu

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

On first launch, PodWang will ask you to choose a parent folder for downloads. This is required for sandboxed file access to work correctly. You can reset or change this folder at any time from the gear menu in the sidebar.

---

## Finding and Adding Podcasts

Tap the **gear icon** (⚙) at the top of the sidebar to open the management menu.

**Search the Apple Podcasts catalogue:**
1. Click **Find Podcasts…**
2. Type to search — results appear automatically
3. Tap **+** on any result to add it instantly to your feed list

**Add manually by RSS URL:**
1. Click **Add Podcast…**
2. Enter the podcast name, RSS feed URL, and an optional category
3. Click **Add**

**Can't find what you're looking for?** Use the **Browse Podcast Index…** link at the bottom of the search popover to search at [podcastindex.org](https://podcastindex.org/).

---

## OPML Support

PodWang can import and export your podcast list as an OPML file (`.xml`).

- **Import XML** — adds any feeds from the file that aren't already in your list (matched by URL)
- **Export XML** — saves your full feed list as `PodWang Backup.xml`, readable by any podcast app that supports OPML

---

## Project Structure

```
PodWang/
├── PodWangApp.swift              # App entry point, window configuration, Help menu command
├── Models.swift                  # Episode and Feed data models
├── PodWangManager.swift          # Core logic — playback, downloads, RSS parsing, persistence
├── AppView.swift                 # Main layout, episode list, show notes, download controls, player bar
├── SidebarView.swift             # Feed list with artwork, search, inline edit, swipe actions, gear menu
├── SidebarAdditions.swift        # Podcast search, management popover, OPMLDocument
├── HelpView.swift                # In-app help window
└── TimeInterval+Formatting.swift # Playback time formatting utility extension
```

### Key design decisions

- `PodWangManager` is a `@MainActor` `ObservableObject` — all published state lives in one place and is always updated on the main thread
- Downloads use a delegate-based `URLSession` rather than `async/await`, enabling per-episode progress tracking and cancellation without extra concurrency overhead
- File access uses security-scoped bookmarks persisted in `UserDefaults`, so the app retains sandbox permissions to the downloads folder across restarts
- The episode ID and destination path are encoded into each `URLSessionDownloadTask`'s `taskDescription`, avoiding shared mutable state between the manager and its delegate extension
- Feed data is persisted as JSON in Application Support; the `Feed` model uses a custom `Codable` initialiser with fallback defaults so older saved data loads safely
- Podcast search uses the iTunes Search API — no API key or registration required, with the Apple Podcasts catalogue as the data source
- Feed artwork URLs are stored on the `Feed` model once fetched, so sidebar icons persist across launches without additional network calls
- Category-aware drag-to-reorder maps local indices back to global feed array positions to avoid a SwiftUI cross-category reorder bug
- Episode duration is parsed from `itunes:duration`, handling seconds, mm:ss, and hh:mm:ss formats
- File extension inference handles redirect URLs (e.g. OneDrive share links) by checking the `filedisplay` query parameter before falling back to the path extension

---

## Credits

Created by G5KIT.

Slava Ukraine! 🇺🇦 If you find PodWang useful, please consider donating to [United24](https://u24.gov.ua).

---

## License

MIT License. See `LICENSE` for details.
