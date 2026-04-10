import Foundation
import PDFKit

enum ExtractService {

    // MARK: - Errors

    enum ExtractError: LocalizedError {
        case invalidPageIndex(Int, totalPages: Int)
        case emptySelection
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidPageIndex(let page, let total):
                return "Page \(page) is out of range. The document has \(total) pages."
            case .emptySelection:
                return "No pages were selected. Please select at least one page to extract."
            case .cancelled:
                return "The extraction was cancelled."
            }
        }
    }

    // MARK: - Extract Pages

    /// Extract specified pages from a document into one or more output PDFs.
    /// - Parameters:
    ///   - document: The source PDF document.
    ///   - sourceURL: Original file URL (used for naming).
    ///   - pages: 1-based page numbers to extract.
    ///   - asSinglePDF: If true, combine all extracted pages into one PDF; otherwise create one PDF per page.
    ///   - outputDirectory: Directory to write output files.
    ///   - outputFilename: Base filename for the output (without extension).
    ///   - progress: Callback reporting (pagesProcessed, totalPages).
    /// - Returns: Array of output file URLs.
    @discardableResult
    static func extractPages(
        from document: PDFDocument,
        sourceURL: URL,
        pages: [Int],
        asSinglePDF: Bool,
        outputDirectory: URL,
        outputFilename: String,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        let totalPages = document.pageCount
        guard !pages.isEmpty else { throw ExtractError.emptySelection }

        // Validate all page numbers
        for page in pages {
            guard page >= 1, page <= totalPages else {
                throw ExtractError.invalidPageIndex(page, totalPages: totalPages)
            }
        }

        if asSinglePDF {
            // Combine all selected pages into a single PDF
            let newDoc = PDFDocument()

            for (i, pageNum) in pages.enumerated() {
                try Task.checkCancellation()

                guard let page = document.page(at: pageNum - 1) else { continue }
                newDoc.insert(page, at: newDoc.pageCount)

                progress(i + 1, pages.count)
            }

            let filename = "\(outputFilename).pdf"
            let outputURL = outputDirectory.appendingPathComponent(filename)
            try FileService.atomicWrite(newDoc, to: outputURL)
            return [outputURL]

        } else {
            // Create one PDF per extracted page
            var outputs: [URL] = []

            for (i, pageNum) in pages.enumerated() {
                try Task.checkCancellation()

                guard let page = document.page(at: pageNum - 1) else { continue }

                let newDoc = PDFDocument()
                newDoc.insert(page, at: 0)

                let filename = "\(outputFilename)_page\(pageNum).pdf"
                let outputURL = outputDirectory.appendingPathComponent(filename)
                try FileService.atomicWrite(newDoc, to: outputURL)
                outputs.append(outputURL)

                progress(i + 1, pages.count)
            }

            return outputs
        }
    }
}
