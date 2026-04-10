import Foundation

enum FileSizeFormatter {

    /// Formats a byte count into a human-readable string (e.g. "2.4 MB").
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Convenience overload accepting `Int`.
    static func format(_ bytes: Int) -> String {
        format(Int64(bytes))
    }
}
