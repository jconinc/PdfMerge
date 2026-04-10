import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct RotateView: View {
    @StateObject private var viewModel = RotateViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Rotate")
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
                    // Recent files when no file loaded
                    RecentFilesSection(tool: .rotate) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                } else {
                    // Loaded file name
                    if let inputURL = viewModel.inputURL {
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.secondary)
                            Text(inputURL.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(viewModel.pageCount) page\(viewModel.pageCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, AppConstants.sectionSpacing)
                    }

                    // Rotation buttons
                    rotationControls
                        .padding(.top, AppConstants.sectionSpacing)

                    // Selection badge
                    if !viewModel.selectedPages.isEmpty {
                        Text("\(viewModel.selectedPages.count) page\(viewModel.selectedPages.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }

                    // Page thumbnail grid
                    if let document = viewModel.document {
                        PageThumbnailGridView(
                            document: document,
                            selectedPages: $viewModel.selectedPages,
                            pendingRotations: viewModel.pendingRotations
                        )
                        .padding(.top, AppConstants.sectionSpacing)
                    }

                    // Output settings
                    OutputSettingsSection(
                        outputSettings: $viewModel.outputSettings,
                        defaultFilename: viewModel.inputURL?.toolOutputName(.rotate) ?? "",
                        defaultDirectory: viewModel.inputURL?.deletingLastPathComponent()
                    )
                    .padding(.top, AppConstants.sectionSpacing)

                    // Save button
                    ProgressActionButton(
                        label: "Save",
                        operationStatus: viewModel.operationStatus,
                        canExecute: viewModel.canExecute,
                        disabledReason: viewModel.disabledReason,
                        action: { viewModel.execute() },
                        onCancel: { viewModel.cancel() }
                    )
                    .padding(.top, AppConstants.actionButtonTopPadding)
                }

                // Status banner
                StatusBannerView(
                    operationStatus: $viewModel.operationStatus,
                    onShowInFinder: { url in
                        NSWorkspace.shared.showInFinder(url: url)
                    }
                )
            }
            .padding(AppConstants.panelPadding)
        }
        .confirmationDialog(
            "A file with this name already exists.",
            isPresented: $viewModel.showOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace") {
                viewModel.executeReplace()
            }
            Button("Save as Copy") {
                viewModel.executeSaveAsCopy()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to replace the existing file or save a copy?")
        }
    }

    // MARK: - Rotation Controls

    private var rotationControls: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.rotateLeft()
            } label: {
                Label("Left 90\u{00B0}", systemImage: "rotate.left")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedPages.isEmpty)
            .help("Rotate selected pages 90\u{00B0} counter-clockwise")

            Button {
                viewModel.rotateRight()
            } label: {
                Label("Right 90\u{00B0}", systemImage: "rotate.right")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedPages.isEmpty)
            .help("Rotate selected pages 90\u{00B0} clockwise")

            Button {
                viewModel.rotate180()
            } label: {
                Label("180\u{00B0}", systemImage: "arrow.uturn.down")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedPages.isEmpty)
            .help("Rotate selected pages 180\u{00B0}")

            Spacer()

            Button {
                viewModel.resetAll()
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.pendingRotations.isEmpty)
            .help("Remove all pending rotations")
        }
    }
}

// MARK: - Page Thumbnail Grid View

struct PageThumbnailGridView: View {
    let document: PDFDocument
    @Binding var selectedPages: Set<Int>
    let pendingRotations: [Int: Int]

    @State private var thumbnails: [Int: NSImage] = [:]

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<document.pageCount, id: \.self) { index in
                pageThumbnail(index: index)
            }
        }
        .task(id: ObjectIdentifier(document)) {
            await loadThumbnails()
        }
    }

    // MARK: - Single Page Thumbnail

    @ViewBuilder
    private func pageThumbnail(index: Int) -> some View {
        let isSelected = selectedPages.contains(index)
        let rotation = pendingRotations[index] ?? 0

        VStack(spacing: 4) {
            ZStack {
                if let image = thumbnails[index] {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(Double(rotation)))
                        .animation(
                            .easeInOut(duration: AppConstants.thumbnailSelectionDuration),
                            value: rotation
                        )
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
            .frame(
                width: AppConstants.gridThumbnailSize.width,
                height: AppConstants.gridThumbnailSize.height
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            }

            // Page label and rotation badge
            HStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if rotation != 0 {
                    Text("\(rotation)\u{00B0}")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue, in: Capsule())
                }
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(index)
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ index: Int) {
        if selectedPages.contains(index) {
            selectedPages.remove(index)
        } else {
            selectedPages.insert(index)
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnails() async {
        let loaded = await ThumbnailService.shared.generateThumbnails(
            for: document,
            size: AppConstants.gridThumbnailSize
        ) { _, _ in }

        thumbnails = loaded
    }
}
