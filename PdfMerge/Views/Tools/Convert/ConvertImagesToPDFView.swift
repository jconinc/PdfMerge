import SwiftUI
import UniformTypeIdentifiers

struct ConvertImagesToPDFView: View {
    @ObservedObject var viewModel: ConvertViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.sectionSpacing) {
            // Multi-file drop zone for images
            DropZoneView(
                allowedTypes: [.jpeg, .png, .tiff, .heic, .bmp],
                allowsMultiple: true
            ) { urls in
                viewModel.addImages(urls)
            }
            .frame(height: AppConstants.multiFileDropHeight)

            if viewModel.imageFiles.isEmpty {
                VStack(spacing: 6) {
                    Text("Add one or more images to combine into a single PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, AppConstants.sectionSpacing)
            } else {
                // Reorderable image file list
                ReorderableFileListView(
                    files: $viewModel.imageFiles,
                    onRemove: { item in
                        viewModel.removeImage(item)
                    },
                    onUnlock: { _, _ in
                        // Images are never locked
                        false
                    },
                    onClearAll: {
                        viewModel.clearAll()
                    },
                    onAddMore: {
                        openAddMorePanel()
                    }
                )
                .padding(.top, AppConstants.sectionSpacing)

                // Page size picker
                GroupBox("Page Size") {
                    Picker("Page Size", selection: $viewModel.pageSize) {
                        ForEach(ConvertService.PageSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Add More Panel

    private func openAddMorePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic, .bmp]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        viewModel.addImages(panel.urls)
    }
}
