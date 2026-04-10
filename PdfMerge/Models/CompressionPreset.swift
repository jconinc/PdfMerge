import Foundation

enum CompressionPreset: String, CaseIterable, Identifiable {
    case screen
    case ebook
    case printer
    case prepress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screen: "Screen"
        case .ebook: "eBook"
        case .printer: "Printer"
        case .prepress: "Prepress"
        }
    }

    var dpi: Int {
        switch self {
        case .screen: 72
        case .ebook: 150
        case .printer: 300
        case .prepress: 300
        }
    }

    var description: String {
        switch self {
        case .screen: "Smallest file size (72 dpi). Best for on-screen viewing."
        case .ebook: "Medium file size (150 dpi). Good for email and eBooks."
        case .printer: "High quality (300 dpi). Suitable for desktop printing."
        case .prepress: "Maximum quality (300 dpi). Preserves color for professional printing."
        }
    }

    static var defaultPreset: CompressionPreset { .printer }
}
