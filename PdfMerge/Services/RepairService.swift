import Foundation
import PDFKit

enum RepairService {

    // MARK: - Errors

    enum RepairError: LocalizedError {
        case documentUnreadable(URL)
        case repairFailed

        var errorDescription: String? {
            switch self {
            case .documentUnreadable(let url):
                return "Could not open \(url.lastPathComponent). It may be too damaged to repair."
            case .repairFailed:
                return "The file could not be repaired. It may be severely damaged."
            }
        }
    }

    // MARK: - Repair

    /// Attempt to repair a PDF by reading and rewriting it through PDFKit.
    /// This can fix minor structural issues (cross-reference table errors, etc.)
    /// by letting PDFKit parse what it can and produce a clean output.
    /// - Parameters:
    ///   - inputURL: Source PDF file (potentially damaged).
    ///   - outputURL: Destination for the repaired PDF.
    /// - Returns: The output URL.
    @discardableResult
    static func repair(
        inputURL: URL,
        outputURL: URL
    ) async throws -> URL {
        // Attempt to load the document; PDFKit is fairly tolerant of minor corruption
        guard let document = PDFDocument(url: inputURL) else {
            throw RepairError.documentUnreadable(inputURL)
        }

        // If locked, we can't rewrite without the password
        if document.isLocked {
            throw RepairError.documentUnreadable(inputURL)
        }

        // Rewrite page-by-page into a fresh document to strip corrupt structures
        let repairedDoc = PDFDocument()

        for pageIndex in 0..<document.pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }
            repairedDoc.insert(page, at: repairedDoc.pageCount)
        }

        guard repairedDoc.pageCount > 0 else {
            throw RepairError.repairFailed
        }

        return try FileService.atomicWrite(repairedDoc, to: outputURL)
    }
}
