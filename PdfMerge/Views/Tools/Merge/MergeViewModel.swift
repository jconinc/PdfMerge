import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class MergeViewModel: ObservableObject {
    @Published var files: [PDFFileItem] = []
    @Published var operationStatus: OperationStatus = .idle
    @Published var outputSettings = OutputSettings(filename: "")

    let tool: Tool = .merge
    private let fileManager = FileListManager()
    private var runningTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        files.count >= 2
            && !files.contains(where: { $0.isLocked })
            && !operationStatus.isRunning
    }

    var disabledReason: String? {
        if files.count < 2 { return "Add at least 2 PDFs to merge" }
        if files.contains(where: { $0.isLocked }) { return "Unlock all password-protected files before merging" }
        return nil
    }

    var defaultFilename: String {
        guard let first = files.first else { return "merged.pdf" }
        return first.url.toolOutputName(tool)
    }

    var defaultDirectory: URL? {
        files.first?.url.deletingLastPathComponent()
    }

    // MARK: - File Management

    func addFiles(_ urls: [URL]) {
        Task {
            await fileManager.loadURLs(urls, tool: tool)
            files = fileManager.files
            if outputSettings.filename.isEmpty { outputSettings.filename = defaultFilename }
            if outputSettings.saveDirectory == nil { outputSettings.saveDirectory = defaultDirectory }
        }
    }

    func removeFile(_ item: PDFFileItem) {
        fileManager.removeFile(item)
        files = fileManager.files
        if files.isEmpty { outputSettings = OutputSettings(filename: "") }
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        fileManager.moveFiles(from: source, to: destination)
        files = fileManager.files
    }

    func clearAll() {
        fileManager.clearAll()
        files = []
        operationStatus = .idle
        outputSettings = OutputSettings(filename: "")
    }

    func unlockFile(_ item: PDFFileItem, password: String) -> Bool {
        let result = fileManager.unlockFile(item, password: password)
        files = fileManager.files
        return result
    }

    // MARK: - Merge Execution

    func execute() {
        guard let outputURL else { return }
        let fileInputs = files.map { (url: $0.url, password: fileManager.password(for: $0)) }
        let openAfter = outputSettings.openAfterOperation
        let totalFiles = files.count

        runningTask = Task {
            do {
                operationStatus = .running(progress: 0, message: "Starting merge\u{2026}")

                let result = try await MergeService.merge(
                    files: fileInputs,
                    to: outputURL
                ) { [weak self] current, total in
                    Task { @MainActor in
                        self?.operationStatus = .running(
                            progress: Double(current) / Double(total),
                            message: "Merging\u{2026} \(current) of \(total)"
                        )
                    }
                }

                operationStatus = .success(
                    message: "Merged \(totalFiles) PDFs \u{2192} \(result.lastPathComponent)",
                    outputURL: result
                )

                if openAfter {
                    NSWorkspace.shared.openInPreview(url: result)
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
        outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func executeWithCopyName() {
        outputSettings.applyCopyName(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
        execute()
    }
}
