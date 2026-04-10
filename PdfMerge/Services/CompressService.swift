import Foundation
import PDFKit
import Quartz

enum CompressService {

    private struct PreparedInput {
        let cgDocument: CGPDFDocument
        let pdfDocument: PDFDocument?
        let inputFileSize: Int64
        let cleanup: () -> Void
    }

    // MARK: - Errors

    enum CompressError: LocalizedError {
        case filterNotFound(String)
        case compressionFailed
        case compressionUnavailable
        case outputLarger
        case preservationFailed(String)

        var errorDescription: String? {
            switch self {
            case .filterNotFound(let name):
                return "The compression filter \"\(name)\" is not available on this system."
            case .compressionFailed:
                return "Compression failed. The file may be damaged or use an unsupported format."
            case .compressionUnavailable:
                return "Compression isn't available on this system because the required Quartz filters could not be loaded."
            case .outputLarger:
                return "The compressed file would be larger than the original. The file may already be well-optimized."
            case .preservationFailed(let detail):
                return "Compression was aborted because it would lose \(detail). Try a higher quality preset."
            }
        }
    }

    // MARK: - Compress

    /// Compress a PDF using macOS Quartz filters with preset-specific quality settings.
    /// - Parameters:
    ///   - inputURL: Source PDF file URL.
    ///   - outputURL: Destination URL for the compressed PDF.
    ///   - preset: Compression quality preset.
    ///   - progress: Callback reporting (currentStep, totalSteps).
    /// - Returns: The output URL on success.
    @discardableResult
    static func compress(
        inputURL: URL,
        outputURL: URL,
        password: String? = nil,
        preset: CompressionPreset,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        progress(1, 4) // Step 1: Loading

        let preparedInput = try prepareInput(inputURL: inputURL, password: password)
        defer { preparedInput.cleanup() }

        let totalPages = preparedInput.cgDocument.numberOfPages

        // Capture input metadata for preservation check
        let inputOutlineCount = countOutlineItems(preparedInput.pdfDocument?.outlineRoot)
        let inputAnnotationCount = countAnnotations(preparedInput.pdfDocument)

        progress(2, 4) // Step 2: Creating filter

        // Create a custom Quartz filter with preset-specific parameters
        guard let filter = createCustomFilter(for: preset) else {
            // Fallback: try system filter, then PDFKit
            if let systemFilter = systemFilter() {
                return try await applyFilter(
                    systemFilter,
                    to: preparedInput.cgDocument,
                    totalPages: totalPages,
                    outputURL: outputURL,
                    inputFileSize: preparedInput.inputFileSize,
                    inputOutlineCount: inputOutlineCount,
                    inputAnnotationCount: inputAnnotationCount,
                    progress: progress
                )
            }
            throw CompressError.compressionUnavailable
        }

        progress(3, 4) // Step 3: Applying filter

        return try await applyFilter(
            filter,
            to: preparedInput.cgDocument,
            totalPages: totalPages,
            outputURL: outputURL,
            inputFileSize: preparedInput.inputFileSize,
            inputOutlineCount: inputOutlineCount,
            inputAnnotationCount: inputAnnotationCount,
            progress: progress
        )
    }

    // MARK: - Filter Application

    private static func applyFilter(
        _ filter: QuartzFilter,
        to cgDocument: CGPDFDocument,
        totalPages: Int,
        outputURL: URL,
        inputFileSize: Int64,
        inputOutlineCount: Int,
        inputAnnotationCount: Int,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        // Write the filtered PDF through a CGContext with the Quartz filter applied
        let outputDirectory = outputURL.deletingLastPathComponent()
        let tempName = ".pdftool_\(UUID().uuidString).tmp"
        let tempURL = outputDirectory.appendingPathComponent(tempName)

        do {
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792) // Default letter size
            guard let context = CGContext(tempURL as CFURL, mediaBox: &mediaBox, nil) else {
                throw CompressError.compressionFailed
            }
            defer { context.closePDF() }

            filter.apply(to: context)

            for pageNum in 1...totalPages {
                try Task.checkCancellation()

                guard let cgPage = cgDocument.page(at: pageNum) else { continue }
                var pageBox = cgPage.getBoxRect(.mediaBox)
                context.beginPage(mediaBox: &pageBox)
                context.drawPDFPage(cgPage)
                context.endPage()
            }
        } catch {
            FileService.cleanupTempFile(tempURL)
            throw error
        }

        progress(4, 4) // Step 4: Finalizing

        // Preservation check: verify bookmarks and annotations survived
        let outputDocument = PDFDocument(url: tempURL)
        let outputOutlineCount = countOutlineItems(outputDocument?.outlineRoot)
        let outputAnnotationCount = countAnnotations(outputDocument)

        if inputOutlineCount > 0 && outputOutlineCount < inputOutlineCount {
            FileService.cleanupTempFile(tempURL)
            throw CompressError.preservationFailed("bookmarks (\(inputOutlineCount) \u{2192} \(outputOutlineCount))")
        }

        if inputAnnotationCount > 0 && outputAnnotationCount < inputAnnotationCount {
            FileService.cleanupTempFile(tempURL)
            throw CompressError.preservationFailed("annotations (\(inputAnnotationCount) \u{2192} \(outputAnnotationCount))")
        }

        if inputFileSize > 0,
           let outputSize = tempURL.fileSize,
           outputSize >= inputFileSize {
            FileService.cleanupTempFile(tempURL)
            throw CompressError.outputLarger
        }

        // Move temp file to final destination atomically
        do {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
        } catch {
            FileService.cleanupTempFile(tempURL)
            throw CompressError.compressionFailed
        }

        return outputURL
    }

    // MARK: - Custom Filter Creation

    /// Create a Quartz filter by writing preset parameters to a temp plist and loading via `QuartzFilter(url:)`.
    /// This uses the documented public API rather than the non-existent `QuartzFilter(properties:)` initializer.
    private static func createCustomFilter(for preset: CompressionPreset) -> QuartzFilter? {
        let (quality, resolution, maxPixel, minPixel, name): (Double, Int, Int, Int, String) = {
            switch preset {
            case .screen:   return (0.1, 72,  512,  128, "PDF Tool Screen")
            case .ebook:    return (0.4, 150, 1024, 256, "PDF Tool eBook")
            case .printer:  return (0.7, 300, 2048, 512, "PDF Tool Printer")
            case .prepress: return (0.9, 300, 4096, 1024, "PDF Tool Prepress")
            }
        }()

        let filterDict: [String: Any] = [
            "CalFilter": [
                "ColorSettings": [
                    "ImageSettings": [
                        "ImageCompression": "ImageJPEGCompress",
                        "ImageQuality": quality,
                        "ImageScaleSettings": [
                            "ImageMaxPixelSize": maxPixel,
                            "ImageMinPixelSize": minPixel,
                            "ImageResolution": resolution
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "Domains": [
                "Applications": ["*"]
            ] as [String: Any],
            "FilterType": 1,
            "Name": name
        ] as [String: Any]

        // Write to a temporary .qfilter plist file and load via the documented API
        let tempDir = FileManager.default.temporaryDirectory
        let filterURL = tempDir.appendingPathComponent("PDFTool_\(preset.rawValue)_\(UUID().uuidString).qfilter")

        guard (filterDict as NSDictionary).write(to: filterURL, atomically: true) else {
            return nil
        }

        defer { try? FileManager.default.removeItem(at: filterURL) }

        return QuartzFilter(url: filterURL)
    }

    /// URL for the system "Reduce File Size" filter (fallback).
    private static func systemFilterURL() -> URL {
        URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
    }

    private static func systemFilter() -> QuartzFilter? {
        let url = systemFilterURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return QuartzFilter(url: url)
    }

    // MARK: - Preservation Helpers

    /// Recursively count outline (bookmark) items in a PDF.
    private static func countOutlineItems(_ outline: PDFOutline?) -> Int {
        guard let outline = outline else { return 0 }
        var count = 0
        for i in 0..<outline.numberOfChildren {
            count += 1
            if let child = outline.child(at: i) {
                count += countOutlineItems(child)
            }
        }
        return count
    }

    /// Count total annotations across all pages.
    private static func countAnnotations(_ document: PDFDocument?) -> Int {
        guard let document = document else { return 0 }
        var count = 0
        for i in 0..<document.pageCount {
            if let page = document.page(at: i) {
                count += page.annotations.count
            }
        }
        return count
    }

    // MARK: - Input Preparation

    private static func prepareInput(inputURL: URL, password: String?) throws -> PreparedInput {
        let inputFileSize = inputURL.fileSize ?? 0

        guard let password, !password.isEmpty else {
            guard let cgDocument = CGPDFDocument(inputURL as CFURL) else {
                throw CompressError.compressionFailed
            }
            return PreparedInput(
                cgDocument: cgDocument,
                pdfDocument: PDFDocument(url: inputURL),
                inputFileSize: inputFileSize,
                cleanup: {}
            )
        }

        let unlockedDocument = try PDFLoadService.loadDocument(from: inputURL, password: password)
        let unlockedTempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PdfMergeUnlocked_\(UUID().uuidString).pdf"
        )

        guard unlockedDocument.write(to: unlockedTempURL),
              let cgDocument = CGPDFDocument(unlockedTempURL as CFURL) else {
            FileService.cleanupTempFile(unlockedTempURL)
            throw CompressError.compressionFailed
        }

        return PreparedInput(
            cgDocument: cgDocument,
            pdfDocument: unlockedDocument,
            inputFileSize: inputFileSize,
            cleanup: {
                FileService.cleanupTempFile(unlockedTempURL)
            }
        )
    }
}
