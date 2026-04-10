import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class AnnotateViewModel: ObservableObject {

    // MARK: - Published State

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle
    @Published var selectedTool: AnnotationToolType = .selectPan
    @Published var selectedColor: Color = .yellow
    @Published var strokeWidth: StrokeWeight = .medium
    @Published var annotations: [PDFAnnotation] = []
    @Published var hasUnsavedChanges: Bool = false
    @Published var showAnnotationsList: Bool = true

    let tool: Tool = .annotate

    // MARK: - Persisted Preferences

    @AppStorage("annotateSelectedColor") private var persistedColorHex: String = "FFFF00"
    @AppStorage("annotateStrokeWidth") private var persistedStrokeWidth: String = StrokeWeight.medium.rawValue

    // MARK: - Undo Manager

    /// Set by the view to wire up the window's UndoManager.
    weak var undoManager: UndoManager?

    // MARK: - Stroke Weight

    enum StrokeWeight: String, CaseIterable, Identifiable {
        case thin
        case medium
        case thick

        var id: String { rawValue }

        var points: CGFloat {
            switch self {
            case .thin: 1
            case .medium: 2
            case .thick: 4
            }
        }

        var label: String {
            switch self {
            case .thin: "Thin"
            case .medium: "Medium"
            case .thick: "Thick"
            }
        }
    }

    // MARK: - Initialization

    init() {
        // Restore persisted stroke width
        if let restored = StrokeWeight(rawValue: persistedStrokeWidth) {
            strokeWidth = restored
        }
        // Restore persisted color
        selectedColor = Color(hex: persistedColorHex) ?? .yellow
    }

    // MARK: - Computed

    var canSave: Bool {
        hasUnsavedChanges && document != nil && inputURL != nil
    }

    var annotationsByPage: [(pageIndex: Int, pageLabel: String, annotations: [PDFAnnotation])] {
        guard let doc = document else { return [] }
        var result: [(pageIndex: Int, pageLabel: String, annotations: [PDFAnnotation])] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let pageAnnotations = page.annotations.filter { !isWidgetAnnotation($0) }
            if !pageAnnotations.isEmpty {
                result.append((pageIndex: i, pageLabel: "Page \(i + 1)", annotations: pageAnnotations))
            }
        }
        return result
    }

    // MARK: - File Management

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            hasUnsavedChanges = false
            operationStatus = .idle
            refreshAnnotationsList()
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: false
            )
        }
    }

    func save() {
        guard let doc = document, let url = inputURL else { return }

        operationStatus = .running(progress: 0, message: "Saving\u{2026}")

        do {
            try FileService.atomicWrite(doc, to: url)
            hasUnsavedChanges = false
            operationStatus = .success(
                message: "Saved annotations to \(url.lastPathComponent)",
                outputURL: url
            )
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: true
            )
        }
    }

    func saveAs() {
        guard let doc = document else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true

        if let inputURL {
            let stem = inputURL.deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(stem)_annotated.pdf"
            panel.directoryURL = inputURL.deletingLastPathComponent()
        } else {
            panel.nameFieldStringValue = "annotated.pdf"
        }

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        operationStatus = .running(progress: 0, message: "Saving\u{2026}")

        do {
            try FileService.atomicWrite(doc, to: saveURL)
            inputURL = saveURL
            hasUnsavedChanges = false
            operationStatus = .success(
                message: "Saved to \(saveURL.lastPathComponent)",
                outputURL: saveURL
            )
            NSWorkspace.shared.openInPreview(url: saveURL)
        } catch {
            operationStatus = .error(
                message: ErrorMapper.map(error),
                isRecoverable: true
            )
        }
    }

    // MARK: - Annotation Management

    func addAnnotation(_ annotation: PDFAnnotation, to page: PDFPage) {
        page.addAnnotation(annotation)
        hasUnsavedChanges = true
        refreshAnnotationsList()

        // Register undo
        undoManager?.registerUndo(withTarget: self) { target in
            target.removeAnnotation(annotation, from: page)
        }
        undoManager?.setActionName("Add \(annotationLabel(for: annotation))")
    }

    func removeAnnotation(_ annotation: PDFAnnotation, from page: PDFPage) {
        page.removeAnnotation(annotation)
        hasUnsavedChanges = true
        refreshAnnotationsList()

        // Register undo
        undoManager?.registerUndo(withTarget: self) { target in
            target.addAnnotation(annotation, to: page)
        }
        undoManager?.setActionName("Remove \(annotationLabel(for: annotation))")
    }

    func removeAnnotation(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        removeAnnotation(annotation, from: page)
    }

    func refreshAnnotationsList() {
        guard let doc = document else {
            annotations = []
            return
        }
        var allAnnotations: [PDFAnnotation] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let pageAnnotations = page.annotations.filter { !isWidgetAnnotation($0) }
            allAnnotations.append(contentsOf: pageAnnotations)
        }
        annotations = allAnnotations
    }

    // MARK: - Preference Persistence

    func persistColor() {
        persistedColorHex = selectedColor.hexString ?? "FFFF00"
    }

    func persistStrokeWidth() {
        persistedStrokeWidth = strokeWidth.rawValue
    }

    // MARK: - Helpers

    private func isWidgetAnnotation(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == "Widget"
    }

    func annotationLabel(for annotation: PDFAnnotation) -> String {
        switch annotation.type {
        case "Highlight": return "Highlight"
        case "Underline": return "Underline"
        case "StrikeOut": return "Strikethrough"
        case "Ink": return "Freehand"
        case "FreeText": return "Text Note"
        case "Text": return "Popup Note"
        case "Line": return "Arrow"
        case "Square": return "Rectangle"
        case "Circle": return "Circle"
        default: return annotation.type ?? "Annotation"
        }
    }

    func annotationIcon(for annotation: PDFAnnotation) -> String {
        switch annotation.type {
        case "Highlight": return "highlighter"
        case "Underline": return "underline"
        case "StrikeOut": return "strikethrough"
        case "Ink": return "scribble"
        case "FreeText": return "text.cursor"
        case "Text": return "note.text"
        case "Line": return "arrow.up.right"
        case "Square": return "rectangle"
        case "Circle": return "circle"
        default: return "pencil"
        }
    }

    func annotationPreviewText(for annotation: PDFAnnotation) -> String {
        if let contents = annotation.contents, !contents.isEmpty {
            return contents
        }
        return annotationLabel(for: annotation)
    }
}

// MARK: - Color Hex Conversion

private extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    var hexString: String? {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
