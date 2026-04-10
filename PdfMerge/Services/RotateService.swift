import Foundation
import PDFKit

enum RotateService {

    // MARK: - Errors

    enum RotateError: LocalizedError {
        case invalidRotation(Int)
        case invalidPageIndex(Int, totalPages: Int)
        case emptyDocument

        var errorDescription: String? {
            switch self {
            case .invalidRotation(let degrees):
                return "Rotation of \(degrees) degrees is not supported. Use 90, 180, or 270."
            case .invalidPageIndex(let index, let total):
                return "Page \(index + 1) is out of range. The document has \(total) pages."
            case .emptyDocument:
                return "The document has no pages to rotate."
            }
        }
    }

    // MARK: - Rotate

    /// Rotate specific pages in a document by the given degrees.
    /// - Parameters:
    ///   - document: The source PDF document.
    ///   - rotations: A dictionary mapping 0-based page indices to rotation degrees (90, 180, 270).
    ///   - outputURL: Destination URL for the rotated PDF.
    /// - Returns: The output URL on success.
    @discardableResult
    static func rotate(
        document: PDFDocument,
        rotations: [Int: Int],
        to outputURL: URL
    ) async throws -> URL {
        let totalPages = document.pageCount
        guard totalPages > 0 else { throw RotateError.emptyDocument }

        // Validate all rotations first
        for (pageIndex, degrees) in rotations {
            guard pageIndex >= 0, pageIndex < totalPages else {
                throw RotateError.invalidPageIndex(pageIndex, totalPages: totalPages)
            }
            guard [90, 180, 270].contains(degrees) else {
                throw RotateError.invalidRotation(degrees)
            }
        }

        // Build a new document from a copy so we don't mutate the source
        guard let sourceData = document.dataRepresentation(),
              let workingDoc = PDFDocument(data: sourceData) else {
            throw RotateError.emptyDocument
        }

        for pageIndex in 0..<totalPages {
            try Task.checkCancellation()

            guard let page = workingDoc.page(at: pageIndex) else { continue }

            if let degreesToRotate = rotations[pageIndex] {
                page.rotation = (page.rotation + degreesToRotate) % 360
            }
        }

        return try FileService.atomicWrite(workingDoc, to: outputURL)
    }
}
