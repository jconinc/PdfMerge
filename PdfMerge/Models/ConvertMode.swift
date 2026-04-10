import Foundation

enum ConvertMode: String, CaseIterable, Identifiable {
    case pdfToWord
    case pdfToExcel
    case pdfToImages
    case imagesToPDF

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdfToWord: "PDF to Word"
        case .pdfToExcel: "PDF to Excel"
        case .pdfToImages: "PDF to Images"
        case .imagesToPDF: "Images to PDF"
        }
    }
}
