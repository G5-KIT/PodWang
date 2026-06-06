// HelpView.swift
// PodWang — a native macOS podcast client.
//
// In-app help window, opened via ⌘? or the Help menu (configured in PodWangApp.swift).
// Presents a searchable two-panel NavigationSplitView: topic list on the left,
// topic content on the right. Selecting a topic scrolls the detail pane to the top.

import SwiftUI

// MARK: - Help Topic Model

/// A single help topic with a title and plain-text content string.
struct HelpTopic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let content: String
}

// MARK: - Help View

struct HelpView: View {

    @State private var searchText      = ""
    @State private var selectedTopicID: HelpTopic.ID?

    private let topics: [HelpTopic] = [

        HelpTopic(
            title: "Getting Started",
            content: """
• First time running:

PodWang will ask you to choose a folder for storing your downloaded files. \
The home Downloads folder is a good choice. PodWang creates a subfolder \
for each podcast using the feed title.

• Podcasts and Radio:

Use the Podcasts / Radio toggle at the top of the sidebar to switch between \
your podcast feeds and your saved internet radio stations. Each mode has its \
own gear menu (⚙) for managing content.
"""
        ),

        HelpTopic(
            title: "Managing your feeds",
            content: """
On first installation your feeds list will be empty. \
Tap the gear icon (⚙) at the top of the sidebar to open the management menu.

• Find Podcasts
Searches the Apple Podcasts catalogue. Results appear automatically as you type. \
Tap + on any result to add it to your feed list. \
Browse Podcast Index opens podcastindex.org in your default browser for feeds \
not in the Apple catalogue.

• Add Podcast
Opens a form to manually enter a feed title, RSS URL, and optional category.

• Reset Storage
Allows you to change your downloads folder location.

• Search Feeds
Use the search bar at the top of the sidebar to find a feed quickly.

• Edit or Delete
Swipe left on a feed to delete it. Swipe right to edit its title or category.

• Reorder Feeds
Drag feeds up or down within a category to reorder them.

• Feed Icons
Each feed shows its podcast artwork once it has been opened at least once. \
Unopened feeds show a placeholder icon until then.
"""
        ),

        HelpTopic(
            title: "Episodes",
            content: """
• Selecting a feed opens its episode list in the right panel. \
Use the Sort button in the toolbar to switch between newest-first and oldest-first order.

• Search Episodes
Use the search bar in the toolbar to filter episodes by title.

• Show Notes
Tap the ⓘ button on an episode to read its show notes, where available.

• Download All
CAUTION! Downloads all currently displayed episodes. \
If a search filter is active, only the filtered results are downloaded.

• Single Download
Tap the download button (↓) on an episode to download it. \
Multiple downloads run concurrently, each showing a live progress ring. \
Tap ✕ next to a ring to cancel that download. \
Once complete, the button becomes a folder icon — tap it to reveal the file in Finder.

• Playback
Tap the play button to stream an episode. The player bar opens at the bottom of the \
screen with a scrubber, time display, and skip ±30s / ±60s controls. \
If the episode has already been downloaded, the local file is used automatically.
"""
        ),

        HelpTopic(
            title: "Internet Radio",
            content: """
Switch to Radio mode using the Podcasts / Radio toggle at the top of the sidebar.

• Finding Stations
Tap the gear icon (⚙) and choose Find Stations… to search the radio-browser.info \
directory, which lists thousands of stations worldwide. Results are sorted by \
popularity. Tap + to save a station to your list.

• Adding a Station Manually
Tap the gear icon (⚙) and choose Add Station… to enter a station name, direct \
stream URL (mp3, aac, etc.), genre tags, and country manually.

• Playing a Station
Select a station from the sidebar to open its detail view, then tap the large \
play button. A Live indicator and a mini player bar appear at the bottom of the \
screen while streaming.

• Pause and Stop
Tap the play button again to pause. Tap the ✕ in the mini player bar to stop \
and dismiss the player.

• Edit or Delete
Swipe left on a station to delete it. Swipe right to edit its name or tags.
"""
        ),

        HelpTopic(
            title: "Backup and Restore",
            content: """
Your podcast feeds and radio stations can be backed up together as a single XML file \
and restored at any time.

• Import XML  (File menu → Import XML… or ⇧⌘I)
Reads a PodWang backup file and adds any feeds or stations not already in your lists. \
Existing entries are matched by URL and are never duplicated.

• Export XML  (File menu → Export XML… or ⇧⌘E)
Saves all your podcast feeds and radio stations to a file called PodWang Backup.xml. \
The file uses standard OPML format, so podcast feeds can also be imported by other \
podcast apps. Radio stations are stored in a clearly labelled group within the same \
file and are restored automatically when imported back into PodWang.
"""
        ),

        HelpTopic(
            title: "Credits",
            content: """
• Created by G5KIT.

• Slava Ukraine!

• If you find PodWang useful, please consider donating to United24 at U24.gov.ua
"""
        ),
    ]

    // MARK: - Filtering

    /// Topics filtered by the current search text, matching title or content.
    /// Returns all topics when the search field is empty.
    var filteredTopics: [HelpTopic] {
        guard !searchText.isEmpty else { return topics }
        return topics.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The currently selected topic, provided it exists in the filtered list.
    /// Falls back to the first filtered topic when nothing is explicitly selected.
    /// Returns nil if the previously selected topic has been filtered out, so the
    /// detail pane shows "Select a topic" rather than stale content.
    var selectedTopic: HelpTopic? {
        guard let selectedTopicID else { return filteredTopics.first }
        return filteredTopics.first(where: { $0.id == selectedTopicID })
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopicID) { topic in
                Text(topic.title)
            }
            .navigationTitle("Help")
            .searchable(text: $searchText)

        } detail: {
            if let topic = selectedTopic {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(topic.title)
                                .font(.largeTitle).bold()
                                .id("TOP")

                            Divider()

                            Text(topic.content)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(24)
                    }
                    // Scroll the detail pane back to the top whenever the topic changes.
                    .onChange(of: selectedTopicID) { _, _ in
                        proxy.scrollTo("TOP", anchor: .top)
                    }
                }
            } else {
                Text("Select a topic")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
