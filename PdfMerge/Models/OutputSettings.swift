import Foundation

struct OutputSettings {
    var filename: String = ""
    var saveDirectory: URL?
    var openAfterOperation: Bool = true

    /// Resolve the full output URL from settings + defaults.
    /// Ensures the filename has a `.pdf` extension if none is present.
    func resolvedURL(defaultFilename: String, defaultDirectory: URL?, defaultExtension: String = "pdf") -> URL? {
        let dir = saveDirectory ?? defaultDirectory
        guard let dir else { return nil }
        var name = filename.isEmpty ? defaultFilename : filename
        if URL(fileURLWithPath: name).pathExtension.isEmpty {
            name += ".\(defaultExtension)"
        }
        return dir.appendingPathComponent(name)
    }

    /// Check if the resolved output file already exists.
    func outputExists(defaultFilename: String, defaultDirectory: URL?) -> Bool {
        guard let url = resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory) else {
            return false
        }
        return FileService.destinationExists(url)
    }

    /// Generate a non-conflicting copy name and apply it to these settings.
    mutating func applyCopyName(defaultFilename: String, defaultDirectory: URL?) {
        guard let url = resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory) else { return }
        let copyURL = FileService.generateCopyName(for: url)
        filename = copyURL.lastPathComponent
        saveDirectory = copyURL.deletingLastPathComponent()
    }
}
