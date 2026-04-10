import SwiftUI
import PDFKit

@MainActor
final class EditTextViewModel: ObservableObject {

    // MARK: - Published State

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var isEditMode: Bool = false
    @Published var pendingEdits: [TextEdit] = []
    @Published var hasUnsavedChanges: Bool = false
    @Published var showEditsList: Bool = true
    @Published var detectedFont: String?
    @Published var detectedFontSize: CGFloat?
    @Published var detectedTextColor: NSColor?
    @Published var fontWarning: String?

    let tool: Tool = .editText

    // MARK: - Undo Manager

    weak var undoManager: UndoManager?

    // MARK: - Computed

    var canSave: Bool {
        hasUnsavedChanges && document != nil && inputURL != nil && !pendingEdits.isEmpty
    }

    var editsByPage: [(pageIndex: Int, pageLabel: String, edits: [TextEdit])] {
        let grouped = Dictionary(grouping: pendingEdits) { $0.pageIndex }
        return grouped.keys.sorted().compactMap { pageIndex in
            let edits = grouped[pageIndex] ?? []
            return (pageIndex: pageIndex, pageLabel: "Page \(pageIndex + 1)", edits: edits)
        }
    }

    // MARK: - File Management

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            pendingEdits = []
            hasUnsavedChanges = false
            operationStatus = .idle
            isEditMode = false
            detectedFont = nil
            detectedFontSize = nil
            detectedTextColor = nil
            fontWarning = nil
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: false
            )
        }
    }

    func save(onComplete: (() -> Void)? = nil) {
        guard let doc = document,
              let url = inputURL,
              !pendingEdits.isEmpty,
              let documentData = doc.dataRepresentation() else { return }

        operationStatus = .running(progress: 0, message: "Flattening edits\u{2026}")

        let edits = pendingEdits
        Task.detached {
            do {
                guard let workingDocument = PDFDocument(data: documentData) else {
                    throw FileService.FileError.writeFailed(url)
                }
                try EditTextService.flattenEdits(edits, in: workingDocument, to: url)
                let reloaded = try PDFLoadService.loadDocument(from: url)
                await MainActor.run {
                    self.document = reloaded
                    self.pendingEdits = []
                    self.hasUnsavedChanges = false
                    self.operationStatus = .success(
                        message: "Saved edits to \(url.lastPathComponent)",
                        outputURL: url
                    )
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    self.operationStatus = .error(
                        message: ErrorMapper.map(error),
                        isRecoverable: true
                    )
                }
            }
        }
    }

    func saveAs() {
        guard let doc = document,
              !pendingEdits.isEmpty,
              let documentData = doc.dataRepresentation() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        if let inputURL {
            let stem = inputURL.deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(stem)_edited.pdf"
            panel.directoryURL = inputURL.deletingLastPathComponent()
        } else {
            panel.nameFieldStringValue = "edited.pdf"
        }

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        operationStatus = .running(progress: 0, message: "Flattening edits\u{2026}")

        let edits = pendingEdits
        Task.detached {
            do {
                guard let workingDocument = PDFDocument(data: documentData) else {
                    throw FileService.FileError.writeFailed(saveURL)
                }
                try EditTextService.flattenEdits(edits, in: workingDocument, to: saveURL)
                let reloaded = try PDFLoadService.loadDocument(from: saveURL)
                await MainActor.run {
                    self.document = reloaded
                    self.inputURL = saveURL
                    self.pendingEdits = []
                    self.hasUnsavedChanges = false
                    self.operationStatus = .success(
                        message: "Saved to \(saveURL.lastPathComponent)",
                        outputURL: saveURL
                    )
                    NSWorkspace.shared.openInPreview(url: saveURL)
                }
            } catch {
                await MainActor.run {
                    self.operationStatus = .error(
                        message: ErrorMapper.map(error),
                        isRecoverable: true
                    )
                }
            }
        }
    }

    // MARK: - Edit Management

    func addEdit(
        original: String,
        replacement: String,
        bounds: CGRect,
        pageIndex: Int,
        fontName: String,
        fontSize: CGFloat,
        textColor: NSColor,
        isFontApproximate: Bool
    ) {
        let edit = TextEdit(
            pageIndex: pageIndex,
            originalText: original,
            replacementText: replacement,
            bounds: bounds,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            isFontApproximate: isFontApproximate
        )

        pendingEdits.append(edit)
        hasUnsavedChanges = true

        undoManager?.registerUndo(withTarget: self) { target in
            target.removeEdit(edit)
        }
        undoManager?.setActionName("Edit Text")
    }

    func removeEdit(_ edit: TextEdit) {
        guard let index = pendingEdits.firstIndex(where: { $0.id == edit.id }) else { return }
        let removed = pendingEdits.remove(at: index)
        hasUnsavedChanges = !pendingEdits.isEmpty

        undoManager?.registerUndo(withTarget: self) { target in
            target.pendingEdits.insert(removed, at: min(index, target.pendingEdits.count))
            target.hasUnsavedChanges = true
        }
        undoManager?.setActionName("Remove Edit")
    }

    // MARK: - Font Detection Display

    func updateDetectedFont(from detected: EditTextService.DetectedText) {
        detectedFont = detected.fontName
        detectedFontSize = detected.fontSize
        detectedTextColor = detected.textColor
        fontWarning = detected.isFontApproximate ? "Font approximated" : nil
    }

    func clearDetectedFont() {
        detectedFont = nil
        detectedFontSize = nil
        detectedTextColor = nil
        fontWarning = nil
    }
}
