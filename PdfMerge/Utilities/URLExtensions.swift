import Foundation
import UniformTypeIdentifiers

extension URL {

    /// File size in bytes, or `nil` if the resource is unavailable.
    var fileSize: Int64? {
        guard let values = try? resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    /// Builds a tool-specific output filename, e.g. "contract_merged.pdf".
    func toolOutputName(_ tool: Tool) -> String {
        let base = deletingPathExtension().lastPathComponent
        let suffix = tool.label.lowercased().replacingOccurrences(of: " / ", with: "_").replacingOccurrences(of: " ", with: "_")
        return "\(base)_\(suffix).pdf"
    }

    /// Whether the containing directory is writable.
    var isWritableLocation: Bool {
        FileManager.default.isWritableFile(atPath: deletingLastPathComponent().path)
    }

    /// Human-readable file size string (e.g. "2.4 MB").
    var fileSizeFormatted: String {
        guard let bytes = fileSize else { return "Unknown size" }
        return FileSizeFormatter.format(bytes)
    }
}
