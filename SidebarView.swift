// SidebarView.swift
// PodWang — a native macOS podcast client.
//
// The left-hand feed list panel of the NavigationSplitView.
// Feeds are grouped by category, searchable, draggable within a category,
// and support swipe-to-delete and swipe-to-edit gestures.
//
// The gear toolbar button opens ManagementPopover (SidebarAdditions.swift)
// for all feed management actions.

import SwiftUI

struct SidebarView: View {
    @ObservedObject var manager: PodWangManager
    @Binding var selectedFeed: Feed?
    @Binding var searchText: String
    @Binding var showingFilePicker: Bool
    @Binding var showingFileExporter: Bool
    @Binding var opmlDoc: OPMLDocument?

    /// The UUID of the feed currently open in the inline edit form, if any.
    @State private var editingFeedID:    UUID?
    @State private var tempTitle       = ""
    @State private var tempCategory    = ""
    @State private var showingManagement = false

    // MARK: - Filtered data

    /// Feeds filtered by the current search text, matching title or category.
    /// Returns the full feed list when the search field is empty.
    /// Computed as a property rather than inline in `body` to keep the view readable.
    private var filteredFeeds: [Feed] {
        guard !searchText.isEmpty else { return manager.feeds }
        return manager.feeds.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Sorted, deduplicated category names for the current filtered feed list.
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
                    .onMove { localSource, localDestination in
                        // SwiftUI's onMove provides indices relative to the category slice,
                        // but manager.feeds is the full unsegmented array. We map each local
                        // index back to its global position before performing the move,
                        // which prevents cross-category reorder bugs.
                        let globalSource = IndexSet(
                            localSource.compactMap { localIndex in
                                manager.feeds.firstIndex(where: { $0.id == feedsInCategory[localIndex].id })
                            }
                        )
                        if localDestination < feedsInCategory.count {
                            let destinationFeed = feedsInCategory[localDestination]
                            if let globalDestination = manager.feeds.firstIndex(where: { $0.id == destinationFeed.id }) {
                                manager.feeds.move(fromOffsets: globalSource, toOffset: globalDestination)
                            }
                        } else {
                            // Dragged to the end of the category.
                            if let lastFeed = feedsInCategory.last,
                               let lastGlobal = manager.feeds.firstIndex(where: { $0.id == lastFeed.id }) {
                                manager.feeds.move(fromOffsets: globalSource, toOffset: lastGlobal + 1)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingManagement = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Manage podcasts")
                .popover(isPresented: $showingManagement, arrowEdge: .bottom) {
                    ManagementPopover(
                        manager: manager,
                        showingFilePicker: $showingFilePicker,
                        showingFileExporter: $showingFileExporter,
                        opmlDoc: $opmlDoc
                    )
                }
            }
        }
    }

    // MARK: - Sidebar row

    /// Renders either an inline edit form or a standard NavigationLink row,
    /// depending on whether this feed is currently being edited.
    @ViewBuilder
    private func sidebarRow(for feed: Feed) -> some View {
        if editingFeedID == feed.id {
            // Inline edit form — Save is triggered by button or Return key.
            // Cancel discards changes without saving.
            VStack(spacing: 6) {
                TextField("Title", text: $tempTitle)
                TextField("Category", text: $tempCategory)

                HStack {
                    Button("Cancel") { editingFeedID = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Spacer()

                    Button("Save") { commitEdit(for: feed) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .onSubmit { commitEdit(for: feed) }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)

        } else {
            NavigationLink(value: feed) {
                HStack(spacing: 8) {
                    // Show the feed's podcast artwork thumbnail if available,
                    // falling back to the radio waves placeholder otherwise.
                    // Artwork is fetched and persisted the first time a feed is opened.
                    if let artworkURL = feed.artworkURL, let url = URL(string: artworkURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "dot.radiowaves.up.forward")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                    } else {
                        Image(systemName: "dot.radiowaves.up.forward")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.accentColor)
                    }
                    Text(feed.title)
                }
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

    /// Writes the edited title and category back to the manager and closes the edit form.
    private func commitEdit(for feed: Feed) {
        guard let idx = manager.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        manager.feeds[idx].title    = tempTitle
        manager.feeds[idx].category = tempCategory.isEmpty ? "Uncategorized" : tempCategory
        editingFeedID = nil
    }
}
