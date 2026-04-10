import Foundation
import PDFKit
import AppKit

/// Shared logic for ViewModels that manage a list of PDF files with thumbnails,
/// password unlock, and recent-file tracking (Merge, Compress).
@MainActor
final class FileListManager {
    private let passwordStore = FilePasswordStore.shared

    var files: [PDFFileItem] = []

    func password(for item: PDFFileItem) -> String? {
        passwordStore.password(for: item.id)
    }

    // MARK: - Load URLs

    /// Load URLs into the file list, skipping duplicates. Generates thumbnails for unlocked files.
    func loadURLs(_ urls: [URL], tool: Tool) async {
        for url in urls {
            guard !files.contains(where: { $0.url == url }) else { continue }
            RecentFilesService.addRecentFile(url: url, for: tool)

            let isLocked = PDFLoadService.isLocked(url)
            let pageCount = PDFLoadService.pageCount(for: url) ?? 0
            let fileSize = url.fileSize ?? 0

            var item = PDFFileItem(
                url: url,
                pageCount: pageCount,
                fileSize: fileSize,
                isLocked: isLocked
            )

            if !isLocked,
               let doc = try? PDFLoadService.loadDocument(from: url),
               let page = doc.page(at: 0) {
                item.thumbnail = await ThumbnailService.shared.generateThumbnail(
                    for: page, size: AppConstants.thumbnailSize
                )
            }

            files.append(item)
        }
    }

    // MARK: - Unlock

    /// Unlock a password-protected file in the list. Returns true on success.
    func unlockFile(_ item: PDFFileItem, password: String) -> Bool {
        guard let index = files.firstIndex(where: { $0.id == item.id }) else { return false }
        guard let doc = try? PDFLoadService.loadDocument(from: item.url, password: password) else {
            return false
        }
        files[index].isLocked = false
        passwordStore.setPassword(password, for: item.id)
        files[index].pageCount = doc.pageCount

        if let page = doc.page(at: 0) {
            Task {
                let thumb = await ThumbnailService.shared.generateThumbnail(
                    for: page, size: AppConstants.thumbnailSize
                )
                if let idx = files.firstIndex(where: { $0.id == item.id }) {
                    files[idx].thumbnail = thumb
                }
            }
        }
        return true
    }

    // MARK: - Remove / Reorder / Clear

    func removeFile(_ item: PDFFileItem) {
        passwordStore.removePassword(for: item.id)
        files.removeAll { $0.id == item.id }
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
    }

    func clearAll() {
        passwordStore.removePasswords(for: files.map(\.id))
        files.removeAll()
    }
}
