import AppKit
import SwiftUI

@main
struct PdfMergeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTool: Tool = .merge

    var body: some Scene {
        WindowGroup {
            ContentView(selectedTool: $selectedTool)
                .onAppear {
                    cleanupOrphanedTempFiles()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        cleanupOrphanedTempFiles()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    cleanupOrphanedTempFiles()
                }
        }
        .defaultSize(
            width: AppConstants.defaultWindowWidth,
            height: AppConstants.defaultWindowHeight
        )
        .windowResizability(.contentSize)
        .commands {
            AppCommands(selectedTool: $selectedTool)
        }

        Settings {
            PreferencesView()
        }
    }

    private func cleanupOrphanedTempFiles() {
        Task.detached(priority: .utility) {
            // Temp files are created next to the output file, which can be in any
            // user-chosen directory. Scan the most common locations.
            let fm = FileManager.default
            var directories: [URL] = []

            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                directories.append(docs)
            }
            if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
                directories.append(desktop)
            }
            if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                directories.append(downloads)
            }
            directories.append(fm.homeDirectoryForCurrentUser)
            directories.append(fm.temporaryDirectory)

            for dir in directories {
                FileService.cleanupOrphanedTempFiles(in: dir)
            }
        }
    }
}
