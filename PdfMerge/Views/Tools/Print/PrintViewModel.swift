import Foundation
import PDFKit
import AppKit

@MainActor
final class PrintViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var document: PDFDocument?
    @Published var inputURL: URL?
    @Published var operationStatus: OperationStatus = .idle

    let tool: Tool = .print

    // MARK: - Computed Properties

    var canExecute: Bool {
        document != nil
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var fileSizeFormatted: String {
        inputURL?.fileSizeFormatted ?? "Unknown"
    }

    // MARK: - File Loading

    func loadFile(url: URL) {
        do {
            let doc = try PDFLoadService.loadDocument(from: url)
            document = doc
            inputURL = url
            operationStatus = .idle
            saveRecentFile(url: url)
        } catch {
            operationStatus = .error(message: ErrorMapper.map(error), isRecoverable: true)
        }
    }

    // MARK: - Print

    func printDocument(from pdfView: NSView) {
        guard let document else { return }
        Task {
            await PrintService.print(document: document, from: pdfView)
        }
    }

    // MARK: - Recent Files

    private func saveRecentFile(url: URL) {
        RecentFilesService.addRecentFile(url: url, for: tool)
    }
}
