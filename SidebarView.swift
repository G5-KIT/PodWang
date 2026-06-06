// SidebarView.swift
// PodWang — a native macOS podcast client.
//
// The left-hand panel of the NavigationSplitView.
// A segmented Podcasts / Radio toggle at the top switches between two modes:
//
//   Podcasts — existing feed list, grouped by category, with the gear menu.
//   Radio    — saved radio station list, grouped by primary tag, with its own gear menu.
//
// Both modes share the same swipe-to-delete / swipe-to-edit pattern and in-place
// drag-to-reorder behaviour.

import SwiftUI

// MARK: - Sidebar mode

enum SidebarMode: String, CaseIterable {
    case podcasts = "Podcasts"
    case radio    = "Radio"
}

// MARK: - SidebarView

struct SidebarView: View {
    @ObservedObject var manager: PodWangManager

    // Podcast selection / search
    @Binding var selectedFeed: Feed?
    @Binding var searchText: String

    // Radio selection / search
    @Binding var selectedStation: RadioStation?
    @Binding var radioSearchText: String

    @State private var sidebarMode: SidebarMode = .podcasts

    // Podcast inline edit state
    @State private var editingFeedID: UUID?
    @State private var tempFeedTitle    = ""
    @State private var tempFeedCategory = ""

    // Radio inline edit state
    @State private var editingStationID: UUID?
    @State private var tempStationName = ""
    @State private var tempStationTags = ""

    // Management popover visibility
    @State private var showingPodcastManagement = false
    @State private var showingRadioManagement   = false

    // MARK: - Filtered data

    private var filteredFeeds: [Feed] {
        guard !searchText.isEmpty else { return manager.feeds }
        return manager.feeds.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var feedCategories: [String] {
        manager.getCategories(for: filteredFeeds)
    }

    private var filteredStations: [RadioStation] {
        guard !radioSearchText.isEmpty else { return manager.radioStations }
        return manager.radioStations.filter {
            $0.name.localizedCaseInsensitiveContains(radioSearchText) ||
            $0.tags.localizedCaseInsensitiveContains(radioSearchText) ||
            ($0.country ?? "").localizedCaseInsensitiveContains(radioSearchText)
        }
    }

    private var stationTags: [String] {
        let allTags = filteredStations.map { $0.primaryTag }
        return Array(Set(allTags)).sorted()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggle — sits above the list, outside the List scroll area.
            Picker("Mode", selection: $sidebarMode) {
                ForEach(SidebarMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if sidebarMode == .podcasts {
                podcastList
            } else {
                radioList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if sidebarMode == .podcasts {
                    Button { showingPodcastManagement = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Manage podcasts")
                    .popover(isPresented: $showingPodcastManagement, arrowEdge: .bottom) {
                        ManagementPopover(manager: manager)
                    }
                } else {
                    Button { showingRadioManagement = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Manage radio stations")
                    .popover(isPresented: $showingRadioManagement, arrowEdge: .bottom) {
                        RadioManagementPopover(manager: manager)
                    }
                }
            }
        }
    }

    // MARK: - Podcast list

    private var podcastList: some View {
        List(selection: $selectedFeed) {
            ForEach(feedCategories, id: \.self) { category in
                Section(header: Text(category)) {
                    let feedsInCategory = filteredFeeds.filter {
                        ($0.category.isEmpty ? "Uncategorized" : $0.category) == category
                    }
                    ForEach(feedsInCategory) { feed in
                        podcastRow(for: feed)
                    }
                    .onMove { localSource, localDestination in
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
                            if let lastFeed = feedsInCategory.last,
                               let lastGlobal = manager.feeds.firstIndex(where: { $0.id == lastFeed.id }) {
                                manager.feeds.move(fromOffsets: globalSource, toOffset: lastGlobal + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Radio list

    private var radioList: some View {
        List(selection: $selectedStation) {
            ForEach(stationTags, id: \.self) { tag in
                Section(header: Text(tag)) {
                    let stationsInTag = filteredStations.filter { $0.primaryTag == tag }
                    ForEach(stationsInTag) { station in
                        radioRow(for: station)
                    }
                    .onMove { localSource, localDestination in
                        let globalSource = IndexSet(
                            localSource.compactMap { localIndex in
                                manager.radioStations.firstIndex(where: { $0.id == stationsInTag[localIndex].id })
                            }
                        )
                        if localDestination < stationsInTag.count {
                            let destStation = stationsInTag[localDestination]
                            if let globalDest = manager.radioStations.firstIndex(where: { $0.id == destStation.id }) {
                                manager.radioStations.move(fromOffsets: globalSource, toOffset: globalDest)
                            }
                        } else {
                            if let lastStation = stationsInTag.last,
                               let lastGlobal = manager.radioStations.firstIndex(where: { $0.id == lastStation.id }) {
                                manager.radioStations.move(fromOffsets: globalSource, toOffset: lastGlobal + 1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Podcast row

    @ViewBuilder
    private func podcastRow(for feed: Feed) -> some View {
        if editingFeedID == feed.id {
            VStack(spacing: 6) {
                TextField("Title", text: $tempFeedTitle)
                TextField("Category", text: $tempFeedCategory)
                HStack {
                    Button("Cancel") { editingFeedID = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    Button("Save") { commitFeedEdit(for: feed) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .onSubmit { commitFeedEdit(for: feed) }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        } else {
            NavigationLink(value: feed) {
                HStack(spacing: 8) {
                    if let artworkURL = feed.artworkURL, let url = URL(string: artworkURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "dot.radiowaves.up.forward").foregroundColor(.accentColor)
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
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    if let idx = manager.feeds.firstIndex(where: { $0.id == feed.id }) {
                        manager.removeFeed(at: IndexSet(integer: idx))
                    }
                } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    editingFeedID    = feed.id
                    tempFeedTitle    = feed.title
                    tempFeedCategory = feed.category
                } label: { Label("Edit", systemImage: "pencil") }
                .tint(.orange)
            }
        }
    }

    private func commitFeedEdit(for feed: Feed) {
        guard let idx = manager.feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        manager.feeds[idx].title    = tempFeedTitle
        manager.feeds[idx].category = tempFeedCategory.isEmpty ? "Uncategorized" : tempFeedCategory
        editingFeedID = nil
    }

    // MARK: - Radio row

    @ViewBuilder
    private func radioRow(for station: RadioStation) -> some View {
        if editingStationID == station.id {
            VStack(spacing: 6) {
                TextField("Name", text: $tempStationName)
                TextField("Tags / Genre", text: $tempStationTags)
                HStack {
                    Button("Cancel") { editingStationID = nil }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    Button("Save") { commitStationEdit(for: station) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .onSubmit { commitStationEdit(for: station) }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        } else {
            NavigationLink(value: station) {
                HStack(spacing: 8) {
                    stationIcon(for: station)
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(station.name)
                            .lineLimit(1)
                        if let country = station.country, !country.isEmpty {
                            Text(country)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Live playing indicator dot.
                    if manager.currentRadioStation?.id == station.id && manager.isRadioPlaying {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    if let idx = manager.radioStations.firstIndex(where: { $0.id == station.id }) {
                        manager.removeRadioStation(at: IndexSet(integer: idx))
                    }
                } label: { Label("Delete", systemImage: "trash") }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    editingStationID = station.id
                    tempStationName  = station.name
                    tempStationTags  = station.tags
                } label: { Label("Edit", systemImage: "pencil") }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private func stationIcon(for station: RadioStation) -> some View {
        if let faviconURL = station.faviconURL, let url = URL(string: faviconURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "radio").foregroundColor(.accentColor)
                }
            }
        } else {
            Image(systemName: "radio").foregroundColor(.accentColor)
        }
    }

    private func commitStationEdit(for station: RadioStation) {
        guard let idx = manager.radioStations.firstIndex(where: { $0.id == station.id }) else { return }
        manager.radioStations[idx].name = tempStationName
        manager.radioStations[idx].tags = tempStationTags
        editingStationID = nil
    }
}
