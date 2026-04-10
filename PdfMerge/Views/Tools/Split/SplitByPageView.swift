import SwiftUI
import PDFKit
import AppKit

struct SplitByPageView: View {
    @ObservedObject var viewModel: SplitViewModel

    @State private var thumbnails: [Int: NSImage] = [:]
    @State private var isLoadingThumbnails = false

    private let columns = [
        GridItem(.adaptive(minimum: AppConstants.gridThumbnailSize.width + 16), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with count badge
            HStack {
                Text("Select Pages")
                    .font(.headline)

                Spacer()

                if !viewModel.selectedPages.isEmpty {
                    Text("\(viewModel.selectedPages.count) page\(viewModel.selectedPages.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }

            // Select/Deselect all
            HStack(spacing: 12) {
                Button("Select All") {
                    let allPages = Set(1...viewModel.pageCount)
                    viewModel.selectedPages = allPages
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.pageCount == 0)

                Button("Deselect All") {
                    viewModel.selectedPages.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.selectedPages.isEmpty)
            }

            // Extraction mode toggle
            Toggle(
                viewModel.combineSinglePDF
                    ? "Extract as single PDF"
                    : "One PDF per page",
                isOn: $viewModel.combineSinglePDF
            )
            .font(.callout)

            // Thumbnail grid
            if isLoadingThumbnails {
                ProgressView("Loading thumbnails\u{2026}")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(1...max(viewModel.pageCount, 1), id: \.self) { pageNumber in
                            pageThumbnailCell(pageNumber: pageNumber)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 400)
            }
        }
        .task(id: viewModel.document?.documentURL) {
            await loadThumbnails()
        }
    }

    // MARK: - Page Thumbnail Cell

    @ViewBuilder
    private func pageThumbnailCell(pageNumber: Int) -> some View {
        let isSelected = viewModel.selectedPages.contains(pageNumber)

        Button {
            togglePage(pageNumber)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Thumbnail image
                    Group {
                        if let image = thumbnails[pageNumber - 1] {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "doc")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(
                        width: AppConstants.gridThumbnailSize.width,
                        height: AppConstants.gridThumbnailSize.height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Selection overlay
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.accentColor, lineWidth: 2.5)
                            .frame(
                                width: AppConstants.gridThumbnailSize.width,
                                height: AppConstants.gridThumbnailSize.height
                            )

                        // Checkmark badge
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white, .accentColor)
                                    .padding(4)
                            }
                            Spacer()
                        }
                        .frame(
                            width: AppConstants.gridThumbnailSize.width,
                            height: AppConstants.gridThumbnailSize.height
                        )
                    }
                }

                // Page label
                Text("\(pageNumber)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: AppConstants.thumbnailSelectionDuration), value: isSelected)
    }

    // MARK: - Actions

    private func togglePage(_ pageNumber: Int) {
        if viewModel.selectedPages.contains(pageNumber) {
            viewModel.selectedPages.remove(pageNumber)
        } else {
            viewModel.selectedPages.insert(pageNumber)
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnails() async {
        guard let document = viewModel.document, document.pageCount > 0 else {
            thumbnails = [:]
            return
        }

        isLoadingThumbnails = true
        let loaded = await ThumbnailService.shared.generateThumbnails(
            for: document,
            size: AppConstants.gridThumbnailSize,
            progress: { _, _ in }
        )
        thumbnails = loaded
        isLoadingThumbnails = false
    }
}
