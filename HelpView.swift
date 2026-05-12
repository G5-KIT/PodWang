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

• Import XML
Loads feeds from a saved XML or OPML file.

• Export XML
Saves a backup of your feeds as PodWang Backup.xml.

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
