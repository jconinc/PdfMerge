import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class CompressViewModel: ObservableObject {
    @Published var files: [PDFFileItem] = []
    @Published var selectedPreset: CompressionPreset = .printer
    @Published var operationStatus: OperationStatus = .idle
    @Published var outputSettings = OutputSettings(filename: "")
    @Published var estimatedSize: String?

    let tool: Tool = .compress
    private let fileManager = FileListManager()
    private var runningTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        !files.isEmpty
            && !files.contains(where: { $0.isLocked })
            && !operationStatus.isRunning
    }

    var disabledReason: String? {
        if files.isEmpty { return "Add a PDF to compress" }
        if files.contains(where: { $0.isLocked }) { return "Unlock all password-protected files first" }
        return nil
    }

    var buttonLabel: String {
        files.count > 1 ? "Compress \(files.count) PDFs" : "Compress"
    }

    var defaultFilename: String {
        guard let first = files.first else { return "compressed.pdf" }
        return first.url.toolOutputName(tool)
    }

    var defaultDirectory: URL? {
        files.first?.url.deletingLastPathComponent()
    }

    var totalInputSize: Int64 {
        files.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - File Management

    func loadFiles(_ urls: [URL]) {
        Task {
            await fileManager.loadURLs(urls, tool: tool)
            files = fileManager.files
            if outputSettings.filename.isEmpty { outputSettings.filename = defaultFilename }
            if outputSettings.saveDirectory == nil { outputSettings.saveDirectory = defaultDirectory }
            updateEstimatedSize()
        }
    }

    func removeFile(_ item: PDFFileItem) {
        fileManager.removeFile(item)
        files = fileManager.files
        if files.isEmpty {
            outputSettings = OutputSettings(filename: "")
            estimatedSize = nil
        } else {
            updateEstimatedSize()
        }
    }

    func clearAll() {
        fileManager.clearAll()
        files = []
        operationStatus = .idle
        outputSettings = OutputSettings(filename: "")
        estimatedSize = nil
    }

    func unlockFile(_ item: PDFFileItem, password: String) -> Bool {
        let result = fileManager.unlockFile(item, password: password)
        files = fileManager.files
        return result
    }

    // MARK: - Size Estimation

    func updateEstimatedSize() {
        guard !files.isEmpty else {
            estimatedSize = nil
            return
        }

        let total = totalInputSize
        let ratio: Double
        switch selectedPreset {
        case .screen: ratio = 0.15
        case .ebook: ratio = 0.40
        case .printer: ratio = 0.70
        case .prepress: ratio = 0.85
        }

        let estimated = Int64(Double(total) * ratio)
        let inputFormatted = FileSizeFormatter.format(total)
        let outputFormatted = FileSizeFormatter.format(estimated)
        estimatedSize = "Estimated: \(inputFormatted) \u{2192} ~\(outputFormatted)"
    }

    // MARK: - Execute

    func execute() {
        let filesToCompress = files
        let outputDir = outputSettings.saveDirectory ?? files.first?.url.deletingLastPathComponent() ?? FileManager.default.temporaryDirectory
        let preset = selectedPreset
        let openAfter = outputSettings.openAfterOperation
        let fileCount = files.count

        runningTask = Task {
            do {
                if fileCount == 1 {
                    try await compressSingleFile(
                        file: filesToCompress[0],
                        outputDir: outputDir,
                        preset: preset,
                        openAfter: openAfter
                    )
                } else {
                    try await compressMultipleFiles(
                        files: filesToCompress,
                        outputDir: outputDir,
                        preset: preset,
                        openAfter: openAfter
                    )
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

    // MARK: - Single File Compression

    private func compressSingleFile(
        file: PDFFileItem,
        outputDir: URL,
        preset: CompressionPreset,
        openAfter: Bool
    ) async throws {
        guard let outputURL = outputSettings.resolvedURL(
            defaultFilename: defaultFilename,
            defaultDirectory: defaultDirectory
        ) else { return }

        operationStatus = .running(progress: 0, message: "Compressing\u{2026}")

        let result = try await CompressService.compress(
            inputURL: file.url,
            outputURL: outputURL,
            password: fileManager.password(for: file),
            preset: preset
        ) { [weak self] current, total in
            Task { @MainActor in
                self?.operationStatus = .running(
                    progress: Double(current) / Double(total),
                    message: "Compressing\u{2026} step \(current) of \(total)"
                )
            }
        }

        let inputSize = file.fileSize
        let outputSize = result.fileSize ?? 0
        let reduction = inputSize > 0
            ? Int(100 - (Double(outputSize) / Double(inputSize) * 100))
            : 0

        if reduction < 10 {
            operationStatus = .success(
                message: "This PDF is already well-optimized. Saved with minimal reduction (\(FileSizeFormatter.format(inputSize)) \u{2192} \(FileSizeFormatter.format(outputSize))).",
                outputURL: result
            )
        } else {
            operationStatus = .success(
                message: "Compressed: \(FileSizeFormatter.format(inputSize)) \u{2192} \(FileSizeFormatter.format(outputSize)) (\(reduction)% smaller)",
                outputURL: result
            )
        }

        if openAfter {
            NSWorkspace.shared.openInPreview(url: result)
        }
    }

    // MARK: - Multiple File Compression

    private func compressMultipleFiles(
        files: [PDFFileItem],
        outputDir: URL,
        preset: CompressionPreset,
        openAfter: Bool
    ) async throws {
        let totalFiles = files.count
        var totalInputBytes: Int64 = 0
        var totalOutputBytes: Int64 = 0
        var lastOutputURL: URL?

        for (index, file) in files.enumerated() {
            try Task.checkCancellation()

            let outputFilename = file.url.toolOutputName(.compress)
            let outputURL = outputDir.appendingPathComponent(outputFilename)

            operationStatus = .running(
                progress: Double(index) / Double(totalFiles),
                message: "Compressing file \(index + 1) of \(totalFiles)\u{2026}"
            )

            let result = try await CompressService.compress(
                inputURL: file.url,
                outputURL: outputURL,
                password: fileManager.password(for: file),
                preset: preset
            ) { _, _ in
                // Per-file sub-progress is folded into overall progress
            }

            totalInputBytes += file.fileSize
            totalOutputBytes += result.fileSize ?? 0
            lastOutputURL = result
        }

        let reduction = totalInputBytes > 0
            ? Int(100 - (Double(totalOutputBytes) / Double(totalInputBytes) * 100))
            : 0

        if reduction < 10 {
            operationStatus = .success(
                message: "These PDFs are already well-optimized. \(totalFiles) files saved with minimal reduction.",
                outputURL: lastOutputURL
            )
        } else {
            operationStatus = .success(
                message: "Compressed \(totalFiles) PDFs: \(FileSizeFormatter.format(totalInputBytes)) \u{2192} \(FileSizeFormatter.format(totalOutputBytes)) (\(reduction)% smaller)",
                outputURL: lastOutputURL
            )
        }

        if openAfter, let url = lastOutputURL {
            NSWorkspace.shared.openInPreview(url: url)
        }
    }

    // MARK: - Overwrite Check

    var outputURL: URL? {
        outputSettings.resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func outputFileExists() -> Bool {
        if files.count <= 1 {
            return outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        }
        // Multi-file: check each per-file output name
        return multiFileOutputExists()
    }

    private func multiFileOutputExists() -> Bool {
        let outputDir = outputSettings.saveDirectory ?? defaultDirectory ?? FileManager.default.temporaryDirectory
        for file in files {
            let name = file.url.toolOutputName(tool)
            if FileService.destinationExists(outputDir.appendingPathComponent(name)) {
                return true
            }
        }
        return false
    }

    func executeWithCopyName() {
        outputSettings.applyCopyName(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        execute()
    }
}
