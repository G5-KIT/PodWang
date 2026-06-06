// PodWangApp.swift
// PodWang — a native macOS podcast client.
//
// Entry point for the application. Declares two scenes:
//   - The main WindowGroup containing AppView
//   - A secondary Window for the in-app help viewer
//
// HelpCommands registers the Help menu item and its ⌘? keyboard shortcut.
// FileCommands adds Import XML and Export XML to the File menu.

import SwiftUI

@main
struct PodWangApp: App {
    var body: some Scene {

        // Main application window.
        WindowGroup {
            AppView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            FileCommands()
        }

        // Help window — opened via HelpCommands or ⌘?.
        Window("Help", id: "help-window") {
            HelpView()
        }
        .defaultSize(width: 420, height: 320)
        .windowResizability(.contentSize)
        .commands {
            HelpCommands()
        }
    }
}

// MARK: - File Commands

/// Adds Import XML (⌘I) and Export XML (⇧⌘E) to the File menu.
/// Uses @FocusedObject to reach the PodWangManager from the active window,
/// which AppView exposes via .focusedSceneObject(_:).
struct FileCommands: Commands {
    @FocusedObject private var manager: PodWangManager?

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Import XML…") {
                manager?.triggerImport()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(manager == nil)

            Button("Export XML…") {
                manager?.triggerExport()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(manager == nil)
        }
    }
}

// MARK: - Help Commands

/// Replaces the default Help menu entry with a PodWang-specific item
/// that opens the help window and binds to ⌘?.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("PodWang Help") {
                openWindow(id: "help-window")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
