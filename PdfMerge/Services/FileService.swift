import Foundation
import PDFKit

enum FileService {

    // MARK: - Errors

    enum FileError: LocalizedError {
        case writeFailed(URL)
        case replaceFailed(URL, underlying: Error)
        case directoryNotFound(URL)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let url):
                return "Could not save the file to \(url.lastPathComponent). Please check you have write permission for that folder."
            case .replaceFailed(let url, let underlying):
                return "Could not replace \(url.lastPathComponent): \(underlying.localizedDescription)"
            case .directoryNotFound(let url):
                return "The folder \(url.path) does not exist."
            }
        }
    }

    // MARK: - Atomic Write (PDFDocument)

    /// Write a PDFDocument to `destination` atomically using a temp file + rename.
    @discardableResult
    static func atomicWrite(
        _ document: PDFDocument,
        to destination: URL,
        options: [PDFDocument.WriteOption: Any] = [:]
    ) throws -> URL {
        let directory = destination.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw FileError.directoryNotFound(directory)
        }

        let tempName = ".pdftool_\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)

        let success: Bool
        if options.isEmpty {
            success = document.write(to: tempURL)
        } else {
            success = document.write(to: tempURL, withOptions: options)
        }

        guard success else {
            cleanupTempFile(tempURL)
            throw FileError.writeFailed(destination)
        }

        do {
            // replaceItemAt atomically replaces, handling existing files
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            cleanupTempFile(tempURL)
            throw FileError.replaceFailed(destination, underlying: error)
        }

        return destination
    }

    // MARK: - Atomic Write (Data)

    /// Write raw data to `destination` atomically using a temp file + rename.
    @discardableResult
    static func atomicWrite(_ data: Data, to destination: URL) throws -> URL {
        let directory = destination.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw FileError.directoryNotFound(directory)
        }

        let tempName = ".pdftool_\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            cleanupTempFile(tempURL)
            throw FileError.writeFailed(destination)
        }

        do {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
        } catch {
            cleanupTempFile(tempURL)
            throw FileError.replaceFailed(destination, underlying: error)
        }

        return destination
    }

    // MARK: - Destination Helpers

    /// Check whether a file already exists at the given URL.
    static func destinationExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Generate a non-conflicting copy name (e.g. `file_copy.pdf`, `file_copy 2.pdf`).
    static func generateCopyName(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension

        let copyName = "\(stem)_copy.\(ext)"
        let candidate = directory.appendingPathComponent(copyName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        var counter = 2
        while true {
            let numbered = "\(stem)_copy \(counter).\(ext)"
            let numberedURL = directory.appendingPathComponent(numbered)
            if !FileManager.default.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
            counter += 1
        }
    }

    // MARK: - Temp File Cleanup

    /// Delete orphaned `.pdftool_*.tmp` files older than 1 hour in the given directory.
    static func cleanupOrphanedTempFiles(in directory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else { return }

        let cutoff = Date().addingTimeInterval(-AppConstants.orphanTempFileAge)

        for fileURL in contents {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix(AppConstants.tempFilePrefix), name.hasSuffix(AppConstants.tempFileSuffix) else { continue }

            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               modified < cutoff {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    /// Delete a specific temp file if it exists.
    static func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
