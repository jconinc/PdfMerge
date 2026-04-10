import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct EditTextView: View {
    @StateObject private var viewModel = EditTextViewModel()
    @Environment(\.undoManager) private var undoManager
    @State private var showUnsavedChangesAlert = false
    @State private var pendingSwitchURL: URL?
    @State private var pdfView: PDFView?
    @State private var showFloatingEditBar = false
    @State private var floatingEditBarPosition: CGPoint = .zero
    @State private var currentDetectedText: EditTextService.DetectedText?
    @State private var currentEditPageIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.document != nil {
                // MARK: - Info Banner
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Edit Text is designed for small corrections. For large changes, convert to Word first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppConstants.panelPadding)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)

                Divider()

                // MARK: - Toolbar
                EditTextToolbar(
                    viewModel: viewModel,
                    undoManager: undoManager
                )

                Divider()

                // MARK: - Content Area
                HStack(spacing: 0) {
                    // Edits List Panel (collapsible)
                    if viewModel.showEditsList {
                        EditsListPanel(
                            viewModel: viewModel,
                            onScrollToEdit: { edit in
                                dismissFloatingEditBar()
                                scrollToEdit(edit)
                            }
                        )

                        Divider()
                    }

                    // PDF Viewer with click overlay
                    ZStack {
                        PDFViewerRepresentable(
                            document: viewModel.document,
                            isInteractive: true,
                            allowsAnnotationEditing: false,
                            autoScales: true,
                            displayMode: .singlePageContinuous,
                            onViewCreated: { createdPdfView, _ in
                                pdfView = createdPdfView
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Click interceptor for edit mode
                        if viewModel.isEditMode {
                            EditTextClickOverlay(
                                pdfView: pdfView,
                                onTextClicked: { detected, pageIndex, screenPoint in
                                    currentDetectedText = detected
                                    currentEditPageIndex = pageIndex
                                    viewModel.updateDetectedFont(from: detected)
                                    floatingEditBarPosition = screenPoint
                                    showFloatingEditBar = true
                                }
                            )
                        }

                        // Floating edit bar
                        if showFloatingEditBar, let detected = currentDetectedText {
                            FloatingEditBar(
                                originalText: detected.text,
                                isFontApproximate: detected.isFontApproximate,
                                onConfirm: { replacement in
                                    if let pageIndex = currentEditPageIndex {
                                        viewModel.addEdit(
                                            original: detected.text,
                                            replacement: replacement,
                                            bounds: detected.bounds,
                                            pageIndex: pageIndex,
                                            fontName: detected.fontName,
                                            fontSize: detected.fontSize,
                                            textColor: detected.textColor,
                                            isFontApproximate: detected.isFontApproximate
                                        )
                                    }
                                    dismissFloatingEditBar()
                                },
                                onCancel: {
                                    dismissFloatingEditBar()
                                }
                            )
                            .position(
                                x: min(max(floatingEditBarPosition.x, 160), 500),
                                y: max(floatingEditBarPosition.y - 60, 40)
                            )
                            .transition(.opacity)
                            .id(currentDetectedText?.bounds ?? .zero)
                        }
                    }
                }

                // MARK: - Status Banner
                StatusBannerView(
                    operationStatus: $viewModel.operationStatus,
                    onShowInFinder: { url in
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
                .padding(.horizontal, AppConstants.panelPadding)
                .padding(.bottom, 8)
            } else {
                // MARK: - Empty State / Drop Zone
                VStack(spacing: AppConstants.sectionSpacing) {
                    DropZoneView(
                        allowedTypes: [.pdf],
                        allowsMultiple: false,
                        onDrop: { urls in
                            if let url = urls.first {
                                viewModel.loadFile(url: url)
                            }
                        }
                    )
                    .frame(height: AppConstants.singleFileDropHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppConstants.panelPadding)
            }
        }
        .onAppear {
            viewModel.undoManager = undoManager
        }
        .onChange(of: undoManager) { _, newValue in
            viewModel.undoManager = newValue
        }
        .onDrop(of: [UTType.pdf.identifier], isTargeted: nil) { providers in
            handleFileDrop(providers)
        }
        .onChange(of: viewModel.isEditMode) { _, newValue in
            if !newValue { dismissFloatingEditBar() }
        }
        .onChange(of: viewModel.document) { _, _ in
            dismissFloatingEditBar()
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Save") {
                let nextURL = pendingSwitchURL
                pendingSwitchURL = nil
                viewModel.save {
                    if let nextURL {
                        viewModel.loadFile(url: nextURL)
                    }
                }
            }
            Button("Don\u{2019}t Save", role: .destructive) {
                viewModel.hasUnsavedChanges = false
                if let url = pendingSwitchURL {
                    viewModel.loadFile(url: url)
                    pendingSwitchURL = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingSwitchURL = nil
            }
        } message: {
            Text("You have unsaved edits. Save before switching?")
        }
    }

    // MARK: - Helpers

    private func dismissFloatingEditBar() {
        showFloatingEditBar = false
        currentDetectedText = nil
        currentEditPageIndex = nil
        viewModel.clearDetectedFont()
    }

    private func scrollToEdit(_ edit: TextEdit) {
        guard let doc = viewModel.document,
              let page = doc.page(at: edit.pageIndex) else { return }
        pdfView?.go(to: edit.bounds, on: page)
    }

    // MARK: - Drop Handling

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString),
                  UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true else {
                return
            }

            Task { @MainActor in
                loadFileWithUnsavedCheck(url: url)
            }
        }
        return true
    }

    private func loadFileWithUnsavedCheck(url: URL) {
        if viewModel.hasUnsavedChanges {
            pendingSwitchURL = url
            showUnsavedChangesAlert = true
        } else {
            viewModel.loadFile(url: url)
        }
    }
}

// MARK: - Click Overlay for Edit Mode

private struct EditTextClickOverlay: NSViewRepresentable {
    let pdfView: PDFView?
    let onTextClicked: (EditTextService.DetectedText, Int, CGPoint) -> Void

    func makeNSView(context: Context) -> EditTextClickView {
        let view = EditTextClickView()
        view.pdfView = pdfView
        view.onTextClicked = onTextClicked
        return view
    }

    func updateNSView(_ nsView: EditTextClickView, context: Context) {
        nsView.pdfView = pdfView
        nsView.onTextClicked = onTextClicked
    }
}

private class EditTextClickView: NSView {
    weak var pdfView: PDFView?
    var onTextClicked: ((EditTextService.DetectedText, Int, CGPoint) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let pdfView else { return }

        let viewPoint = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: viewPoint, nearest: true) else { return }

        let pdfPoint = pdfView.convert(viewPoint, to: page)
        guard let pageIndex = pdfView.document?.index(for: page) else { return }

        if let detected = EditTextService.detectTextAtPoint(pdfPoint, in: page) {
            let boundsInView = pdfView.convert(detected.bounds, from: page)
            onTextClicked?(detected, pageIndex, CGPoint(x: boundsInView.midX, y: boundsInView.midY))
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }
}
