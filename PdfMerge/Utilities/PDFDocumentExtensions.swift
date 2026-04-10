import PDFKit

extension PDFDocument {

    /// Returns `true` when the page at `pageIndex` already contains selectable text.
    func hasTextLayer(on pageIndex: Int) -> Bool {
        guard let page = page(at: pageIndex) else { return false }
        let text = page.string ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// All widget annotations (form fields) across every page.
    var formFields: [PDFAnnotation] {
        (0..<pageCount).flatMap { index -> [PDFAnnotation] in
            guard let page = page(at: index) else { return [] }
            return page.annotations.filter { $0.type == "Widget" }
        }
    }

    /// Returns `true` when the PDF uses an XFA form definition (unsupported by PDFKit).
    /// Uses a heuristic: scan the first few KB of the PDF data for an /XFA key reference.
    var isXFA: Bool {
        guard let data = dataRepresentation() else { return false }
        let searchRange = min(data.count, 8192)
        let headerData = data.prefix(searchRange)
        guard let headerString = String(data: headerData, encoding: .ascii) else { return false }
        return headerString.contains("/XFA")
    }
}
