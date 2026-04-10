import SwiftUI
import PDFKit
import Vision

// MARK: - OCR Mode

enum OCRMode: String, CaseIterable, Identifiable {
    case searchablePDF
    case extractText
    case both

    var id: Self { self }

    var label: String {
        switch self {
        case .searchablePDF: "Searchable PDF"
        case .extractText: "Extract Text"
        case .both: "Both"
        }
    }
}

// MARK: - OCRViewModel

@MainActor
final class OCRViewModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var ocrMode: OCRMode = .searchablePDF
    @Published var selectedLanguage: String = "en-US"
    @Published var availableLanguages: [String] = []
    @Published var accuracy: VNRequestTextRecognitionLevel = .accurate
    @Published var skipTextPages: Bool = true
    @Published var extractedText: String = ""
    @Published var outputSettings = OutputSettings(filename: "")

    let tool: Tool = .ocr
    private var runningTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        document != nil && !operationStatus.isRunning
    }

    var disabledReason: String? {
        if document == nil { return "Load a PDF to run OCR" }
        return nil
    }

    var defaultFilename: String {
        guard let url = inputURL else { return "ocr_output.pdf" }
        return url.deletingPathExtension().lastPathComponent + "_ocr.pdf"
    }

    var defaultDirectory: URL? {
        inputURL?.deletingLastPathComponent()
    }

    // MARK: - Init

    init() {
        availableLanguages = OCRService.supportedLanguages()
        if let preferred = availableLanguages.first {
            // Keep en-US if available, otherwise use first supported
            if !availableLanguages.contains(selectedLanguage) {
                selectedLanguage = preferred
            }
        }
    }

    // MARK: - File Management

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            RecentFilesService.addRecentFile(url: url, for: tool)
            operationStatus = .idle
            extractedText = ""

            outputSettings.filename = defaultFilename
            outputSettings.saveDirectory = defaultDirectory
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: false
            )
        }
    }

    // MARK: - Execute

    func execute() {
        guard let document, let inputURL else { return }

        let languages = [selectedLanguage]
        let currentAccuracy = accuracy
        let skip = skipTextPages
        let mode = ocrMode
        let openAfter = outputSettings.openAfterOperation
        let totalPages = document.pageCount

        guard let outputURL = outputSettings.resolvedURL(
            defaultFilename: defaultFilename,
            defaultDirectory: defaultDirectory
        ) else { return }

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Starting OCR\u{2026}")

                switch mode {
                case .searchablePDF:
                    let result = try await OCRService.performOCR(
                        on: document,
                        outputURL: outputURL,
                        languages: languages,
                        accuracy: currentAccuracy,
                        skipTextPages: skip
                    ) { [weak self] current, total, skipped in
                        Task { @MainActor in
                            self?.operationStatus = .running(
                                progress: Double(current) / Double(total),
                                message: self?.progressMessage(current: current, total: total, skipped: skipped) ?? ""
                            )
                        }
                    }

                    operationStatus = .success(
                        message: "OCR complete \u{2192} \(result.lastPathComponent)",
                        outputURL: result
                    )

                    if openAfter {
                        NSWorkspace.shared.openInPreview(url: result)
                    }

                case .extractText:
                    let text = try await OCRService.extractText(
                        from: document,
                        languages: languages,
                        accuracy: currentAccuracy
                    ) { [weak self] current, total, skipped in
                        Task { @MainActor in
                            self?.operationStatus = .running(
                                progress: Double(current) / Double(total),
                                message: self?.progressMessage(current: current, total: total, skipped: skipped) ?? ""
                            )
                        }
                    }

                    extractedText = text
                    operationStatus = .success(
                        message: "Extracted text from \(totalPages) page\(totalPages == 1 ? "" : "s")",
                        outputURL: nil
                    )

                case .both:
                    // First: extract text
                    let text = try await OCRService.extractText(
                        from: document,
                        languages: languages,
                        accuracy: currentAccuracy
                    ) { [weak self] current, total, skipped in
                        Task { @MainActor in
                            self?.operationStatus = .running(
                                progress: Double(current) / Double(total) * 0.5,
                                message: "Extracting text\u{2026} page \(current) of \(total)"
                            )
                        }
                    }

                    extractedText = text

                    // Second: create searchable PDF
                    let result = try await OCRService.performOCR(
                        on: document,
                        outputURL: outputURL,
                        languages: languages,
                        accuracy: currentAccuracy,
                        skipTextPages: skip
                    ) { [weak self] current, total, skipped in
                        Task { @MainActor in
                            self?.operationStatus = .running(
                                progress: 0.5 + Double(current) / Double(total) * 0.5,
                                message: "Creating searchable PDF\u{2026} page \(current) of \(total)"
                            )
                        }
                    }

                    operationStatus = .success(
                        message: "OCR complete \u{2192} \(result.lastPathComponent)",
                        outputURL: result
                    )

                    if openAfter {
                        NSWorkspace.shared.openInPreview(url: result)
                    }
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: false
                )
            }
        }
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }

    // MARK: - Overwrite Check

    var outputURL: URL? {
        guard ocrMode != .extractText else { return nil }
        return outputSettings.resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func outputFileExists() -> Bool {
        guard ocrMode != .extractText else { return false }
        return outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func executeWithCopyName() {
        outputSettings.applyCopyName(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        execute()
    }

    // MARK: - Private

    private func progressMessage(current: Int, total: Int, skipped: Int) -> String {
        var msg = "Processing page \(current) of \(total)\u{2026}"
        if skipped > 0 {
            msg += " (skipped \(skipped) page\(skipped == 1 ? "" : "s") with text)"
        }
        return msg
    }
}
