import Foundation
import PDFKit
import AppKit

actor ThumbnailService {

    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // ~50 MB
    }

    // MARK: - Single Thumbnail

    /// Generate (or retrieve from cache) a thumbnail for a single PDFPage.
    func generateThumbnail(for page: PDFPage, size: CGSize) async -> NSImage? {
        let cacheKey = thumbnailCacheKey(for: page, size: size)

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let thumbnail = page.thumbnail(of: size, for: .cropBox)
        cache.setObject(thumbnail, forKey: cacheKey, cost: thumbnailCacheCost(for: thumbnail))
        return thumbnail
    }

    // MARK: - Batch Thumbnails

    /// Generate thumbnails for all pages in a document, reporting progress.
    func generateThumbnails(
        for document: PDFDocument,
        size: CGSize,
        progress: @Sendable (Int, Int) -> Void
    ) async -> [Int: NSImage] {
        let totalPages = document.pageCount
        var results: [Int: NSImage] = [:]
        results.reserveCapacity(totalPages)

        for i in 0..<totalPages {
            guard let page = document.page(at: i) else { continue }

            if let image = await generateThumbnail(for: page, size: size) {
                results[i] = image
            }

            progress(i + 1, totalPages)
        }

        return results
    }

    // MARK: - Cache Management

    /// Clear all cached thumbnails.
    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func thumbnailCacheKey(for page: PDFPage, size: CGSize) -> NSString {
        // Use the page's document URL + page index + size as a stable key
        let doc = page.document
        let pageIndex = doc?.index(for: page) ?? 0
        let urlString = doc?.documentURL?.absoluteString ?? "unknown"
        return "\(urlString)_p\(pageIndex)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func thumbnailCacheCost(for image: NSImage) -> Int {
        if let bitmapRep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return bitmapRep.bytesPerRow * bitmapRep.pixelsHigh
        }

        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        return width * height * 4
    }
}
