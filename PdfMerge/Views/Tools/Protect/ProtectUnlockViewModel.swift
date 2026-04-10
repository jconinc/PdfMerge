import Foundation
import PDFKit
import AppKit

// MARK: - ProtectMode

enum ProtectMode: String, CaseIterable, Identifiable {
    case protect
    case unlock

    var id: Self { self }

    var label: String {
        switch self {
        case .protect: "Protect"
        case .unlock: "Unlock"
        }
    }
}

// MARK: - ProtectUnlockViewModel

@MainActor
final class ProtectUnlockViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var mode: ProtectMode = .protect
    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var outputSettings = OutputSettings(filename: "")

    // Protect mode
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var allowPrinting: Bool = true
    @Published var allowCopying: Bool = true

    // Unlock mode
    @Published var unlockPassword: String = ""
    @Published var isProtected: Bool = false
    @Published var unlockError: String?

    let tool: Tool = .protectUnlock

    // MARK: - Task Handle

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed Properties (Protect)

    var passwordsMatch: Bool {
        password == confirmPassword
    }

    var passwordError: String? {
        guard !password.isEmpty, !confirmPassword.isEmpty else { return nil }
        if !passwordsMatch {
            return "Passwords don't match"
        }
        return nil
    }

    // MARK: - Computed Properties (General)

    var canExecute: Bool {
        guard document != nil else { return false }
        if case .running = operationStatus { return false }

        switch mode {
        case .protect:
            return !isProtected && !password.isEmpty && !confirmPassword.isEmpty && passwordsMatch

        case .unlock:
            guard isProtected else { return false }
            return !unlockPassword.isEmpty
        }
    }

    var disabledReason: String? {
        guard document != nil else { return "Load a PDF first." }
        if case .running = operationStatus { return "Operation in progress." }

        switch mode {
        case .protect:
            if isProtected { return "This PDF is already password protected." }
            if password.isEmpty { return "Enter a password." }
            if confirmPassword.isEmpty { return "Confirm your password." }
            if !passwordsMatch { return "Passwords don't match." }
            return nil

        case .unlock:
            if !isProtected { return "This PDF is not password protected." }
            if unlockPassword.isEmpty { return "Enter the current password." }
            return nil
        }
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        // Reset unlock-specific state
        unlockError = nil

        // Check if the file is locked before full load
        let rawDoc = PDFDocument(url: url)
        let locked = rawDoc?.isLocked ?? false
        isProtected = locked

        if locked && mode == .unlock {
            // For unlock mode, store the URL but don't try to fully load yet
            inputURL = url
            document = rawDoc
            operationStatus = .idle
            let stem = url.deletingPathExtension().lastPathComponent
            outputSettings.filename = "\(stem)_unlocked"
            outputSettings.saveDirectory = url.deletingLastPathComponent()
            saveRecentFile(url: url)
            return
        }

        if locked && mode == .protect {
            // Can't protect an already-locked document without unlocking first
            isProtected = true
            inputURL = url
            document = rawDoc
            operationStatus = .idle
            let stem = url.deletingPathExtension().lastPathComponent
            outputSettings.filename = "\(stem)_protected"
            outputSettings.saveDirectory = url.deletingLastPathComponent()
            saveRecentFile(url: url)
            return
        }

        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            operationStatus = .idle

            let stem = url.deletingPathExtension().lastPathComponent
            let suffix = mode == .protect ? "_protected" : "_unlocked"
            outputSettings.filename = "\(stem)\(suffix)"
            outputSettings.saveDirectory = url.deletingLastPathComponent()

            // Check if already protected (has owner password / permissions set)
            // A document that loads without being locked may still have an owner password
            isProtected = locked

            saveRecentFile(url: url)
        } catch {
            operationStatus = .error(message: ErrorMapper.map(error), isRecoverable: true)
        }
    }

    // MARK: - Execute

    func execute() {
        guard canExecute, let outputURL, let inputURL else { return }
        let openAfter = outputSettings.openAfterOperation

        currentTask = Task {
            do {
                switch mode {
                case .protect:
                    operationStatus = .running(progress: -1, message: "Applying password protection\u{2026}")

                    let permissions = PDFPermissions(
                        allowPrinting: allowPrinting,
                        allowCopying: allowCopying
                    )

                    let result = try await ProtectService.protect(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        password: password,
                        permissions: permissions
                    )

                    operationStatus = .success(
                        message: "Password protection applied successfully.",
                        outputURL: result
                    )

                    if openAfter {
                        NSWorkspace.shared.openInPreview(url: result)
                    }

                case .unlock:
                    operationStatus = .running(progress: -1, message: "Removing password protection\u{2026}")
                    unlockError = nil

                    let result = try await ProtectService.unlock(
                        inputURL: inputURL,
                        outputURL: outputURL,
                        password: unlockPassword
                    )

                    operationStatus = .success(
                        message: "Password removed successfully.",
                        outputURL: result
                    )

                    if openAfter {
                        NSWorkspace.shared.openInPreview(url: result)
                    }
                }
            } catch let error as ProtectService.ProtectError {
                switch error {
                case .incorrectPassword:
                    unlockError = error.localizedDescription
                    operationStatus = .error(
                        message: error.localizedDescription,
                        isRecoverable: true
                    )
                default:
                    operationStatus = .error(
                        message: error.localizedDescription,
                        isRecoverable: true
                    )
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

    // MARK: - Recent Files

    private func saveRecentFile(url: URL) {
        RecentFilesService.addRecentFile(url: url, for: tool)
    }

    var outputURL: URL? {
        guard let inputURL else { return nil }
        let outputDir = outputSettings.saveDirectory ?? inputURL.deletingLastPathComponent()
        let baseFilename = outputSettings.filename.isEmpty
            ? inputURL.deletingPathExtension().lastPathComponent + (mode == .protect ? "_protected" : "_unlocked")
            : outputSettings.filename

        if URL(fileURLWithPath: baseFilename).pathExtension.isEmpty {
            return outputDir.appendingPathComponent(baseFilename).appendingPathExtension("pdf")
        }

        return outputDir.appendingPathComponent(baseFilename)
    }

    func outputFileExists() -> Bool {
        guard let url = outputURL else { return false }
        return FileService.destinationExists(url)
    }

    func executeWithCopyName() {
        guard let url = outputURL else { return }
        let copyURL = FileService.generateCopyName(for: url)
        outputSettings.filename = copyURL.lastPathComponent
        outputSettings.saveDirectory = copyURL.deletingLastPathComponent()
        execute()
    }
}
