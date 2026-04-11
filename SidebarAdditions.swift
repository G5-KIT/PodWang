// SidebarAdditions.swift v3.2
// Sidebar management controls and the OPML file document type.
//
// ManagementSection provides:
//   - Find Podcasts   → opens podcastindex.org in the default browser
//   - Add Podcast…    → popover form for adding a feed by RSS URL
//   - Import XML      → triggers the file importer in AppView
//   - Export XML      → generates an OPML string and triggers the file exporter
//   - Reset Storage   → clears the saved downloads folder bookmark

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Management Section

struct ManagementSection: View {
    @ObservedObject var manager: PodWangManager
    @Binding var showingFilePicker: Bool
    @Binding var showingFileExporter: Bool
    @Binding var opmlDoc: OPMLDocument?

    @State private var showingAddPopover = false
    @State private var newTitle    = ""
    @State private var newURL      = ""
    @State private var newCategory = ""

    var body: some View {
        Section(header: Text("Management").font(.callout).foregroundColor(.secondary)) {

            // Opens podcastindex.org in the user's default browser.
            Button {
                NSWorkspace.shared.open(URL(string: "https://podcastindex.org/")!)
            } label: {
                Label("Find Podcasts…", systemImage: "magnifyingglass")
            }

            // Opens a popover with a form for adding a new feed by RSS URL.
            Button {
                showingAddPopover = true
            } label: {
                Label("Add Podcast…", systemImage: "plus.circle")
            }
            .popover(isPresented: $showingAddPopover, arrowEdge: .trailing) {
                addPodcastPopover
            }

            // Triggers the fileImporter modifier in AppView.
            Button { showingFilePicker = true } label: {
                Label("Import XML", systemImage: "square.and.arrow.down")
            }

            // Generates an OPML string and triggers the fileExporter modifier in AppView.
            Button {
                opmlDoc = OPMLDocument(text: manager.generateOPMLString())
                showingFileExporter = true
            } label: {
                Label("Export XML", systemImage: "square.and.arrow.up")
            }

            // Clears the security-scoped bookmark, returning the app to the setup screen.
            Button(role: .destructive) {
                manager.resetStorageLocation()
            } label: {
                Label("Reset Storage", systemImage: "folder.badge.minus")
            }
        }
    }

    // MARK: - Add Podcast Popover

    /// Inline form for adding a new feed. The Add button is disabled until
    /// both Name and RSS URL fields contain text.
    private var addPodcastPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Podcast")
                .font(.headline)

            TextField("Name", text: $newTitle)
            TextField("RSS URL", text: $newURL)
            TextField("Category (optional)", text: $newCategory)

            HStack {
                Button("Cancel") {
                    showingAddPopover = false
                    newTitle = ""; newURL = ""; newCategory = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    manager.addFeed(title: newTitle, url: newURL, category: newCategory)
                    showingAddPopover = false
                    newTitle = ""; newURL = ""; newCategory = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.isEmpty || newURL.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        .frame(width: 280)
    }
}

// MARK: - OPML Document

/// A `FileDocument` wrapping an OPML XML string for use with SwiftUI's `fileExporter`.
/// Saved as `.xml` for maximum compatibility with other podcast apps.
struct OPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
