import Foundation
import PDFKit
import Vision
import CoreGraphics

enum OCRService {

    // MARK: - Errors

    enum OCRError: LocalizedError {
        case emptyDocument
        case renderFailed(Int)
        case noTextRecognized
        case cancelled

        var errorDescription: String? {
            switch self {
            case .emptyDocument:
                return "The document has no pages to process."
            case .renderFailed(let page):
                return "Could not render page \(page + 1) for text recognition."
            case .noTextRecognized:
                return "No text was recognized in the document. The pages may contain only graphics or very low-quality scans."
            case .cancelled:
                return "OCR was cancelled."
            }
        }
    }

    // MARK: - OCR with Invisible Text Layer

    /// Perform OCR on a document and write an invisible text layer into the output PDF.
    /// - Parameters:
    ///   - document: Source PDF document.
    ///   - outputURL: Destination for the OCR'd PDF.
    ///   - languages: Vision recognition languages (e.g. ["en-US"]).
    ///   - accuracy: Recognition level (.accurate or .fast).
    ///   - skipTextPages: If true, skip pages that already have a text layer.
    ///   - progress: Callback reporting (currentPage, totalPages, skippedPages).
    /// - Returns: The output URL.
    @discardableResult
    static func performOCR(
        on document: PDFDocument,
        outputURL: URL,
        languages: [String],
        accuracy: VNRequestTextRecognitionLevel = .accurate,
        skipTextPages: Bool = true,
        progress: @escaping @Sendable (Int, Int, Int) -> Void
    ) async throws -> URL {
        let totalPages = document.pageCount
        guard totalPages > 0 else { throw OCRError.emptyDocument }
        let renderScale = recommendedRenderScale(forPageCount: totalPages)

        // We'll build a new PDF with text layers using Core Graphics
        let outputDirectory = outputURL.deletingLastPathComponent()
        let tempName = ".pdftool_\(UUID().uuidString).tmp"
        let tempURL = outputDirectory.appendingPathComponent(tempName)

        var skippedCount = 0

        do {
            // Create PDF context for the output
            guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: nil, nil) else {
                throw OCRError.renderFailed(0)
            }
            defer { pdfContext.closePDF() }

            for pageIndex in 0..<totalPages {
                try Task.checkCancellation()

                guard let page = document.page(at: pageIndex) else { continue }
                let mediaBox = page.bounds(for: .mediaBox)

                // Check if we should skip this page
                if skipTextPages, PDFLoadService.hasTextLayer(document: document, page: pageIndex) {
                    // Copy the original page as-is
                    var box = mediaBox
                    pdfContext.beginPage(mediaBox: &box)
                    if let cgPage = page.pageRef {
                        pdfContext.drawPDFPage(cgPage)
                    }
                    pdfContext.endPage()
                    skippedCount += 1
                    progress(pageIndex + 1, totalPages, skippedCount)
                    continue
                }

                // Render the page to a CGImage for Vision
                let renderWidth = Int(mediaBox.width * renderScale)
                let renderHeight = Int(mediaBox.height * renderScale)

                guard let cgImage = renderPageToCGImage(page: page, width: renderWidth, height: renderHeight) else {
                    throw OCRError.renderFailed(pageIndex)
                }

                // Run text recognition
                let observations = try await recognizeText(
                    in: cgImage,
                    languages: languages,
                    accuracy: accuracy
                )

                // Write the page with invisible text overlay
                var box = mediaBox
                pdfContext.beginPage(mediaBox: &box)

                // Draw the original page content
                if let cgPage = page.pageRef {
                    pdfContext.drawPDFPage(cgPage)
                }

                // Overlay invisible text
                renderInvisibleTextLayer(
                    context: pdfContext,
                    observations: observations,
                    pageBox: mediaBox
                )

                pdfContext.endPage()
                progress(pageIndex + 1, totalPages, skippedCount)
            }
        } catch {
            FileService.cleanupTempFile(tempURL)
            throw error
        }

        // Move to final destination
        do {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
        } catch {
            FileService.cleanupTempFile(tempURL)
            throw error
        }

        return outputURL
    }

    // MARK: - Text Extraction (Plain Text)

    /// Extract text from all pages using Vision OCR, returning a single string.
    static func extractText(
        from document: PDFDocument,
        languages: [String],
        accuracy: VNRequestTextRecognitionLevel = .accurate,
        progress: @escaping @Sendable (Int, Int, Int) -> Void
    ) async throws -> String {
        let totalPages = document.pageCount
        guard totalPages > 0 else { throw OCRError.emptyDocument }
        let renderScale = recommendedRenderScale(forPageCount: totalPages)

        var allText: [String] = []
        var skippedCount = 0

        for pageIndex in 0..<totalPages {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }

            // First try to get existing text layer
            if let existingText = page.string, !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                allText.append(existingText)
                skippedCount += 1
                progress(pageIndex + 1, totalPages, skippedCount)
                continue
            }

            // Render and OCR
            let mediaBox = page.bounds(for: .mediaBox)
            let renderWidth = Int(mediaBox.width * renderScale)
            let renderHeight = Int(mediaBox.height * renderScale)

            guard let cgImage = renderPageToCGImage(page: page, width: renderWidth, height: renderHeight) else {
                progress(pageIndex + 1, totalPages, skippedCount)
                continue
            }

            let observations = try await recognizeText(
                in: cgImage,
                languages: languages,
                accuracy: accuracy
            )

            let pageText = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")

            if !pageText.isEmpty {
                allText.append(pageText)
            }

            progress(pageIndex + 1, totalPages, skippedCount)
        }

        let result = allText.joined(separator: "\n\n")
        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OCRError.noTextRecognized
        }
        return result
    }

    // MARK: - Supported Languages

    /// Return the list of languages supported by Vision text recognition on this system.
    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let languages = (try? request.supportedRecognitionLanguages()) ?? []
        return languages
    }

    // MARK: - Private: Render Page to CGImage

    private static func renderPageToCGImage(page: PDFPage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        // White background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let mediaBox = page.bounds(for: .mediaBox)
        let scaleX = CGFloat(width) / mediaBox.width
        let scaleY = CGFloat(height) / mediaBox.height

        context.scaleBy(x: scaleX, y: scaleY)
        context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)

        if let cgPage = page.pageRef {
            context.drawPDFPage(cgPage)
        }

        return context.makeImage()
    }

    // MARK: - Private: Recognize Text

    private static func recognizeText(
        in image: CGImage,
        languages: [String],
        accuracy: VNRequestTextRecognitionLevel
    ) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            func resumeOnce(with result: Result<[VNRecognizedTextObservation], Error>) {
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    resumeOnce(with: .failure(error))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                resumeOnce(with: .success(observations))
            }

            request.recognitionLevel = accuracy
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                resumeOnce(with: .failure(error))
            }
        }
    }

    private static func recommendedRenderScale(forPageCount pageCount: Int) -> CGFloat {
        switch pageCount {
        case 0..<50:
            return 2.0
        case 50..<200:
            return 1.5
        default:
            return 1.0
        }
    }

    // MARK: - Private: Render Invisible Text Layer

    /// Render recognized text as invisible (transparent) characters positioned to match
    /// the original text locations. This makes the text selectable and searchable.
    private static func renderInvisibleTextLayer(
        context: CGContext,
        observations: [VNRecognizedTextObservation],
        pageBox: CGRect
    ) {
        context.saveGState()

        // Set text to be completely invisible
        context.setTextDrawingMode(.invisible)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string

            // Vision coordinates: bottom-left origin, normalized (0-1).
            // Map to page coordinates using the crop/media box.
            let boundingBox = observation.boundingBox
            let x = pageBox.origin.x + boundingBox.origin.x * pageBox.width
            let y = pageBox.origin.y + boundingBox.origin.y * pageBox.height
            let width = boundingBox.width * pageBox.width
            let height = boundingBox.height * pageBox.height

            // Estimate font size from bounding box height
            let fontSize = max(height * 0.8, 1.0)

            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: CGColor(gray: 0, alpha: 0) // Fully transparent
            ]

            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)

            context.saveGState()
            context.textPosition = CGPoint(x: x, y: y)

            // Scale text to fit the observed bounding width
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            if lineWidth > 0 {
                let scaleX = width / CGFloat(lineWidth)
                context.scaleBy(x: scaleX, y: 1.0)
                context.textPosition = CGPoint(x: x / scaleX, y: y)
            }

            CTLineDraw(line, context)
            context.restoreGState()
        }

        context.restoreGState()
    }
}
