import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class ConvertViewModel: ObservableObject {

    // MARK: - Mode

    @Published var mode: ConvertMode = .pdfToImages

    // MARK: - PDF Input (for pdfToImages, pdfToWord, pdfToExcel)

    @Published var document: PDFDocument?
    @Published var inputURL: URL?

    // MARK: - Image Input (for imagesToPDF)

    @Published var imageFiles: [PDFFileItem] = []

    // MARK: - Operation

    @Published var operationStatus: OperationStatus = .idle
    @Published var outputSettings = OutputSettings(filename: "")

    // MARK: - PDF to Images Settings

    @Published var imageFormat: ConvertService.ImageFormat = .jpg
    @Published var resolution: Int = 150
    @Published var pageRangeText: String = ""

    // MARK: - Images to PDF Settings

    @Published var pageSize: ConvertService.PageSize = .fitToImage

    // MARK: - Advanced (Word/Excel)

    @Published var pythonAvailable: Bool = PythonConvertService.isSetUp()
    @Published var hasTextLayer: Bool = true

    let tool: Tool = .convert
    private var runningTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        guard !operationStatus.isRunning else { return false }

        switch mode {
        case .pdfToImages:
            return document != nil
        case .imagesToPDF:
            return !imageFiles.isEmpty
        case .pdfToWord, .pdfToExcel:
            return document != nil && pythonAvailable
        }
    }

    var disabledReason: String? {
        switch mode {
        case .pdfToImages:
            if document == nil { return "Drop a PDF to convert" }
        case .imagesToPDF:
            if imageFiles.isEmpty { return "Add at least one image" }
        case .pdfToWord, .pdfToExcel:
            if !pythonAvailable { return "Word and Excel conversion is not set up" }
            if document == nil { return "Drop a PDF to convert" }
        }
        return nil
    }

    var defaultFilename: String {
        guard let url = inputURL else {
            if mode == .imagesToPDF, let first = imageFiles.first {
                return first.url.deletingPathExtension().lastPathComponent + "_converted.pdf"
            }
            return "converted"
        }
        let stem = url.deletingPathExtension().lastPathComponent
        switch mode {
        case .pdfToImages:
            return stem // Individual image files are named by ConvertService
        case .imagesToPDF:
            return stem + "_converted.pdf"
        case .pdfToWord:
            return stem + "_converted.docx"
        case .pdfToExcel:
            return stem + "_converted.xlsx"
        }
    }

    var defaultDirectory: URL? {
        if let url = inputURL {
            return url.deletingLastPathComponent()
        }
        return imageFiles.first?.url.deletingLastPathComponent()
    }

    private var actionLabel: String {
        switch mode {
        case .pdfToImages: return "Convert to Images"
        case .imagesToPDF: return "Convert to PDF"
        case .pdfToWord: return "Convert to Word"
        case .pdfToExcel: return "Convert to Excel"
        }
    }

    // MARK: - File Management

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            RecentFilesService.addRecentFile(url: url, for: tool)

            // Check text layer for Word/Excel warning
            hasTextLayer = PDFLoadService.hasTextLayer(document: doc, page: 0)

            outputSettings.filename = defaultFilename
            outputSettings.saveDirectory = defaultDirectory

            operationStatus = .idle
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: false
            )
        }
    }

    func addImages(_ urls: [URL]) {
        let imageTypes: [UTType] = [.jpeg, .png, .tiff, .heic, .bmp]

        for url in urls {
            guard !imageFiles.contains(where: { $0.url == url }) else { continue }

            let fileType = UTType(filenameExtension: url.pathExtension)
            let isImage = imageTypes.contains { type in
                fileType?.conforms(to: type) == true
            }
            guard isImage else { continue }

            let fileSize = url.fileSize ?? 0

            var item = PDFFileItem(
                url: url,
                pageCount: 1,
                fileSize: fileSize
            )

            // Generate thumbnail from the image
            if let nsImage = NSImage(contentsOf: url) {
                let thumbSize = AppConstants.thumbnailSize
                let thumb = NSImage(size: thumbSize, flipped: false) { rect in
                    nsImage.draw(in: rect)
                    return true
                }
                item.thumbnail = thumb
            }

            imageFiles.append(item)
        }

        if outputSettings.filename.isEmpty {
            outputSettings.filename = defaultFilename
        }
        if outputSettings.saveDirectory == nil {
            outputSettings.saveDirectory = defaultDirectory
        }
    }

    func removeImage(_ item: PDFFileItem) {
        imageFiles.removeAll { $0.id == item.id }
        if imageFiles.isEmpty {
            outputSettings = OutputSettings(filename: "")
        }
    }

    func moveImages(from source: IndexSet, to destination: Int) {
        imageFiles.move(fromOffsets: source, toOffset: destination)
    }

    func clearAll() {
        document = nil
        inputURL = nil
        imageFiles.removeAll()
        operationStatus = .idle
        outputSettings = OutputSettings(filename: "")
        pageRangeText = ""
    }

    // MARK: - Execute

    func execute() {
        switch mode {
        case .pdfToImages:
            executePDFToImages()
        case .imagesToPDF:
            executeImagesToPDF()
        case .pdfToWord:
            executePDFToWord()
        case .pdfToExcel:
            executePDFToExcel()
        }
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }

    // MARK: - Overwrite Check

    private var defaultExtension: String {
        switch mode {
        case .pdfToWord: "docx"
        case .pdfToExcel: "xlsx"
        default: "pdf"
        }
    }

    var outputURL: URL? {
        guard mode != .pdfToImages else { return nil }
        return outputSettings.resolvedURL(
            defaultFilename: defaultFilename,
            defaultDirectory: defaultDirectory,
            defaultExtension: defaultExtension
        )
    }

    func outputFileExists() -> Bool {
        if mode == .pdfToImages {
            return pdfToImagesOutputExists()
        }
        return outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    /// Check whether any of the image files that pdfToImages would write already exist.
    private func pdfToImagesOutputExists() -> Bool {
        guard let document, let inputURL else { return false }
        let outputDir = outputSettings.saveDirectory ?? inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let totalPages = document.pageCount
        let rangeText = pageRangeText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine which page indices (0-based) will be exported
        let pageIndices: [Int]
        if !rangeText.isEmpty,
           let ranges = try? PageRangeParser.parse(rangeText, totalPages: totalPages) {
            pageIndices = ranges.flatMap { ($0.start...$0.end).map { $0 - 1 } }
        } else {
            pageIndices = Array(0..<totalPages)
        }

        for i in pageIndices {
            let filename = "\(stem)_page\(i + 1).\(imageFormat.fileExtension)"
            let url = outputDir.appendingPathComponent(filename)
            if FileService.destinationExists(url) {
                return true
            }
        }
        return false
    }

    func executeWithCopyName() {
        outputSettings.applyCopyName(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        execute()
    }

    // MARK: - Private Execution

    private func executePDFToImages() {
        guard let document = document, let inputURL = inputURL else { return }

        let outputDir = outputSettings.saveDirectory ?? inputURL.deletingLastPathComponent()
        let format = imageFormat
        let dpi = resolution
        let rangeText = pageRangeText
        let openAfter = outputSettings.openAfterOperation
        let totalPages = document.pageCount

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Converting\u{2026}")

                // Parse optional page range
                var pageIndices: [Int]?
                if !rangeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let ranges = try PageRangeParser.parse(rangeText, totalPages: totalPages)
                    pageIndices = ranges.flatMap { ($0.start...$0.end).map { $0 - 1 } }
                }

                let outputs = try await ConvertService.pdfToImages(
                    document: document,
                    sourceURL: inputURL,
                    format: format,
                    resolution: dpi,
                    pages: pageIndices,
                    outputDirectory: outputDir
                ) { [weak self] current, total in
                    Task { @MainActor in
                        self?.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Converting\u{2026} page \(current) of \(total)"
                        )
                    }
                }

                let count = outputs.count
                operationStatus = .success(
                    message: "Exported \(count) image\(count == 1 ? "" : "s") to \(outputDir.lastPathComponent)/",
                    outputURL: outputs.first
                )

                if openAfter, let first = outputs.first {
                    NSWorkspace.shared.openInPreview(url: first)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch PythonConvertService.PythonError.cancelled {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: false
                )
            }
        }
    }

    private func executeImagesToPDF() {
        guard !imageFiles.isEmpty,
              let outputURL = outputSettings.resolvedURL(
                  defaultFilename: defaultFilename,
                  defaultDirectory: defaultDirectory
              ) else { return }
        let imageURLs = imageFiles.map(\.url)
        let size = pageSize
        let openAfter = outputSettings.openAfterOperation
        let totalImages = imageURLs.count

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Converting\u{2026}")

                let result = try await ConvertService.imagesToPDF(
                    imageURLs: imageURLs,
                    pageSize: size,
                    outputURL: outputURL
                ) { [weak self] current, total in
                    Task { @MainActor in
                        self?.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Converting\u{2026} image \(current) of \(total)"
                        )
                    }
                }

                operationStatus = .success(
                    message: "Created PDF from \(totalImages) image\(totalImages == 1 ? "" : "s") \u{2192} \(result.lastPathComponent)",
                    outputURL: result
                )

                if openAfter {
                    NSWorkspace.shared.openInPreview(url: result)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch PythonConvertService.PythonError.cancelled {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: false
                )
            }
        }
    }

    private func executePDFToWord() {
        guard let inputURL = inputURL,
              let outputURL = outputSettings.resolvedURL(
                  defaultFilename: defaultFilename,
                  defaultDirectory: defaultDirectory,
                  defaultExtension: "docx"
              ) else { return }
        let openAfter = outputSettings.openAfterOperation

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Converting to Word\u{2026}")

                let result = try await PythonConvertService.convertToWord(
                    inputURL: inputURL,
                    outputURL: outputURL
                ) { [weak self] current, total in
                    Task { @MainActor in
                        self?.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Converting to Word\u{2026} step \(current) of \(total)"
                        )
                    }
                }

                operationStatus = .success(
                    message: "Converted to Word \u{2192} \(result.lastPathComponent)",
                    outputURL: result
                )

                if openAfter {
                    NSWorkspace.shared.open(result)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch PythonConvertService.PythonError.cancelled {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: false
                )
            }
        }
    }

    private func executePDFToExcel() {
        guard let inputURL = inputURL,
              let outputURL = outputSettings.resolvedURL(
                  defaultFilename: defaultFilename,
                  defaultDirectory: defaultDirectory,
                  defaultExtension: "xlsx"
              ) else { return }
        let openAfter = outputSettings.openAfterOperation

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Converting to Excel\u{2026}")

                let result = try await PythonConvertService.convertToExcel(
                    inputURL: inputURL,
                    outputURL: outputURL
                ) { [weak self] current, total in
                    Task { @MainActor in
                        self?.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Converting to Excel\u{2026} step \(current) of \(total)"
                        )
                    }
                }

                operationStatus = .success(
                    message: "Converted to Excel \u{2192} \(result.lastPathComponent)",
                    outputURL: result
                )

                if openAfter {
                    NSWorkspace.shared.open(result)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch PythonConvertService.PythonError.cancelled {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: false
                )
            }
        }
    }
}
