import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class ExtractPagesViewModel: ObservableObject {

    // MARK: - Selection Mode

    enum SelectionMode: String, CaseIterable, Identifiable {
        case visual
        case range

        var id: Self { self }

        var label: String {
            switch self {
            case .visual: "Visual"
            case .range: "Range"
            }
        }
    }

    // MARK: - Published State

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var selectionMode: SelectionMode = .visual {
        didSet { handleModeSwitch(from: oldValue, to: selectionMode) }
    }
    @Published var selectedPages: Set<Int> = []
    @Published var rangeText: String = "" {
        didSet { validateRange() }
    }
    @Published var rangeError: String?
    @Published var asSinglePDF: Bool = true
    @Published var outputSettings = OutputSettings(filename: "")

    let tool: Tool = .extractPages
    private var runningTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        document != nil
            && hasValidSelection
            && !operationStatus.isRunning
    }

    var disabledReason: String? {
        if document == nil { return "Drop a PDF to get started" }
        if !hasValidSelection { return "Select at least one page to extract" }
        return nil
    }

    var selectedPageCount: Int {
        switch selectionMode {
        case .visual:
            return selectedPages.count
        case .range:
            guard let doc = document else { return 0 }
            guard let ranges = try? PageRangeParser.parse(rangeText, totalPages: doc.pageCount) else {
                return 0
            }
            return ranges.reduce(0) { $0 + $1.count }
        }
    }

    var defaultFilename: String {
        guard let url = inputURL else { return "extracted.pdf" }
        return url.toolOutputName(.extractPages)
    }

    var defaultDirectory: URL? {
        inputURL?.deletingLastPathComponent()
    }

    private var hasValidSelection: Bool {
        switch selectionMode {
        case .visual:
            return !selectedPages.isEmpty
        case .range:
            guard let doc = document else { return false }
            return (try? PageRangeParser.parse(rangeText, totalPages: doc.pageCount)) != nil
        }
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            RecentFilesService.addRecentFile(url: url, for: tool)
            selectedPages = []
            rangeText = ""
            rangeError = nil
            operationStatus = .idle

            outputSettings.filename = defaultFilename
            outputSettings.saveDirectory = defaultDirectory
        } catch {
            document = nil
            inputURL = nil
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: false
            )
        }
    }

    // MARK: - Mode Switching

    private func handleModeSwitch(from oldMode: SelectionMode, to newMode: SelectionMode) {
        guard document != nil else { return }

        switch (oldMode, newMode) {
        case (.visual, .range):
            // Convert selected page set to range text
            if !selectedPages.isEmpty {
                rangeText = formatPagesAsRangeText(selectedPages)
            }
        case (.range, .visual):
            // Parse range text into selected pages
            if let doc = document,
               let ranges = try? PageRangeParser.parse(rangeText, totalPages: doc.pageCount) {
                selectedPages = Set(ranges.flatMap { $0.start...$0.end })
            }
        default:
            break
        }
    }

    /// Converts a set of 1-based page numbers into a compact range string.
    private func formatPagesAsRangeText(_ pages: Set<Int>) -> String {
        let sorted = pages.sorted()
        guard !sorted.isEmpty else { return "" }

        var segments: [String] = []
        var rangeStart = sorted[0]
        var rangeEnd = sorted[0]

        for i in 1..<sorted.count {
            if sorted[i] == rangeEnd + 1 {
                rangeEnd = sorted[i]
            } else {
                segments.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")
                rangeStart = sorted[i]
                rangeEnd = sorted[i]
            }
        }
        segments.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")

        return segments.joined(separator: ", ")
    }

    // MARK: - Range Validation

    func validateRange() {
        guard selectionMode == .range else {
            rangeError = nil
            return
        }
        let trimmed = rangeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            rangeError = nil
            return
        }
        guard let doc = document else {
            rangeError = nil
            return
        }
        do {
            _ = try PageRangeParser.parse(rangeText, totalPages: doc.pageCount)
            rangeError = nil
        } catch {
            rangeError = ErrorMapper.map(error)
        }
    }

    // MARK: - Execute

    func execute() {
        guard let doc = document, let url = inputURL else { return }

        let pages: [Int]
        switch selectionMode {
        case .visual:
            pages = selectedPages.sorted()
        case .range:
            guard let ranges = try? PageRangeParser.parse(rangeText, totalPages: doc.pageCount) else { return }
            pages = ranges.flatMap { $0.start...$0.end }
        }

        let outputDir = outputSettings.saveDirectory ?? url.deletingLastPathComponent()
        let filename = outputSettings.filename.isEmpty ? defaultFilename : outputSettings.filename
        let baseName = (filename as NSString).deletingPathExtension
        let openAfter = outputSettings.openAfterOperation
        let singlePDF = asSinglePDF
        let pageCount = pages.count

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Starting extraction\u{2026}")

                let outputs = try await ExtractService.extractPages(
                    from: doc,
                    sourceURL: url,
                    pages: pages,
                    asSinglePDF: singlePDF,
                    outputDirectory: outputDir,
                    outputFilename: baseName
                ) { current, total in
                    Task { @MainActor in
                        self.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Extracting\u{2026} \(current) of \(total) pages"
                        )
                    }
                }

                let summary: String
                if singlePDF, let first = outputs.first {
                    summary = "Extracted \(pageCount) pages \u{2192} \(first.lastPathComponent)"
                } else {
                    summary = "Extracted \(pageCount) pages into \(outputs.count) files"
                }

                operationStatus = .success(
                    message: summary,
                    outputURL: outputs.first
                )

                if openAfter, let first = outputs.first {
                    NSWorkspace.shared.openInPreview(url: first)
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
        outputSettings.resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func outputFileExists() -> Bool {
        if asSinglePDF {
            return outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        }
        return multiFileOutputExists()
    }

    private func multiFileOutputExists() -> Bool {
        guard let url = inputURL else { return false }
        let outputDir = outputSettings.saveDirectory ?? url.deletingLastPathComponent()
        let filename = outputSettings.filename.isEmpty ? defaultFilename : outputSettings.filename
        let baseName = (filename as NSString).deletingPathExtension

        let pages: [Int]
        switch selectionMode {
        case .visual:
            pages = selectedPages.sorted()
        case .range:
            guard let doc = document,
                  let ranges = try? PageRangeParser.parse(rangeText, totalPages: doc.pageCount) else { return false }
            pages = ranges.flatMap { $0.start...$0.end }
        }

        for pageNum in pages {
            let target = outputDir.appendingPathComponent("\(baseName)_page\(pageNum).pdf")
            if FileService.destinationExists(target) { return true }
        }
        return false
    }

    func executeWithCopyName() {
        outputSettings.applyCopyName(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        execute()
    }
}
