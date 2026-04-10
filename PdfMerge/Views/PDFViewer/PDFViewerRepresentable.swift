import SwiftUI
import PDFKit

struct PDFViewerRepresentable: NSViewRepresentable {
    let document: PDFDocument?
    var isInteractive: Bool = true
    var allowsAnnotationEditing: Bool = false
    var autoScales: Bool = true
    var displayMode: PDFDisplayMode = .singlePageContinuous
    var onViewCreated: ((PDFView, PDFViewerCoordinator) -> Void)? = nil

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = displayMode
        pdfView.autoScales = autoScales
        pdfView.document = document

        context.coordinator.pdfView = pdfView
        onViewCreated?(pdfView, context.coordinator)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.autoScales = autoScales
        if pdfView.displayMode != displayMode {
            pdfView.displayMode = displayMode
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: Coordinator) {
        // CRITICAL: Memory cleanup (Patch 10)
        pdfView.document = nil
        coordinator.pdfView = nil
        pdfView.removeFromSuperview()
    }

    func makeCoordinator() -> PDFViewerCoordinator {
        PDFViewerCoordinator()
    }
}
