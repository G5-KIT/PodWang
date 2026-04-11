// SidebarView.swift v3.2
// The left-hand feed list panel of the NavigationSplitView.
// Displays feeds grouped by category, with search filtering, swipe-to-edit/delete,
// drag-to-reorder, and inline editing via a Cancel/Save form.

import SwiftUI

struct SidebarView: View {
    @ObservedObject var manager: PodWangManager
    @Binding var selectedFeed: Feed?
    @Binding var searchText: String
    @Binding var showingFilePicker: Bool
    @Binding var showingFileExporter: Bool
    @Binding var opmlDoc: OPMLDocument?

    /// The ID of the feed currently being edited inline, if any.
    @State private var editingFeedID: UUID?
    @State private var tempTitle    = ""
    @State private var tempCategory = ""

    // MARK: - Filtered data

    /// Feeds filtered by the current search text. Returns all feeds when search is empty.
    /// Computed as a property rather than inline in `body` to avoid re-running on every render.
    private var filteredFeeds: [Feed] {
        guard !searchText.isEmpty else { return manager.feeds }
        return manager.feeds.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Sorted, deduplicated category names derived from the filtered feed list.
    private var categories: [String] {
        manager.getCategories(for: filteredFeeds)
    }

    // MARK: - Body

    var body: some View {
        List(selection: $selectedFeed) {
            ForEach(categories, id: \.self) { category in
                Section(header: Text(category)) {
                    let feedsInCategory = filteredFeeds.filter {
                        ($0.category.isEmpty ? "Uncategorized" : $0.category) == category
                    }
                    ForEach(feedsInCategory) { feed in
                        sidebarRow(for: feed)
                    }
                    .onMove { manager.moveFeed(from: $0, to: $1) }
                }
            }

            ManagementSection(
                manager: manager,
                showingFilePicker: $showingFilePicker,
                showingFileExporter: $showingFileExporter,
                opmlDoc: $opmlDoc
            )
        }
    }

    // MARK: - Sidebar row

    /// Renders either an inline edit form or a standard NavigationLink row,
    /// depending on whether this feed is currently being edited.
    @ViewBuilder
    private func sidebarRow(for feed: Feed) -> some View {
        if editingFeedID == feed.id {
            // Inline edit form with explicit Save/Cancel buttons.
            // The Save button is also submitted by pressing Return.
            VStack(spacing: 6) {
                TextField("Title", text: $tempTitle)
                TextField("Category", text: $tempCategory)

                HStack {
                    Button("Cancel") {
                        editingFeedID = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("Save") {
                        commitEdit(for: feed)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .onSubmit { commitEdit(for: feed) }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)

        } else {
            NavigationLink(value: feed) {
                Label(feed.title, systemImage: "dot.radiowaves.up.forward")
            }
            // Swipe left to delete.
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    if let idx = manager.feeds.firstIndex(where: { $0.id == feed.id }) {
                        manager.removeFeed(at: IndexSet(integer: idx))
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            // Swipe right to edit.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    editingFeedID = feed.id
                    tempTitle     = feed.title
                    tempCategory  = feed.category
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
    }

    /// Writes the edited title and category back to the manager and exits edit mode.
    private func commitEdit(for feed: Feed) {
        guard let idx = manager.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        manager.feeds[idx].title    = tempTitle
        manager.feeds[idx].category = tempCategory.isEmpty ? "Uncategorized" : tempCategory
        editingFeedID = nil
    }
}
