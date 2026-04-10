import SwiftUI
import PDFKit

// MARK: - Supporting Types

enum FieldType: String, CaseIterable {
    case textField
    case checkbox
    case radioButton
    case dropdown
    case signature

    var label: String {
        switch self {
        case .textField: "Text Field"
        case .checkbox: "Checkbox"
        case .radioButton: "Radio Button"
        case .dropdown: "Dropdown"
        case .signature: "Signature"
        }
    }

    var sfSymbol: String {
        switch self {
        case .textField: "character.cursor.ibeam"
        case .checkbox: "checkmark.square"
        case .radioButton: "circle.inset.filled"
        case .dropdown: "chevron.up.chevron.down"
        case .signature: "signature"
        }
    }

    init(annotation: PDFAnnotation) {
        // Only called for confirmed widget annotations
        if let widgetType = annotation.widgetFieldType {
            switch widgetType {
            case .button:
                self = .checkbox
            case .choice:
                self = .dropdown
            case .signature:
                self = .signature
            case .text:
                self = .textField
            @unknown default:
                self = .textField
            }
        } else {
            self = .textField
        }
    }
}

struct FormFieldInfo: Identifiable {
    let id: UUID = UUID()
    let annotation: PDFAnnotation
    let page: Int
    let fieldName: String
    let fieldType: FieldType
    var isFilled: Bool

    init(annotation: PDFAnnotation, page: Int) {
        self.annotation = annotation
        self.page = page
        self.fieldName = annotation.fieldName ?? "Unnamed Field"
        self.fieldType = FieldType(annotation: annotation)
        self.isFilled = FormFieldInfo.checkFilled(annotation: annotation)
    }

    private static func checkFilled(annotation: PDFAnnotation) -> Bool {
        guard let value = annotation.widgetStringValue else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - View Model

@MainActor
final class FillFormViewModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var formFields: [FormFieldInfo] = []
    @Published var hasUnsavedChanges: Bool = false
    @Published var showFieldsList: Bool = true
    @Published var isXFA: Bool = false
    @Published var hasFields: Bool = true
    @Published var outputSettings = OutputSettings(filename: "")

    let tool: Tool = .fillForm

    /// Grouped fields by page number for the side panel.
    var fieldsByPage: [(page: Int, fields: [FormFieldInfo])] {
        let grouped = Dictionary(grouping: formFields, by: \.page)
        return grouped.keys.sorted().map { page in
            (page: page, fields: grouped[page] ?? [])
        }
    }

    var canSave: Bool {
        hasUnsavedChanges && document != nil && !isXFA
    }

    var defaultFilename: String {
        guard let url = inputURL else { return "filled.pdf" }
        return url.deletingPathExtension().lastPathComponent + "_filled.pdf"
    }

    var defaultDirectory: URL? {
        inputURL?.deletingLastPathComponent()
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)

            // Detect XFA
            let xfa = PDFLoadService.isXFA(document: doc)
            if xfa {
                isXFA = true
                hasFields = false
                document = doc
                inputURL = url
                formFields = []
                outputSettings.filename = defaultFilename
                outputSettings.saveDirectory = defaultDirectory
                operationStatus = .idle
                return
            }

            isXFA = false
            document = doc
            inputURL = url

            // Scan form fields
            scanFormFields(in: doc)

            hasFields = !formFields.isEmpty

            outputSettings.filename = defaultFilename
            outputSettings.saveDirectory = defaultDirectory
            hasUnsavedChanges = false
            snapshotFieldValues()
            operationStatus = .idle
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: true
            )
        }
    }

    // MARK: - Field Scanning

    private func scanFormFields(in doc: PDFDocument) {
        var fields: [FormFieldInfo] = []
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                if annotation.type == "Widget" {
                    let info = FormFieldInfo(annotation: annotation, page: pageIndex)
                    fields.append(info)
                }
            }
        }
        formFields = fields
    }

    // MARK: - Refresh Fields

    func refreshFields() {
        for index in formFields.indices {
            let annotation = formFields[index].annotation
            let filled: Bool
            if let value = annotation.widgetStringValue {
                filled = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else {
                filled = false
            }
            formFields[index].isFilled = filled
        }
    }

    /// Called by the coordinator on annotation hit. Compares current field values
    /// against the snapshot taken at load time — only marks dirty if something
    /// actually changed, so clicking a field without editing doesn't trigger a
    /// save prompt.
    func markDirty() {
        refreshFields()
        if !hasUnsavedChanges {
            hasUnsavedChanges = currentFieldValues() != fieldValueSnapshot
        }
    }

    // MARK: - Field Value Snapshot

    private var fieldValueSnapshot: [String: String] = [:]

    private func snapshotFieldValues() {
        fieldValueSnapshot = currentFieldValues()
    }

    private func currentFieldValues() -> [String: String] {
        var values: [String: String] = [:]
        for field in formFields {
            let key = field.annotation.fieldName ?? field.id.uuidString
            values[key] = field.annotation.widgetStringValue ?? ""
        }
        return values
    }

    // MARK: - Save

    func save(flatten: Bool, onComplete: (() -> Void)? = nil) {
        guard let doc = document else { return }

        guard let outputURL = outputSettings.resolvedURL(
            defaultFilename: defaultFilename,
            defaultDirectory: defaultDirectory
        ) else { return }
        let openAfter = outputSettings.openAfterOperation

        operationStatus = .running(progress: -1, message: "Saving\u{2026}")

        Task {
            do {
                if flatten {
                    guard let data = doc.dataRepresentation(),
                          let flatDoc = PDFDocument(data: data) else {
                        throw FileService.FileError.writeFailed(outputURL)
                    }
                    for pageIndex in 0..<flatDoc.pageCount {
                        guard let page = flatDoc.page(at: pageIndex) else { continue }
                        let widgets = page.annotations.filter { $0.type == "Widget" }
                        for widget in widgets {
                            page.removeAnnotation(widget)
                        }
                    }
                    try FileService.atomicWrite(flatDoc, to: outputURL)
                } else {
                    try FileService.atomicWrite(doc, to: outputURL)
                }

                hasUnsavedChanges = false
                operationStatus = .success(
                    message: "Saved \(outputURL.lastPathComponent)",
                    outputURL: outputURL
                )

                if openAfter {
                    NSWorkspace.shared.openInPreview(url: outputURL)
                }

                onComplete?()
            } catch {
                operationStatus = .error(
                    message: ErrorMapper.map(error),
                    isRecoverable: true
                )
            }
        }
    }

    // MARK: - Clear All

    func clearAll() {
        guard let doc = document else { return }
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard annotation.type == "Widget" else { continue }
                annotation.widgetStringValue = ""
            }
        }
        hasUnsavedChanges = true
        refreshFields()
    }

    // MARK: - Overwrite Check

    var outputURL: URL? {
        outputSettings.resolvedURL(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func outputFileExists() -> Bool {
        outputSettings.outputExists(defaultFilename: defaultFilename, defaultDirectory: defaultDirectory)
    }

    func outputCopyURL() -> URL {
        guard let url = outputURL else {
            return FileManager.default.temporaryDirectory.appendingPathComponent(defaultFilename)
        }
        return FileService.generateCopyName(for: url)
    }

    // Change tracking is handled by the PDFViewerCoordinator callback
    // wired up in FillFormView.makeFillFormCoordinator(viewModel:).
}
