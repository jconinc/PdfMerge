import Foundation
import AppKit

struct TextEdit: Identifiable {
    let id: UUID
    let pageIndex: Int
    let originalText: String
    var replacementText: String
    let bounds: CGRect
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    let isFontApproximate: Bool

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        originalText: String,
        replacementText: String,
        bounds: CGRect,
        fontName: String,
        fontSize: CGFloat,
        textColor: NSColor,
        isFontApproximate: Bool
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.originalText = originalText
        self.replacementText = replacementText
        self.bounds = bounds
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.isFontApproximate = isFontApproximate
    }
}
