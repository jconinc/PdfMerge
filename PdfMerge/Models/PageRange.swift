import Foundation

struct PageRange: Equatable {
    var start: Int
    var end: Int

    var count: Int {
        guard end >= start else { return 0 }
        return end - start + 1
    }

    func isValid(totalPages: Int) -> Bool {
        start >= 1 && end >= start && end <= totalPages
    }
}

struct PageRangeSet: Equatable {
    var ranges: [PageRange]

    init(ranges: [PageRange] = []) {
        self.ranges = ranges
    }

    func isValid(totalPages: Int) -> Bool {
        guard !ranges.isEmpty else { return false }
        return ranges.allSatisfy { $0.isValid(totalPages: totalPages) }
    }

    var totalPageCount: Int {
        ranges.reduce(0) { $0 + $1.count }
    }
}
