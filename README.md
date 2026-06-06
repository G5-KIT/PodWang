# PodWang 🎙️

A clean, native macOS podcast client and internet radio player built with SwiftUI. Search for podcasts, add them by RSS feed, browse episodes, stream or download them locally — and stream live internet radio stations from around the world — all from a simple two-panel interface.

---

## Screenshots

*Coming soon*

---

## Features

- **Podcasts & Internet Radio** — a segmented toggle in the sidebar switches between your podcast feeds and your saved radio stations; each mode has its own gear menu
- **Podcast search** — search the Apple Podcasts catalogue directly from the sidebar and add feeds with a single tap
- **Browse by feed** — podcasts organised into custom categories in the sidebar, each showing its own artwork
- **Search feeds and episodes** — quickly filter your feed list or narrow down episodes by title
- **Episode list** — sorted newest or oldest first, with publication dates and duration where available
- **Show notes** — tap the info button on any episode to read its show notes
- **Stream or download** — play episodes directly from the internet, or download them locally for offline listening
- **Download progress** — live circular progress ring per episode, with individual cancel support
- **Podcast playback** — play/pause, scrubber, time display, and skip ±30s / ±60s controls
- **Radio station search** — search thousands of stations via the free radio-browser.info directory, sorted by popularity
- **Manual station entry** — add any station by name, direct stream URL, genre tags, and country
- **Radio playback** — tap a station to open its detail view and stream live; a mini player bar with live badge, pause, and stop stays visible while streaming
- **HTTP stream support** — automatically upgrades stream URLs to HTTPS where possible, with HTTP fallback for stations that require it
- **Swipe to edit or delete** — manage feeds and stations directly from the sidebar without entering a separate mode
- **Drag to reorder** — rearrange feeds and stations by dragging
- **Gear menu** — management actions tucked into a clean toolbar popover, context-sensitive for Podcasts or Radio mode
- **Backup and restore** — File menu → Import XML… / Export XML… (⇧⌘I / ⇧⌘E) saves and restores both podcast feeds and radio stations in a single OPML-compatible file
- **Dynamic background** — each podcast's artwork blurs subtly behind its episode list; radio stations do the same with their favicon
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

### HTTP radio streams

Many radio stations serve their streams over plain HTTP. To allow these to play, add the following to your app's `Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

In Xcode: open `Info.plist` → right-click → Add Row → **App Transport Security Settings** (Dictionary) → add child **Allow Arbitrary Loads** (Boolean) = YES.

---

## Finding and Adding Podcasts

Tap the **gear icon** (⚙) at the top of the sidebar (in Podcasts mode) to open the management menu.

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

## Internet Radio

Switch to **Radio** mode using the toggle at the top of the sidebar.

**Search for stations:**
1. Tap the gear icon (⚙) and choose **Find Stations…**
2. Type to search — results from [radio-browser.info](https://www.radio-browser.info/) appear automatically, sorted by popularity
3. Tap **+** to save a station

**Add manually:**
1. Tap the gear icon (⚙) and choose **Add Station…**
2. Enter the station name, direct stream URL, optional genre tags, and country
3. Click **Add**

Select a station to open its detail view and tap the play button to start streaming.

---

## Backup and Restore

Use **File → Import XML…** (⇧⌘I) and **File → Export XML…** (⇧⌘E) to back up and restore your data.

- **Export XML** saves all podcast feeds and radio stations to a single `PodWang Backup.xml` file in standard OPML format. Podcast feeds can be imported by any OPML-compatible podcast app; radio stations are stored in a clearly labelled group within the same file.
- **Import XML** reads a backup file and merges any feeds or stations not already in your lists. Entries are matched by URL so nothing is ever duplicated.

---

## Project Structure

```
PodWang/
├── PodWangApp.swift              # App entry point, window scenes, File and Help menu commands
├── Models.swift                  # Episode, Feed, and RadioStation data models
├── PodWangManager.swift          # Core logic — podcast & radio playback, downloads, RSS parsing, persistence, OPML
├── AppView.swift                 # Main layout, episode list, radio detail view, podcast & radio player bars
├── SidebarView.swift             # Podcasts/Radio toggle, feed & station lists, inline edit, swipe actions
├── SidebarAdditions.swift        # Podcast search, radio station search, management popovers, OPML document type
├── HelpView.swift                # In-app help window
└── TimeInterval+Formatting.swift # Playback time formatting utility extension
```

### Key design decisions

- `PodWangManager` is a `@MainActor` `ObservableObject` — all published state lives in one place and is always updated on the main thread
- Downloads use a delegate-based `URLSession` rather than `async/await`, enabling per-episode progress tracking and cancellation without extra concurrency overhead
- File access uses security-scoped bookmarks persisted in `UserDefaults`, so the app retains sandbox permissions to the downloads folder across restarts
- The episode ID and destination path are encoded into each `URLSessionDownloadTask`'s `taskDescription`, avoiding shared mutable state between the manager and its delegate extension
- Feed and radio station data are persisted as separate JSON files in Application Support; both models use custom `Codable` initialisers with fallback defaults so older saved data loads safely
- Podcast playback uses `AVPlayer` with a periodic time observer for scrubber updates; radio playback uses a separate `AVPlayer` instance — starting one stops the other
- Radio stream URLs are upgraded from `http://` to `https://` automatically; a KVO observer on `AVPlayerItem.status` detects failure and retries with the original HTTP URL, so both HTTPS and HTTP-only streams work transparently
- Radio station search uses the radio-browser.info open API (no key required); a mirror resolver picks the nearest of three regional endpoints at startup
- Import and export are driven by `NSOpenPanel` / `NSSavePanel` called directly from `triggerImport()` / `triggerExport()` on the manager, exposed to the File menu via `@FocusedObject` — no SwiftUI `fileImporter`/`fileExporter` machinery required
- OPML export writes radio stations into a `<outline text="Radio Stations">` container group; the parser uses outline-depth tracking (not a boolean flag) so all stations are correctly imported regardless of how many there are
- Podcast search uses the iTunes Search API — no API key or registration required
- Feed artwork and station favicon URLs are stored on the model once fetched, so sidebar icons persist across launches without additional network calls
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
