import SwiftUI

struct SplitByRangeView: View {
    @ObservedObject var viewModel: SplitViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Page Ranges")
                .font(.headline)

            if viewModel.ranges.isEmpty {
                Text("No ranges defined. Add a range to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(viewModel.ranges.enumerated()), id: \.offset) { index, _ in
                    rangeRow(at: index)
                }
            }

            Button {
                addRange()
            } label: {
                Label("Add Range", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Range Row

    @ViewBuilder
    private func rangeRow(at index: Int) -> some View {
        let isOverlapping = viewModel.overlappingRangeIndices.contains(index)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Start page
                HStack(spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(
                        "1",
                        value: Binding(
                            get: { viewModel.ranges[index].0.start },
                            set: { viewModel.ranges[index].0.start = $0 }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }

                // End page
                HStack(spacing: 4) {
                    Text("to")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(
                        "\(viewModel.pageCount)",
                        value: Binding(
                            get: { viewModel.ranges[index].0.end },
                            set: { viewModel.ranges[index].0.end = $0 }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                }

                // Page count badge
                let range = viewModel.ranges[index].0
                if range.end >= range.start {
                    Text("\(range.count) pg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()

                // Remove button
                Button {
                    removeRange(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this range")
            }

            // Output filename
            HStack(spacing: 4) {
                Text("Save as")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "filename.pdf",
                    text: Binding(
                        get: { viewModel.ranges[index].1 },
                        set: { viewModel.ranges[index].1 = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            }

            // Overlap error
            if isOverlapping {
                Text("This range overlaps with another range.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isOverlapping ? Color.red.opacity(0.08) : Color.clear)
        }
        .overlay {
            if isOverlapping {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.red.opacity(0.4), lineWidth: 1)
            }
        }
    }

    // MARK: - Actions

    private func addRange() {
        let total = viewModel.pageCount
        let stem = viewModel.inputURL?.deletingPathExtension().lastPathComponent ?? "output"
        let partNumber = viewModel.ranges.count + 1
        let filename = "\(stem)_part\(partNumber).pdf"

        // Default new range: starts after the last range's end, or page 1
        let startPage: Int
        if let lastRange = viewModel.ranges.last {
            startPage = min(lastRange.0.end + 1, total)
        } else {
            startPage = 1
        }

        let range = PageRange(start: startPage, end: total)
        viewModel.ranges.append((range, filename))
    }

    private func removeRange(at index: Int) {
        guard index < viewModel.ranges.count else { return }
        viewModel.ranges.remove(at: index)
    }
}
