import Foundation
import AppKit

struct PDFFileItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var thumbnail: NSImage?
    var pageCount: Int
    var fileSize: Int64
    var isLocked: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        thumbnail: NSImage? = nil,
        pageCount: Int = 0,
        fileSize: Int64 = 0,
        isLocked: Bool = false
    ) {
        self.id = id
        self.url = url
        self.thumbnail = thumbnail
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.isLocked = isLocked
    }

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    static func == (lhs: PDFFileItem, rhs: PDFFileItem) -> Bool {
        lhs.id == rhs.id
            && lhs.url == rhs.url
            && lhs.pageCount == rhs.pageCount
            && lhs.fileSize == rhs.fileSize
            && lhs.isLocked == rhs.isLocked
    }
}
