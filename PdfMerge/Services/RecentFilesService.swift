import Foundation

enum RecentFilesService {

    // MARK: - Constants

    static let didChangeNotification = Notification.Name("RecentFilesService.didChange")

    private static let maxRecentFiles = 5
    private static let defaultsKeyPrefix = "recentFiles_"
    private static let storageQueue = DispatchQueue(label: "PdfMerge.RecentFilesService")

    // MARK: - Get Recent Files

    /// Retrieve the recent files list for a given tool, pruning entries whose files no longer exist
    /// and refreshing stale bookmarks in place.
    static func getRecentFiles(for tool: Tool) -> [RecentFile] {
        storageQueue.sync {
            loadRecentFilesLocked(for: tool)
        }
    }

    // MARK: - Add Recent File

    /// Add a file URL to the recent files list for a given tool.
    /// Creates a security-scoped bookmark for persistent access.
    static func addRecentFile(url: URL, for tool: Tool) {
        storageQueue.sync {
            guard let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { return }

            var files = loadRecentFilesLocked(for: tool)
            let standardizedPath = url.standardizedFileURL.path

            // Remove existing entry for the same file (if re-opening)
            files.removeAll { existing in
                existing.resolvedURL()?.standardizedFileURL.path == standardizedPath
            }

            let newEntry = RecentFile(
                bookmarkData: bookmarkData,
                date: Date(),
                toolID: tool.rawValue
            )

            // Insert at front (most recent first)
            files.insert(newEntry, at: 0)

            // Trim to max
            if files.count > maxRecentFiles {
                files = Array(files.prefix(maxRecentFiles))
            }

            saveLocked(files, for: tool)
        }
    }

    // MARK: - Clear

    /// Remove all recent files for a given tool.
    static func clearRecentFiles(for tool: Tool) {
        storageQueue.sync {
            let key = storageKey(for: tool)
            UserDefaults.standard.removeObject(forKey: key)
            postDidChange(for: tool)
        }
    }

    // MARK: - Private

    private static func storageKey(for tool: Tool) -> String {
        "\(defaultsKeyPrefix)\(tool.rawValue)"
    }

    private static func loadRecentFilesLocked(for tool: Tool) -> [RecentFile] {
        let key = storageKey(for: tool)
        guard let data = UserDefaults.standard.data(forKey: key),
              let files = try? JSONDecoder().decode([RecentFile].self, from: data) else {
            return []
        }

        var cleanedFiles: [RecentFile] = []
        var didChange = false

        for file in files {
            guard let resolution = file.resolveBookmark() else {
                didChange = true
                continue
            }

            guard FileManager.default.fileExists(atPath: resolution.url.path) else {
                didChange = true
                continue
            }

            if resolution.isStale {
                let didAccess = resolution.url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        resolution.url.stopAccessingSecurityScopedResource()
                    }
                }

                if let refreshedBookmarkData = try? resolution.url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    cleanedFiles.append(
                        RecentFile(
                            id: file.id,
                            bookmarkData: refreshedBookmarkData,
                            date: file.date,
                            toolID: file.toolID
                        )
                    )
                    didChange = true
                } else {
                    cleanedFiles.append(file)
                }
            } else {
                cleanedFiles.append(file)
            }
        }

        if didChange {
            saveLocked(cleanedFiles, for: tool)
        }

        return cleanedFiles
    }

    private static func saveLocked(_ files: [RecentFile], for tool: Tool) {
        let key = storageKey(for: tool)
        if let data = try? JSONEncoder().encode(files) {
            UserDefaults.standard.set(data, forKey: key)
            postDidChange(for: tool)
        }
    }

    private static func postDidChange(for tool: Tool) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: didChangeNotification,
                object: nil,
                userInfo: ["toolID": tool.rawValue]
            )
        }
    }
}
