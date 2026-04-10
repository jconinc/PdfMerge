import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ExtractPagesView: View {
    @StateObject private var viewModel = ExtractPagesViewModel()
    @State private var showOverwriteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Extract Pages")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, AppConstants.headingBottomPadding)

                // Drop zone
                DropZoneView(
                    allowedTypes: [.pdf],
                    allowsMultiple: false
                ) { urls in
                    if let url = urls.first {
                        viewModel.loadFile(url: url)
                    }
                }
                .frame(height: AppConstants.singleFileDropHeight)

                if viewModel.document == nil {
                    // Recent files when no document loaded
                    RecentFilesSection(tool: .extractPages) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                } else {
                    documentLoadedContent
                }

                Spacer(minLength: 0)
            }
            .padding(AppConstants.panelPadding)
        }
        .overwriteConfirmation(
            isPresented: $showOverwriteAlert,
            existingURL: viewModel.outputURL,
            onReplace: { viewModel.execute() },
            onSaveAsCopy: { viewModel.executeWithCopyName() },
            onCancel: { }
        )
        .overlay(alignment: .bottom) {
            StatusBannerView(operationStatus: $viewModel.operationStatus) { url in
                NSWorkspace.shared.showInFinder(url: url)
            }
            .padding(AppConstants.panelPadding)
        }
    }

    // MARK: - Document Loaded Content

    @ViewBuilder
    private var documentLoadedContent: some View {
        // File info
        if let url = viewModel.inputURL {
            fileInfoRow(url: url)
                .padding(.top, AppConstants.sectionSpacing)
        }

        // Mode picker
        Picker("Selection Mode", selection: $viewModel.selectionMode) {
            ForEach(ExtractPagesViewModel.SelectionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.top, AppConstants.sectionSpacing)

        // Mode-specific content
        switch viewModel.selectionMode {
        case .visual:
            visualSelectionContent
                .padding(.top, AppConstants.sectionSpacing)
        case .range:
            rangeSelectionContent
                .padding(.top, AppConstants.sectionSpacing)
        }

        // Single vs multiple toggle
        Toggle(
            viewModel.asSinglePDF ? "Extract as single PDF" : "One PDF per page",
            isOn: $viewModel.asSinglePDF
        )
        .font(.callout)
        .padding(.top, AppConstants.sectionSpacing)

        // Output settings
        OutputSettingsSection(
            outputSettings: $viewModel.outputSettings,
            defaultFilename: viewModel.defaultFilename,
            defaultDirectory: viewModel.defaultDirectory
        )
        .padding(.top, AppConstants.sectionSpacing)

        // Action button
        ProgressActionButton(
            label: actionLabel,
            operationStatus: viewModel.operationStatus,
            canExecute: viewModel.canExecute,
            disabledReason: viewModel.disabledReason,
            action: {
                if viewModel.outputFileExists() {
                    showOverwriteAlert = true
                } else {
                    viewModel.execute()
                }
            },
            onCancel: { viewModel.cancel() }
        )
        .padding(.top, AppConstants.actionButtonTopPadding)
    }

    // MARK: - Visual Selection

    @ViewBuilder
    private var visualSelectionContent: some View {
        if let doc = viewModel.document {
            // Uses the local 1-based grid (not the shared 0-based PageThumbnailGridView)
            ExtractPageGrid(
                document: doc,
                selectedPages: $viewModel.selectedPages
            )

            if !viewModel.selectedPages.isEmpty {
                Text("\(viewModel.selectedPages.count) page\(viewModel.selectedPages.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Range Selection

    @ViewBuilder
    private var rangeSelectionContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("e.g. 1, 3-7, 12", text: $viewModel.rangeText)
                .textFieldStyle(.roundedBorder)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.rangeError != nil ? Color.red : Color.clear, lineWidth: 1)
                )

            if let doc = viewModel.document {
                Text("Enter page numbers from 1 to \(doc.pageCount).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.rangeError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if viewModel.selectedPageCount > 0, viewModel.rangeError == nil {
                Text("\(viewModel.selectedPageCount) page\(viewModel.selectedPageCount == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var actionLabel: String {
        let count = viewModel.selectedPageCount
        if count == 0 {
            return "Extract Pages"
        }
        return "Extract \(count) Page\(count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func fileInfoRow(url: URL) -> some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let doc = viewModel.document {
                Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(url.fileSizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
    }
}

// MARK: - Extract Page Grid (1-based page numbers)

/// A thumbnail grid that uses 1-based page numbers in selectedPages,
/// matching ExtractService and PageRangeParser conventions.
/// Not to be confused with the shared PageThumbnailGridView which uses 0-based indices.
struct ExtractPageGrid: View {
    let document: PDFDocument
    @Binding var selectedPages: Set<Int>

    @State private var thumbnails: [Int: NSImage] = [:]

    private let columns = [
        GridItem(.adaptive(minimum: AppConstants.gridThumbnailSize.width, maximum: AppConstants.gridThumbnailSize.width + 20), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<document.pageCount, id: \.self) { index in
                let pageNumber = index + 1
                let isSelected = selectedPages.contains(pageNumber)

                Button {
                    togglePage(pageNumber)
                } label: {
                    VStack(spacing: 4) {
                        thumbnailImage(for: index)
                            .frame(
                                width: AppConstants.gridThumbnailSize.width,
                                height: AppConstants.gridThumbnailSize.height
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        isSelected ? Color.accentColor : Color.clear,
                                        lineWidth: 2.5
                                    )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                        Text("\(pageNumber)")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1.0 : 0.7)
                .animation(.easeInOut(duration: AppConstants.thumbnailSelectionDuration), value: isSelected)
            }
        }
        .task(id: document.documentURL) {
            await loadThumbnails()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func thumbnailImage(for index: Int) -> some View {
        if let nsImage = thumbnails[index] {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    ProgressView()
                        .controlSize(.small)
                }
        }
    }

    private func togglePage(_ pageNumber: Int) {
        if selectedPages.contains(pageNumber) {
            selectedPages.remove(pageNumber)
        } else {
            selectedPages.insert(pageNumber)
        }
    }

    private func loadThumbnails() async {
        thumbnails = [:]
        let thumbs = await ThumbnailService.shared.generateThumbnails(
            for: document,
            size: AppConstants.gridThumbnailSize
        ) { _, _ in }
        thumbnails = thumbs
    }
}
