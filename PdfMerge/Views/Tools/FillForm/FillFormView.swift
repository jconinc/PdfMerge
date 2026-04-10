import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct FillFormView: View {
    @StateObject private var viewModel = FillFormViewModel()
    @State private var pdfViewCoordinator: PDFViewerCoordinator?
    @State private var showOverwriteConfirm = false
    @State private var showFlattenConfirmation = false
    @State private var showUnsavedAlert = false
    @State private var pendingURL: URL?
    @State private var pendingFlatten = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.document != nil {
                documentContent
            } else {
                emptyState
            }
        }
        .overlay(alignment: .bottom) {
            StatusBannerView(
                operationStatus: $viewModel.operationStatus,
                onShowInFinder: { url in
                    NSWorkspace.shared.showInFinder(url: url)
                }
            )
            .padding()
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                let nextURL = pendingURL
                pendingURL = nil
                viewModel.save(flatten: false) {
                    if let nextURL {
                        viewModel.loadFile(url: nextURL)
                    }
                }
            }
            Button("Don\u{2019}t Save", role: .destructive) {
                viewModel.hasUnsavedChanges = false
                if let url = pendingURL {
                    viewModel.loadFile(url: url)
                    pendingURL = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingURL = nil
            }
        } message: {
            Text("You have unsaved form changes. Save before switching?")
        }
        .overwriteConfirmation(
            isPresented: $showOverwriteConfirm,
            existingURL: overwriteURL,
            onReplace: {
                viewModel.save(flatten: pendingFlatten)
            },
            onSaveAsCopy: {
                let copyURL = viewModel.outputCopyURL()
                viewModel.outputSettings.filename = copyURL.lastPathComponent
                viewModel.outputSettings.saveDirectory = copyURL.deletingLastPathComponent()
                viewModel.save(flatten: pendingFlatten)
            },
            onCancel: {
                pendingFlatten = false
            }
        )
        .confirmationDialog(
            "Save Options",
            isPresented: $showFlattenConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep fields editable") {
                attemptSave(flatten: false)
            }
            Button("Flatten (lock values in place)") {
                attemptSave(flatten: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How would you like to save the filled form?")
        }
    }

    // MARK: - Overwrite URL

    private var overwriteURL: URL? {
        let dir = viewModel.outputSettings.saveDirectory ?? viewModel.inputURL?.deletingLastPathComponent()
        guard let dir else { return nil }
        let filename = viewModel.outputSettings.filename.isEmpty
            ? viewModel.defaultFilename
            : viewModel.outputSettings.filename
        return dir.appendingPathComponent(filename)
    }

    // MARK: - Empty State (Drop Zone)

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: AppConstants.sectionSpacing) {
            Spacer()

            DropZoneView(
                allowedTypes: [.pdf],
                allowsMultiple: false,
                onDrop: { urls in
                    guard let url = urls.first else { return }
                    viewModel.loadFile(url: url)
                }
            )
            .frame(height: AppConstants.singleFileDropHeight)
            .padding(.horizontal, AppConstants.panelPadding)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Document Content

    @ViewBuilder
    private var documentContent: some View {
        // Top bar
        topBar

        // Banners
        if viewModel.isXFA {
            InlineBannerView(
                message: "This PDF uses XFA forms, which aren\u{2019}t supported. Open it in Adobe Acrobat instead.",
                style: .warning
            )
            .padding(.horizontal, AppConstants.panelPadding)
            .padding(.top, 8)
        } else if !viewModel.hasFields {
            InlineBannerView(
                message: "This PDF doesn\u{2019}t contain any fillable form fields.",
                style: .info
            )
            .padding(.horizontal, AppConstants.panelPadding)
            .padding(.top, 8)
        }

        // Main content area
        HStack(spacing: 0) {
            if viewModel.showFieldsList && viewModel.hasFields && !viewModel.isXFA {
                FieldsListPanel(
                    fieldsByPage: viewModel.fieldsByPage,
                    onFieldSelected: { field in
                        pdfViewCoordinator?.scrollToAnnotation(field.annotation)
                    }
                )

                Divider()
            }

            PDFViewerRepresentable(
                document: viewModel.document,
                isInteractive: true,
                onViewCreated: { _, coordinator in
                    coordinator.onAnnotationChanged = { [weak viewModel] in
                        Task { @MainActor in
                            viewModel?.markDirty()
                        }
                    }
                    pdfViewCoordinator = coordinator
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 12) {
            // File info
            if let url = viewModel.inputURL {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Toggle fields list
            if viewModel.hasFields && !viewModel.isXFA {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showFieldsList.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(viewModel.showFieldsList ? "Hide fields list" : "Show fields list")
            }

            // Clear All
            Button("Clear All") {
                viewModel.clearAll()
            }
            .disabled(viewModel.isXFA || !viewModel.hasFields)

            // Save button
            Button("Save\u{2026}") {
                showFlattenConfirmation = true
            }
            .disabled(!viewModel.canSave)
            .keyboardShortcut("s", modifiers: .command)

            // Load new file
            Button {
                openFilePanel()
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .help("Open another PDF")
        }
        .padding(.horizontal, AppConstants.panelPadding)
        .padding(.vertical, 8)
        .background(.bar)

        Divider()
    }

    // MARK: - Save Logic

    private func attemptSave(flatten: Bool) {
        pendingFlatten = flatten
        if viewModel.outputFileExists() {
            showOverwriteConfirm = true
        } else {
            viewModel.save(flatten: flatten)
        }
    }

    // MARK: - File Panel

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if viewModel.hasUnsavedChanges {
            pendingURL = url
            showUnsavedAlert = true
        } else {
            viewModel.loadFile(url: url)
        }
    }
}

// Change tracking is wired via onViewCreated → coordinator.onAnnotationChanged.
