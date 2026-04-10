import Foundation
import PDFKit
import AppKit

enum EditTextService {

    enum EditTextError: LocalizedError {
        case pageFlattenFailed(Int)

        var errorDescription: String? {
            switch self {
            case .pageFlattenFailed(let pageIndex):
                return "Could not flatten edits on page \(pageIndex + 1)."
            }
        }
    }

    // MARK: - Text Detection

    struct DetectedText {
        let text: String
        let bounds: CGRect
        let fontName: String
        let fontSize: CGFloat
        let textColor: NSColor
        let isFontApproximate: Bool
    }

    /// Detect the line of text at the given point on a PDF page.
    static func detectTextAtPoint(
        _ point: CGPoint,
        in page: PDFPage
    ) -> DetectedText? {
        guard let selection = page.selectionForLine(at: point),
              let text = selection.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let bounds = selection.bounds(for: page)

        // Extract font info from the attributed string
        var fontName = "Helvetica"
        var fontSize: CGFloat = 12
        var textColor: NSColor = .black
        var isFontApproximate = false

        if let attrString = selection.attributedString,
           attrString.length > 0 {
            let attributes = attrString.attributes(at: 0, effectiveRange: nil)

            if let font = attributes[.font] as? NSFont {
                let matched = matchFont(postScriptName: font.fontName)
                fontName = matched.name
                fontSize = font.pointSize
                isFontApproximate = matched.isApproximate
            }

            if let color = attributes[.foregroundColor] as? NSColor {
                textColor = color
            }
        }

        return DetectedText(
            text: text,
            bounds: bounds,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            isFontApproximate: isFontApproximate
        )
    }

    // MARK: - Font Matching

    struct FontMatch {
        let name: String
        let isApproximate: Bool
    }

    static func matchFont(postScriptName: String) -> FontMatch {
        // Try exact match first
        if NSFont(name: postScriptName, size: 12) != nil {
            return FontMatch(name: postScriptName, isApproximate: false)
        }

        // Lookup table: common PostScript names to macOS font names
        if let mapped = fontLookupTable[postScriptName],
           NSFont(name: mapped, size: 12) != nil {
            return FontMatch(name: mapped, isApproximate: false)
        }

        // Try partial matching on the base family name
        let baseName = postScriptName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "PS", with: "")
            .replacingOccurrences(of: "MT", with: "")
            .trimmingCharacters(in: .whitespaces)

        if NSFont(name: baseName, size: 12) != nil {
            return FontMatch(name: baseName, isApproximate: true)
        }

        // Serif/sans-serif fallback based on name heuristics
        let lowerName = postScriptName.lowercased()
        let isSerif = lowerName.contains("times") ||
            lowerName.contains("georgia") ||
            lowerName.contains("garamond") ||
            lowerName.contains("palatino") ||
            lowerName.contains("cambria") ||
            lowerName.contains("serif")

        let fallback = isSerif ? "Times-Roman" : "Helvetica"
        return FontMatch(name: fallback, isApproximate: true)
    }

    // MARK: - Font Lookup Table (50 common PostScript names)

    private static let fontLookupTable: [String: String] = [
        "TimesNewRomanPSMT": "Times New Roman",
        "TimesNewRomanPS-BoldMT": "Times New Roman Bold",
        "TimesNewRomanPS-ItalicMT": "Times New Roman Italic",
        "TimesNewRomanPS-BoldItalicMT": "Times New Roman Bold Italic",
        "ArialMT": "Arial",
        "Arial-BoldMT": "Arial Bold",
        "Arial-ItalicMT": "Arial Italic",
        "Arial-BoldItalicMT": "Arial Bold Italic",
        "HelveticaNeue": "Helvetica Neue",
        "HelveticaNeue-Bold": "Helvetica Neue Bold",
        "HelveticaNeue-Italic": "Helvetica Neue Italic",
        "HelveticaNeue-BoldItalic": "Helvetica Neue Bold Italic",
        "HelveticaNeue-Light": "Helvetica Neue Light",
        "HelveticaNeue-Medium": "Helvetica Neue Medium",
        "HelveticaNeue-Thin": "Helvetica Neue Thin",
        "HelveticaNeue-UltraLight": "Helvetica Neue UltraLight",
        "Helvetica-Bold": "Helvetica Bold",
        "Helvetica-Oblique": "Helvetica Oblique",
        "Helvetica-BoldOblique": "Helvetica Bold Oblique",
        "CourierNewPSMT": "Courier New",
        "CourierNewPS-BoldMT": "Courier New Bold",
        "CourierNewPS-ItalicMT": "Courier New Italic",
        "CourierNewPS-BoldItalicMT": "Courier New Bold Italic",
        "Courier-Bold": "Courier Bold",
        "Courier-Oblique": "Courier Oblique",
        "Courier-BoldOblique": "Courier Bold Oblique",
        "Georgia-Bold": "Georgia Bold",
        "Georgia-Italic": "Georgia Italic",
        "Georgia-BoldItalic": "Georgia Bold Italic",
        "Verdana-Bold": "Verdana Bold",
        "Verdana-Italic": "Verdana Italic",
        "Verdana-BoldItalic": "Verdana Bold Italic",
        "TrebuchetMS": "Trebuchet MS",
        "TrebuchetMS-Bold": "Trebuchet MS Bold",
        "TrebuchetMS-Italic": "Trebuchet MS Italic",
        "Calibri": "Calibri",
        "Calibri-Bold": "Calibri Bold",
        "Calibri-Italic": "Calibri Italic",
        "Cambria": "Cambria",
        "Cambria-Bold": "Cambria Bold",
        "Cambria-Italic": "Cambria Italic",
        "Palatino-Roman": "Palatino",
        "Palatino-Bold": "Palatino Bold",
        "Palatino-Italic": "Palatino Italic",
        "BookAntiqua": "Book Antiqua",
        "BookAntiqua-Bold": "Book Antiqua Bold",
        "GillSans": "Gill Sans",
        "GillSans-Bold": "Gill Sans Bold",
        "Futura-Medium": "Futura Medium",
        "Futura-Bold": "Futura Bold",
    ]

    // MARK: - Flatten Edits

    /// Flatten all edits into a new PDF document: white rect + FreeText overlay for each edit.
    static func flattenEdits(
        _ edits: [TextEdit],
        in document: PDFDocument,
        to outputURL: URL
    ) throws {
        // Group edits by page
        let editsByPage = Dictionary(grouping: edits) { $0.pageIndex }

        // Add annotations to a copy of the document
        guard let data = document.dataRepresentation(),
              let workingDoc = PDFDocument(data: data) else {
            throw FileService.FileError.writeFailed(outputURL)
        }

        for (pageIndex, pageEdits) in editsByPage {
            guard let page = workingDoc.page(at: pageIndex) else { continue }

            for edit in pageEdits {
                // White rectangle to cover original text
                let whiteRect = PDFAnnotation(bounds: edit.bounds, forType: .square, withProperties: nil)
                whiteRect.color = .white
                whiteRect.interiorColor = .white
                whiteRect.border = PDFBorder()
                whiteRect.border?.lineWidth = 0
                page.addAnnotation(whiteRect)

                // FreeText annotation with replacement text
                let freeText = PDFAnnotation(bounds: edit.bounds, forType: .freeText, withProperties: nil)
                freeText.contents = edit.replacementText
                freeText.font = NSFont(name: edit.fontName, size: edit.fontSize) ?? NSFont.systemFont(ofSize: edit.fontSize)
                freeText.fontColor = edit.textColor
                freeText.color = .clear
                freeText.border = PDFBorder()
                freeText.border?.lineWidth = 0
                page.addAnnotation(freeText)
            }
        }

        // Render each page to a new context to flatten annotations
        let flattenedDoc = PDFDocument()

        for i in 0..<workingDoc.pageCount {
            guard let page = workingDoc.page(at: i) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)

            let pdfData = NSMutableData()
            do {
                guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                      let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
                    throw EditTextError.pageFlattenFailed(i)
                }
                defer { context.closePDF() }

                let pageRect = mediaBox
                context.beginPDFPage([kCGPDFContextMediaBox as String: NSValue(rect: pageRect)] as CFDictionary)

                // Draw the page with its annotations into the context
                NSGraphicsContext.saveGraphicsState()
                let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.current = nsContext

                page.draw(with: .mediaBox, to: context)

                NSGraphicsContext.restoreGraphicsState()

                context.endPDFPage()
            } catch {
                throw EditTextError.pageFlattenFailed(i)
            }

            guard let flatPage = PDFDocument(data: pdfData as Data)?.page(at: 0) else {
                throw EditTextError.pageFlattenFailed(i)
            }
            flattenedDoc.insert(flatPage, at: flattenedDoc.pageCount)
        }

        try FileService.atomicWrite(flattenedDoc, to: outputURL)
    }
}
