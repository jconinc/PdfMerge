import SwiftUI
import PDFKit

/// Shared thumbnail grid using 0-based page indices in `selectedPages`,
/// matching `PDFDocument.page(at:)` convention. Used by RotateView.
struct PageThumbnailGridView: View {
    let document: PDFDocument
    @Binding var selectedPages: Set<Int>

    private let columns = [
        GridItem(.adaptive(minimum: AppConstants.gridThumbnailSize.width), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("\(selectedPages.count) of \(document.pageCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedPages.removeAll()
                    } else {
                        selectedPages = Set(0..<document.pageCount)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            // Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        PageThumbnailCell(
                            document: document,
                            pageIndex: index,
                            isSelected: selectedPages.contains(index),
                            onTap: { modifiers in
                                handleTap(index: index, modifiers: modifiers)
                            }
                        )
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Computed

    private var allSelected: Bool {
        selectedPages.count == document.pageCount
    }

    // MARK: - Selection

    private func handleTap(index: Int, modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            // Cmd+click: toggle
            if selectedPages.contains(index) {
                selectedPages.remove(index)
            } else {
                selectedPages.insert(index)
            }
        } else {
            // Plain click: exclusive select
            selectedPages = [index]
        }
    }
}

// MARK: - Single Thumbnail Cell

private struct PageThumbnailCell: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
    let onTap: (EventModifiers) -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(
                        width: AppConstants.gridThumbnailSize.width,
                        height: AppConstants.gridThumbnailSize.height
                    )

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: AppConstants.gridThumbnailSize.width,
                            height: AppConstants.gridThumbnailSize.height
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .transition(.opacity)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .animation(
                            .easeInOut(duration: AppConstants.thumbnailSelectionDuration),
                            value: isSelected
                        )
                }
            }

            Text("Page \(pageIndex + 1)")
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Plain click
            onTap([])
        }
        .simultaneousGesture(
            TapGesture().modifiers(.command).onEnded {
                onTap(.command)
            }
        )
        .task {
            guard thumbnail == nil,
                  let page = document.page(at: pageIndex) else { return }
            let image = await ThumbnailService.shared.generateThumbnail(
                for: page,
                size: AppConstants.gridThumbnailSize
            )
            withAnimation(.easeIn(duration: AppConstants.thumbnailFadeInDuration)) {
                thumbnail = image
            }
        }
    }
}
