import Foundation
import PDFKit
import AppKit

enum ConvertService {

    // MARK: - Types

    enum ImageFormat: String, CaseIterable {
        case jpg
        case png
        case tiff

        var utType: String {
            switch self {
            case .jpg: return "public.jpeg"
            case .png: return "public.png"
            case .tiff: return "public.tiff"
            }
        }

        var fileExtension: String { rawValue }
    }

    enum PageSize: String, CaseIterable {
        case a4
        case letter
        case fitToImage

        var label: String {
            switch self {
            case .a4: return "A4"
            case .letter: return "Letter"
            case .fitToImage: return "Fit to Image"
            }
        }

        /// Size in points (72 dpi).
        var sizeInPoints: CGSize? {
            switch self {
            case .a4: return CGSize(width: 595.28, height: 841.89)
            case .letter: return CGSize(width: 612, height: 792)
            case .fitToImage: return nil
            }
        }
    }

    // MARK: - Errors

    enum ConvertError: LocalizedError {
        case emptyDocument
        case renderFailed(Int)
        case imageWriteFailed(URL)
        case imageLoadFailed(URL)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .emptyDocument:
                return "The document has no pages to convert."
            case .renderFailed(let page):
                return "Could not render page \(page + 1) as an image."
            case .imageWriteFailed(let url):
                return "Could not save the image to \(url.lastPathComponent)."
            case .imageLoadFailed(let url):
                return "Could not open \(url.lastPathComponent) as an image."
            case .cancelled:
                return "The conversion was cancelled."
            }
        }
    }

    // MARK: - PDF to Images

    /// Convert PDF pages to image files.
    /// - Parameters:
    ///   - document: Source PDF document.
    ///   - sourceURL: Original file URL (for naming).
    ///   - format: Output image format.
    ///   - resolution: DPI for rendering (default 150).
    ///   - pages: Optional 0-based page indices to convert. Nil means all pages.
    ///   - outputDirectory: Directory for output images.
    ///   - progress: Callback reporting (pagesProcessed, totalPages).
    /// - Returns: Array of image file URLs.
    static func pdfToImages(
        document: PDFDocument,
        sourceURL: URL,
        format: ImageFormat,
        resolution: Int = 150,
        pages: [Int]? = nil,
        outputDirectory: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [URL] {
        let totalPages = document.pageCount
        guard totalPages > 0 else { throw ConvertError.emptyDocument }

        let pageIndices = pages ?? Array(0..<totalPages)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let scale = CGFloat(resolution) / 72.0
        var outputs: [URL] = []

        for (i, pageIndex) in pageIndices.enumerated() {
            try Task.checkCancellation()

            guard let page = document.page(at: pageIndex) else { continue }
            let mediaBox = page.bounds(for: .mediaBox)

            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)

            guard let cgImage = renderPageToCGImage(page: page, width: width, height: height) else {
                throw ConvertError.renderFailed(pageIndex)
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

            let filename = "\(stem)_page\(pageIndex + 1).\(format.fileExtension)"
            let outputURL = outputDirectory.appendingPathComponent(filename)

            guard let imageData = imageRepresentation(for: nsImage, format: format) else {
                throw ConvertError.imageWriteFailed(outputURL)
            }

            try FileService.atomicWrite(imageData, to: outputURL)
            outputs.append(outputURL)

            progress(i + 1, pageIndices.count)
        }

        return outputs
    }

    // MARK: - Images to PDF

    /// Convert image files into a single PDF.
    /// - Parameters:
    ///   - imageURLs: Ordered list of image file URLs.
    ///   - pageSize: Target page size.
    ///   - outputURL: Destination URL for the PDF.
    ///   - progress: Callback reporting (imagesProcessed, totalImages).
    /// - Returns: The output URL.
    @discardableResult
    static func imagesToPDF(
        imageURLs: [URL],
        pageSize: PageSize,
        outputURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        guard !imageURLs.isEmpty else { throw ConvertError.emptyDocument }

        let document = PDFDocument()

        for (i, imageURL) in imageURLs.enumerated() {
            try Task.checkCancellation()

            guard let nsImage = NSImage(contentsOf: imageURL) else {
                throw ConvertError.imageLoadFailed(imageURL)
            }

            if let targetSize = pageSize.sizeInPoints {
                // Render the image scaled-to-fit and centered on a fixed-size page
                guard let page = renderImageToPage(nsImage, targetSize: targetSize) else {
                    throw ConvertError.imageLoadFailed(imageURL)
                }
                document.insert(page, at: document.pageCount)
            } else {
                // fitToImage: page sized to match the image
                guard let page = PDFPage(image: nsImage) else {
                    throw ConvertError.imageLoadFailed(imageURL)
                }
                document.insert(page, at: document.pageCount)
            }

            progress(i + 1, imageURLs.count)
        }

        return try FileService.atomicWrite(document, to: outputURL)
    }

    // MARK: - Page Sizing

    /// Render an image scaled-to-fit and centered on a page of the given size.
    private static func renderImageToPage(_ image: NSImage, targetSize: CGSize) -> PDFPage? {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (targetSize.width - scaledWidth) / 2
        let offsetY = (targetSize.height - scaledHeight) / 2

        // Draw the image centered on a white page via CGContext → PDF data → PDFPage
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }

        var mediaBox = CGRect(origin: .zero, size: targetSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)

        // White background
        context.setFillColor(CGColor.white)
        context.fill(mediaBox)

        // Draw the image scaled and centered
        let drawRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: drawRect)
        }

        context.endPDFPage()
        context.closePDF()

        return PDFDocument(data: pdfData as Data)?.page(at: 0)
    }

    // MARK: - Private Helpers

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

    private static func imageRepresentation(for image: NSImage, format: ImageFormat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        switch format {
        case .jpg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .tiff:
            return bitmap.representation(using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw])
        }
    }
}
