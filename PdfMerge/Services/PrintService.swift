import Foundation
import PDFKit
import AppKit

enum PrintService {

    // MARK: - Print

    /// Present the macOS print dialog for the given PDF document.
    /// - Parameters:
    ///   - document: The PDFDocument to print.
    ///   - pdfView: The NSView hosting the PDFView (used to anchor the print panel).
    @MainActor
    static func print(document: PDFDocument, from pdfView: NSView) async {
        // PDFView has a built-in print method, but we need to go through NSPrintOperation
        // to get proper print dialog behavior.

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        // If the view is a PDFView, use its built-in print support
        if let pdfKitView = pdfView as? PDFView {
            pdfKitView.print(with: printInfo, autoRotate: true)
            return
        }

        // Fallback: create a print operation from the PDF data
        guard let data = document.dataRepresentation() else { return }

        let pdfImageRep = NSPDFImageRep(data: data)
        guard let imageRep = pdfImageRep else { return }

        let image = NSImage()
        image.addRepresentation(imageRep)

        let imageView = NSImageView(image: image)
        imageView.frame = NSRect(
            x: 0, y: 0,
            width: imageRep.bounds.width,
            height: imageRep.bounds.height
        )

        let printOperation = NSPrintOperation(view: imageView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        printOperation.runModal(
            for: pdfView.window ?? NSApp.mainWindow ?? NSWindow(),
            delegate: nil,
            didRun: nil,
            contextInfo: nil
        )
    }
}
