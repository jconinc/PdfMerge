import Foundation
import PDFKit
import AppKit

// MARK: - SplitMode

enum SplitMode: String, CaseIterable, Identifiable {
    case byRange
    case everyN
    case byPage

    var id: Self { self }

    var label: String {
        switch self {
        case .byRange: "By Range"
        case .everyN: "Every N Pages"
        case .byPage: "Pick Pages"
        }
    }
}

// MARK: - SplitViewModel

@MainActor
final class SplitViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle

    @Published var splitMode: SplitMode = .byRange

    /// Each entry is a page range plus the desired output filename.
    @Published var ranges: [(PageRange, String)] = []

    @Published var everyNPages: Int = 5

    /// 1-based page numbers selected for extraction.
    @Published var selectedPages: Set<Int> = []

    /// When true, selected pages are combined into one PDF; otherwise one PDF per page.
    @Published var combineSinglePDF: Bool = true

    @Published var outputSettings: OutputSettings = OutputSettings(filename: "")

    // MARK: - Task Handle

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var canExecute: Bool {
        guard document != nil else { return false }
        if case .running = operationStatus { return false }

        switch splitMode {
        case .byRange:
            return !ranges.isEmpty
                && ranges.allSatisfy { $0.0.isValid(totalPages: pageCount) && !$0.1.isEmpty }
                && !hasOverlappingRanges

        case .everyN:
            return everyNPages >= 1 && everyNPages <= pageCount

        case .byPage:
            return !selectedPages.isEmpty
        }
    }

    var disabledReason: String? {
        guard document != nil else { return "Load a PDF first." }
        if case .running = operationStatus { return "Operation in progress." }

        switch splitMode {
        case .byRange:
            if ranges.isEmpty { return "Add at least one range." }
            if hasOverlappingRanges { return "Ranges overlap. Fix highlighted rows." }
            if ranges.contains(where: { !$0.0.isValid(totalPages: pageCount) }) {
                return "One or more ranges are out of bounds."
            }
            if ranges.contains(where: { $0.1.isEmpty }) {
                return "Every range needs a filename."
            }
            return nil

        case .everyN:
            if everyNPages < 1 { return "Must split into at least 1 page per file." }
            if everyNPages > pageCount { return "N exceeds total page count." }
            return nil

        case .byPage:
            if selectedPages.isEmpty { return "Select at least one page." }
            return nil
        }
    }

    // MARK: - Every-N Preview

    var everyNPreview: String {
        guard pageCount > 0, everyNPages >= 1 else { return "" }
        let fullChunks = pageCount / everyNPages
        let remainder = pageCount % everyNPages

        if remainder == 0 {
            return "This will create \(fullChunks) file\(fullChunks == 1 ? "" : "s") of \(everyNPages) page\(everyNPages == 1 ? "" : "s") each."
        } else {
            let totalFiles = fullChunks + 1
            return "This will create \(totalFiles) files of \(everyNPages) pages each (last file: \(remainder) page\(remainder == 1 ? "" : "s"))."
        }
    }

    // MARK: - Overlap Detection

    var hasOverlappingRanges: Bool {
        !overlappingRangeIndices.isEmpty
    }

    var overlappingRangeIndices: Set<Int> {
        var result = Set<Int>()
        let count = ranges.count
        guard count > 1 else { return result }

        for i in 0..<count {
            for j in (i + 1)..<count {
                let a = ranges[i].0
                let b = ranges[j].0
                // Two ranges overlap if a.start <= b.end && b.start <= a.end
                if a.start <= b.end && b.start <= a.end {
                    result.insert(i)
                    result.insert(j)
                }
            }
        }
        return result
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            operationStatus = .idle
            selectedPages = []
            ranges = []

            let stem = url.deletingPathExtension().lastPathComponent
            outputSettings.filename = "\(stem)_split"
            outputSettings.saveDirectory = url.deletingLastPathComponent()

            // Add a default first range if in range mode
            if pageCount > 0 {
                ranges = [(PageRange(start: 1, end: pageCount), "\(stem)_part1.pdf")]
            }

            saveRecentFile(url: url)
        } catch {
            operationStatus = .error(message: ErrorMapper.map(error), isRecoverable: true)
        }
    }

    // MARK: - Execute

    func execute() {
        guard canExecute, let document, let inputURL else { return }

        let outputDir = outputSettings.saveDirectory ?? inputURL.deletingLastPathComponent()
        let openAfter = outputSettings.openAfterOperation

        currentTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Splitting\u{2026}")

                let outputURLs: [URL]

                switch splitMode {
                case .byRange:
                    let rangesCopy = ranges
                    outputURLs = try await SplitService.splitByRanges(
                        document: document,
                        sourceURL: inputURL,
                        ranges: rangesCopy,
                        outputDirectory: outputDir,
                        progress: { [weak self] done, total in
                            Task { @MainActor in
                                self?.operationStatus = .running(
                                    progress: Double(done) / Double(total),
                                    message: "Splitting range \(done) of \(total)\u{2026}"
                                )
                            }
                        }
                    )

                case .everyN:
                    let n = everyNPages
                    outputURLs = try await SplitService.splitEveryN(
                        document: document,
                        sourceURL: inputURL,
                        n: n,
                        outputDirectory: outputDir,
                        progress: { [weak self] done, total in
                            Task { @MainActor in
                                self?.operationStatus = .running(
                                    progress: Double(done) / Double(total),
                                    message: "Creating part \(done) of \(total)\u{2026}"
                                )
                            }
                        }
                    )

                case .byPage:
                    let pages = selectedPages.sorted()
                    let asSingle = combineSinglePDF
                    outputURLs = try await SplitService.splitByPages(
                        document: document,
                        sourceURL: inputURL,
                        pages: pages,
                        asSinglePDF: asSingle,
                        outputDirectory: outputDir,
                        progress: { [weak self] done, total in
                            Task { @MainActor in
                                self?.operationStatus = .running(
                                    progress: Double(done) / Double(total),
                                    message: "Extracting page \(done) of \(total)\u{2026}"
                                )
                            }
                        }
                    )
                }

                let fileWord = outputURLs.count == 1 ? "file" : "files"
                operationStatus = .success(
                    message: "Split complete. Created \(outputURLs.count) \(fileWord).",
                    outputURL: outputURLs.first
                )

                if openAfter, let firstURL = outputURLs.first {
                    NSWorkspace.shared.openInPreview(url: firstURL)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch {
                operationStatus = .error(message: ErrorMapper.map(error), isRecoverable: true)
            }
        }
    }

    // MARK: - Cancel

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Overwrite Check

    /// Check whether any of the files that split would produce already exist.
    func outputFilesExist() -> Bool {
        guard let inputURL, let document else { return false }
        let outputDir = outputSettings.saveDirectory ?? inputURL.deletingLastPathComponent()
        let stem = inputURL.deletingPathExtension().lastPathComponent

        switch splitMode {
        case .byRange:
            for (_, filename) in ranges {
                let url = outputDir.appendingPathComponent(filename)
                if FileService.destinationExists(url) { return true }
            }
        case .everyN:
            let chunkCount = (document.pageCount + everyNPages - 1) / everyNPages
            for i in 1...chunkCount {
                let url = outputDir.appendingPathComponent("\(stem)_part\(i).pdf")
                if FileService.destinationExists(url) { return true }
            }
        case .byPage:
            if combineSinglePDF {
                let url = outputDir.appendingPathComponent("\(stem)_extracted.pdf")
                if FileService.destinationExists(url) { return true }
            } else {
                for page in selectedPages {
                    let url = outputDir.appendingPathComponent("\(stem)_page\(page).pdf")
                    if FileService.destinationExists(url) { return true }
                }
            }
        }
        return false
    }

    @Published var showOverwriteConfirmation = false

    // MARK: - Recent Files

    private func saveRecentFile(url: URL) {
        RecentFilesService.addRecentFile(url: url, for: .split)
    }
}
