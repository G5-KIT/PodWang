// PodWangApp.swift v3.2
// Entry point for the PodWang macOS application.
// Configures the main window with a native unified toolbar style.

import SwiftUI

@main
struct PodWangApp: App {
    var body: some Scene {
        WindowGroup {
            AppView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
    }
}
