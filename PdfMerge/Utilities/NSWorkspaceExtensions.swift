import AppKit

extension NSWorkspace {

    /// Opens the file at `url` in Preview.app.
    func openInPreview(url: URL) {
        let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
        let configuration = NSWorkspace.OpenConfiguration()
        open([url], withApplicationAt: previewURL, configuration: configuration)
    }

    /// Reveals the file at `url` in Finder with the item selected.
    func showInFinder(url: URL) {
        activateFileViewerSelecting([url])
    }
}
