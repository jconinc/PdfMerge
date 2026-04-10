import Foundation

struct RecentFile: Codable, Identifiable {
    struct BookmarkResolution {
        let url: URL
        let isStale: Bool
    }

    let id: UUID
    let bookmarkData: Data
    let date: Date
    let toolID: String

    init(
        id: UUID = UUID(),
        bookmarkData: Data,
        date: Date = Date(),
        toolID: String
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.date = date
        self.toolID = toolID
    }

    var url: URL? {
        resolvedURL()
    }

    func resolvedURL() -> URL? {
        resolveBookmark()?.url
    }

    func resolveBookmark() -> BookmarkResolution? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return BookmarkResolution(url: url, isStale: isStale)
    }
}
