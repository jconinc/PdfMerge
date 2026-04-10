import Foundation

enum PageRangeParser {

    /// Parses a human-readable page range string like `"1, 3-7, 12"` into sorted `PageRange` values.
    ///
    /// - Parameters:
    ///   - input: Comma-separated page numbers and ranges (e.g. `"1, 3-7, 12"`).
    ///   - totalPages: The total number of pages in the document (used for validation).
    /// - Returns: A sorted array of validated, non-overlapping `PageRange` values.
    /// - Throws: `PDFToolError.invalidPageRange` when the input is malformed or out of bounds.
    static func parse(_ input: String, totalPages: Int) throws -> [PageRange] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PDFToolError.invalidPageRange("The page range is empty.")
        }

        let segments = trimmed.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        var ranges: [PageRange] = []

        for segment in segments {
            if segment.contains("-") {
                let parts = segment.split(separator: "-", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2,
                      let start = Int(parts[0]),
                      let end = Int(parts[1]) else {
                    throw PDFToolError.invalidPageRange("\"\(segment)\" is not a valid range.")
                }
                guard start <= end else {
                    throw PDFToolError.invalidPageRange("Start page \(start) is after end page \(end).")
                }
                ranges.append(PageRange(start: start, end: end))
            } else {
                guard let page = Int(segment) else {
                    throw PDFToolError.invalidPageRange("\"\(segment)\" is not a valid page number.")
                }
                ranges.append(PageRange(start: page, end: page))
            }
        }

        // Sort by start page.
        ranges.sort { $0.start < $1.start }

        // Validate bounds.
        for range in ranges {
            if range.start < 1 {
                throw PDFToolError.invalidPageRange("Page \(range.start) is less than 1.")
            }
            if range.end > totalPages {
                throw PDFToolError.invalidPageRange("Page \(range.end) exceeds the document's \(totalPages) pages.")
            }
        }

        // Check for overlaps.
        for i in 1..<ranges.count {
            if ranges[i].start <= ranges[i - 1].end {
                throw PDFToolError.invalidPageRange("Ranges overlap near page \(ranges[i].start).")
            }
        }

        return ranges
    }
}
