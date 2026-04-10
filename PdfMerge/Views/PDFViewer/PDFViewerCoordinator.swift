import PDFKit
import AppKit
import SwiftUI

@MainActor
class PDFViewerCoordinator: NSObject {
    weak var pdfView: PDFView? {
        didSet {
            rebindNotifications()
            installClickHandler()
        }
    }
    var onAnnotationChanged: (() -> Void)?
    weak var annotateViewModel: AnnotateViewModel? {
        didSet { installClickHandler() }
    }

    private var clickMonitor: Any?

    // MARK: - Notifications

    private func rebindNotifications() {
        NotificationCenter.default.removeObserver(self, name: .PDFViewAnnotationHit, object: nil)
        guard let pdfView else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(annotationDidChange(_:)),
            name: .PDFViewAnnotationHit,
            object: pdfView
        )
    }

    @objc private func annotationDidChange(_ notification: Notification) {
        onAnnotationChanged?()
    }

    // MARK: - Annotation Click Handler

    private func installClickHandler() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        // Only install the click monitor when an annotate model is wired up.
        // Other tools (Print, EditText, FillForm) don't need global event monitoring.
        guard let pdfView, annotateViewModel != nil else { return }

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            // Extract what we need from NSEvent before crossing into MainActor,
            // since NSEvent is not Sendable.
            let windowPoint = event.locationInWindow
            let eventWindow = event.window

            guard let self else { return event }
            let handled = MainActor.assumeIsolated {
                self.handleClick(windowPoint: windowPoint, eventWindow: eventWindow, pdfView: pdfView)
            }
            return handled ? nil : event
        }
    }

    /// Returns true if the click was consumed (annotation placed).
    private func handleClick(windowPoint: NSPoint, eventWindow: NSWindow?, pdfView: PDFView) -> Bool {
        guard let viewModel = annotateViewModel,
              viewModel.selectedTool != .selectPan,
              eventWindow === pdfView.window else {
            return false
        }

        let viewPoint = pdfView.convert(windowPoint, from: nil)

        guard pdfView.bounds.contains(viewPoint),
              let page = pdfView.page(for: viewPoint, nearest: true) else {
            return false
        }

        let pagePoint = pdfView.convert(viewPoint, to: page)
        let annotation = createAnnotation(
            tool: viewModel.selectedTool,
            at: pagePoint,
            on: page,
            color: NSColor(viewModel.selectedColor),
            strokeWidth: viewModel.strokeWidth.points
        )

        if let annotation {
            viewModel.addAnnotation(annotation, to: page)
            return true
        }

        return false
    }

    private func createAnnotation(
        tool: AnnotationToolType,
        at point: CGPoint,
        on page: PDFPage,
        color: NSColor,
        strokeWidth: CGFloat
    ) -> PDFAnnotation? {
        switch tool {
        case .selectPan:
            return nil

        case .highlight, .underline, .strikethrough:
            // Text markup: find the line at the click point
            guard let selection = page.selectionForLine(at: point),
                  let selectionString = selection.string,
                  !selectionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let bounds = selection.bounds(for: page)
            let type: PDFAnnotationSubtype
            switch tool {
            case .highlight: type = .highlight
            case .underline: type = .underline
            case .strikethrough: type = .strikeOut
            default: return nil
            }
            let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            annotation.color = color
            return annotation

        case .textNote:
            let size = CGSize(width: 200, height: 50)
            let bounds = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            annotation.contents = "Text"
            annotation.font = NSFont.systemFont(ofSize: 14)
            annotation.fontColor = color
            annotation.color = .clear
            let border = PDFBorder()
            border.lineWidth = 0
            annotation.border = border
            return annotation

        case .popupNote:
            let bounds = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
            let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
            annotation.color = color
            annotation.contents = ""
            return annotation

        case .freehand:
            // Freehand needs drag tracking; place a small ink dot as a starting point
            let bounds = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
            let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
            annotation.color = color
            let border = PDFBorder()
            border.lineWidth = strokeWidth
            annotation.border = border
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 2, y: 2))
            path.line(to: CGPoint(x: 2, y: 2))
            annotation.add(path)
            return annotation

        case .arrow:
            let length: CGFloat = 100
            let bounds = CGRect(x: point.x, y: point.y - 1, width: length, height: 2)
            let annotation = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            annotation.color = color
            annotation.startPoint = CGPoint(x: 0, y: 1)
            annotation.endPoint = CGPoint(x: length, y: 1)
            annotation.endLineStyle = .openArrow
            let border = PDFBorder()
            border.lineWidth = strokeWidth
            annotation.border = border
            return annotation

        case .rectangle:
            let size = CGSize(width: 120, height: 80)
            let bounds = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
            annotation.color = color
            let border = PDFBorder()
            border.lineWidth = strokeWidth
            annotation.border = border
            return annotation

        case .circle:
            let size = CGSize(width: 100, height: 100)
            let bounds = CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            let annotation = PDFAnnotation(bounds: bounds, forType: .circle, withProperties: nil)
            annotation.color = color
            let border = PDFBorder()
            border.lineWidth = strokeWidth
            annotation.border = border
            return annotation
        }
    }

    // MARK: - Navigation

    func scrollToPage(_ pageIndex: Int) {
        guard let document = pdfView?.document,
              let page = document.page(at: pageIndex) else { return }
        pdfView?.go(to: page)
    }

    func scrollToAnnotation(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        pdfView?.go(to: annotation.bounds, on: page)
    }

    deinit {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
