import Foundation
import PDFKit
import AppKit

@MainActor
final class RotateViewModel: ObservableObject {

    // MARK: - Published State

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var selectedPages: Set<Int> = []
    @Published var pendingRotations: [Int: Int] = [:]
    @Published var outputSettings = OutputSettings(filename: "")

    // MARK: - Overwrite Confirmation

    @Published var showOverwriteConfirmation = false

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed

    var canExecute: Bool {
        document != nil && !pendingRotations.isEmpty
    }

    var disabledReason: String? {
        if document == nil { return "Load a PDF first" }
        if pendingRotations.isEmpty { return "No changes to save" }
        return nil
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    // MARK: - Load File

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            selectedPages = []
            pendingRotations = [:]
            operationStatus = .idle

            // Set default output settings
            outputSettings.filename = url.toolOutputName(.rotate)
            outputSettings.saveDirectory = url.deletingLastPathComponent()
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: true
            )
        }
    }

    // MARK: - Rotation Actions

    /// Rotate selected pages 90 degrees clockwise.
    func rotateRight() {
        applyRotation(degrees: 90)
    }

    /// Rotate selected pages 90 degrees counter-clockwise.
    func rotateLeft() {
        applyRotation(degrees: 270)
    }

    /// Rotate selected pages 180 degrees.
    func rotate180() {
        applyRotation(degrees: 180)
    }

    /// Reset all pending rotations.
    func resetAll() {
        pendingRotations = [:]
    }

    // MARK: - Execute

    /// Attempt to save. Shows overwrite confirmation if the destination file exists.
    func execute() {
        let outputURL = resolvedOutputURL
        if FileService.destinationExists(outputURL) {
            showOverwriteConfirmation = true
        } else {
            performSave(to: outputURL)
        }
    }

    /// Save, replacing the existing file.
    func executeReplace() {
        performSave(to: resolvedOutputURL)
    }

    /// Save as a copy with a non-conflicting name.
    func executeSaveAsCopy() {
        let copyURL = FileService.generateCopyName(for: resolvedOutputURL)
        performSave(to: copyURL)
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        operationStatus = .idle
    }

    // MARK: - Private Helpers

    private func applyRotation(degrees: Int) {
        guard !selectedPages.isEmpty else { return }

        for pageIndex in selectedPages {
            let current = pendingRotations[pageIndex] ?? 0
            let updated = (current + degrees) % 360
            if updated == 0 {
                pendingRotations.removeValue(forKey: pageIndex)
            } else {
                pendingRotations[pageIndex] = updated
            }
        }
    }

    private var resolvedOutputURL: URL {
        let directory = outputSettings.saveDirectory ?? inputURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        let filename = outputSettings.filename.isEmpty ? defaultFilename : outputSettings.filename
        return directory.appendingPathComponent(filename)
    }

    private var defaultFilename: String {
        guard let inputURL else { return "rotated.pdf" }
        return inputURL.toolOutputName(.rotate)
    }

    private func performSave(to outputURL: URL) {
        guard let document else { return }

        currentTask = Task {
            operationStatus = .running(progress: 0.0, message: "Rotating pages\u{2026}")

            do {
                try Task.checkCancellation()

                let result = try await RotateService.rotate(
                    document: document,
                    rotations: pendingRotations,
                    to: outputURL
                )

                operationStatus = .success(
                    message: "Saved to \(result.lastPathComponent)",
                    outputURL: result
                )

                // Add to recent files
                if let inputURL {
                    addToRecentFiles(url: inputURL)
                }

                // Open in Preview if requested
                if outputSettings.openAfterOperation {
                    NSWorkspace.shared.openInPreview(url: result)
                }
            } catch is CancellationError {
                operationStatus = .idle
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: true
                )
            }

            currentTask = nil
        }
    }

    // MARK: - Recent Files

    private func addToRecentFiles(url: URL) {
        RecentFilesService.addRecentFile(url: url, for: .rotate)
    }
}
