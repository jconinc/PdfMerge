import Foundation
import PDFKit

enum SplitService {

    // MARK: - Errors

    enum SplitError: LocalizedError {
        case invalidRange(PageRange, totalPages: Int)
        case invalidPageIndex(Int, totalPages: Int)
        case emptySelection
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidRange(let range, let total):
                return "Page range \(range.start)-\(range.end) is invalid. The document has \(total) pages."
            case .invalidPageIndex(let page, let total):
                return "Page \(page) is out of range. The document has \(total) pages."
            case .emptySelection:
                return "No pages were selected for splitting."
            case .cancelled:
                return "The split was cancelled."
            }
        }
    }

    // MARK: - Split by Ranges

    /// Split a document into multiple PDFs, one per range. Each tuple is (range, outputFilename).
    static func splitByRanges(
        document: PDFDocument,
        sourceURL: URL,
        ranges: [(PageRange, String)],
        outputDirectory: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        guard !ranges.isEmpty else { throw SplitError.emptySelection }
        let totalPages = document.pageCount
        var outputs: [URL] = []
        let totalRanges = ranges.count

        for (rangeIndex, (range, filename)) in ranges.enumerated() {
            try Task.checkCancellation()

            guard range.isValid(totalPages: totalPages) else {
                throw SplitError.invalidRange(range, totalPages: totalPages)
            }

            let newDoc = PDFDocument()
            for pageNum in range.start...range.end {
                // pageNum is 1-based; PDFDocument uses 0-based indexing
                guard let page = document.page(at: pageNum - 1) else { continue }
                newDoc.insert(page, at: newDoc.pageCount)
            }

            let outputURL = outputDirectory.appendingPathComponent(filename)
            try FileService.atomicWrite(newDoc, to: outputURL)
            outputs.append(outputURL)

            progress(rangeIndex + 1, totalRanges)
        }

        return outputs
    }

    // MARK: - Split Every N Pages

    /// Split a document into chunks of N pages each.
    static func splitEveryN(
        document: PDFDocument,
        sourceURL: URL,
        n: Int,
        outputDirectory: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        let totalPages = document.pageCount
        guard totalPages > 0, n > 0 else { throw SplitError.emptySelection }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let chunkCount = (totalPages + n - 1) / n
        var outputs: [URL] = []

        for chunkIndex in 0..<chunkCount {
            try Task.checkCancellation()

            let startPage = chunkIndex * n
            let endPage = min(startPage + n - 1, totalPages - 1)

            let newDoc = PDFDocument()
            for pageIndex in startPage...endPage {
                guard let page = document.page(at: pageIndex) else { continue }
                newDoc.insert(page, at: newDoc.pageCount)
            }

            let filename = "\(stem)_part\(chunkIndex + 1).pdf"
            let outputURL = outputDirectory.appendingPathComponent(filename)
            try FileService.atomicWrite(newDoc, to: outputURL)
            outputs.append(outputURL)

            progress(chunkIndex + 1, chunkCount)
        }

        return outputs
    }

    // MARK: - Split by Individual Pages

    /// Extract specific pages, either as individual PDFs or combined into one.
    /// `pages` are 1-based page numbers.
    static func splitByPages(
        document: PDFDocument,
        sourceURL: URL,
        pages: [Int],
        asSinglePDF: Bool,
        outputDirectory: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        let totalPages = document.pageCount
        guard !pages.isEmpty else { throw SplitError.emptySelection }

        let stem = sourceURL.deletingPathExtension().lastPathComponent

        // Validate all page numbers first
        for page in pages {
            guard page >= 1, page <= totalPages else {
                throw SplitError.invalidPageIndex(page, totalPages: totalPages)
            }
        }

        if asSinglePDF {
            let newDoc = PDFDocument()
            for (i, pageNum) in pages.enumerated() {
                try Task.checkCancellation()
                guard let page = document.page(at: pageNum - 1) else { continue }
                newDoc.insert(page, at: newDoc.pageCount)
                progress(i + 1, pages.count)
            }

            let filename = "\(stem)_extracted.pdf"
            let outputURL = outputDirectory.appendingPathComponent(filename)
            try FileService.atomicWrite(newDoc, to: outputURL)
            return [outputURL]
        } else {
            var outputs: [URL] = []
            for (i, pageNum) in pages.enumerated() {
                try Task.checkCancellation()
                guard let page = document.page(at: pageNum - 1) else { continue }

                let newDoc = PDFDocument()
                newDoc.insert(page, at: 0)

                let filename = "\(stem)_page\(pageNum).pdf"
                let outputURL = outputDirectory.appendingPathComponent(filename)
                try FileService.atomicWrite(newDoc, to: outputURL)
                outputs.append(outputURL)

                progress(i + 1, pages.count)
            }
            return outputs
        }
    }
}
