import Foundation
import PDFKit

enum PDFLoadService {

    // MARK: - Errors

    enum LoadError: LocalizedError {
        case fileNotFound(URL)
        case unreadable(URL)
        case locked(URL)
        case invalidPassword

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "The file \(url.lastPathComponent) could not be found. It may have been moved or deleted."
            case .unreadable(let url):
                return "The file \(url.lastPathComponent) could not be opened. It may be damaged or not a valid PDF."
            case .locked(let url):
                return "The file \(url.lastPathComponent) is password-protected. Please enter the password to continue."
            case .invalidPassword:
                return "The password you entered is incorrect. Please try again."
            }
        }
    }

    // MARK: - Load

    /// Load a PDFDocument from the given URL, optionally unlocking with a password.
    static func loadDocument(from url: URL, password: String? = nil) throws -> PDFDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(url)
        }

        guard let document = PDFDocument(url: url) else {
            throw LoadError.unreadable(url)
        }

        if document.isLocked {
            guard let password = password, !password.isEmpty else {
                throw LoadError.locked(url)
            }
            guard document.unlock(withPassword: password) else {
                throw LoadError.invalidPassword
            }
        }

        return document
    }

    // MARK: - Inspection

    /// Check whether the PDF at the given URL is password-locked.
    static func isLocked(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        return document.isLocked
    }

    /// Check whether the given page index has extractable text (a text layer).
    static func hasTextLayer(document: PDFDocument, page: Int) -> Bool {
        guard page >= 0, page < document.pageCount,
              let pdfPage = document.page(at: page) else {
            return false
        }
        let text = pdfPage.string ?? ""
        // A page has a text layer if it contains at least some non-whitespace text
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check whether the document contains AcroForm fields.
    static func hasFormFields(document: PDFDocument) -> Bool {
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations {
                if annotation.widgetFieldType != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Check whether the document uses XFA forms (XML Forms Architecture).
    /// XFA forms embed XML in the document catalog; PDFKit has limited XFA support.
    static func isXFA(document: PDFDocument) -> Bool {
        // PDFKit does not expose the document catalog directly.
        // A practical heuristic: XFA forms typically have no standard AcroForm widgets
        // but do have form-like content. We check for the "XFA" key via document attributes.
        // Since PDFKit's public API is limited here, we check if the document's
        // metadata string contains XFA references.
        guard let metadata = document.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String else {
            // Fallback: scan first page annotations for XFA indicators
            // XFA documents loaded in PDFKit typically show 0 interactive annotations
            // but the raw PDF contains /XFA in its catalog.
            // Without CGPDFDocument access through public API, best-effort detection:
            if let data = document.dataRepresentation() {
                let searchRange = min(data.count, 4096)
                let headerData = data.prefix(searchRange)
                if let headerString = String(data: headerData, encoding: .ascii) {
                    return headerString.contains("/XFA")
                }
            }
            return false
        }
        return metadata.contains("XFA")
    }

    /// Return the page count for a PDF at the given URL, or nil if unreadable.
    static func pageCount(for url: URL) -> Int? {
        guard let document = PDFDocument(url: url) else { return nil }
        if document.isLocked { return nil }
        return document.pageCount
    }
}
