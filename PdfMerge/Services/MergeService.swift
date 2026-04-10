import Foundation
import PDFKit

enum MergeService {

    // MARK: - Errors

    enum MergeError: LocalizedError {
        case noFiles
        case fileUnreadable(URL)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noFiles:
                return "No files were provided to merge. Please add at least two PDF files."
            case .fileUnreadable(let url):
                return "The file \(url.lastPathComponent) could not be read. It may be damaged or password-protected."
            case .cancelled:
                return "The merge was cancelled."
            }
        }
    }

    // MARK: - Merge

    /// Merge multiple PDF files into a single output PDF.
    /// - Parameters:
    ///   - files: Ordered list of PDF file URLs and optional passwords to merge.
    ///   - outputURL: Destination URL for the merged PDF.
    ///   - progress: Callback reporting (filesProcessed, totalFiles).
    /// - Returns: The output URL on success.
    @discardableResult
    static func merge(
        files: [(url: URL, password: String?)],
        to outputURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        guard !files.isEmpty else {
            throw MergeError.noFiles
        }

        let merged = PDFDocument()
        let totalFiles = files.count
        var pageOffset = 0

        for (fileIndex, fileURL) in files.enumerated() {
            // Check cancellation at each file boundary
            try Task.checkCancellation()

            let source = try PDFLoadService.loadDocument(from: fileURL.url, password: fileURL.password)

            for pageIndex in 0..<source.pageCount {
                guard let page = source.page(at: pageIndex) else { continue }
                merged.insert(page, at: pageOffset)
                pageOffset += 1
            }

            progress(fileIndex + 1, totalFiles)
        }

        return try FileService.atomicWrite(merged, to: outputURL)
    }
}
