import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct AnnotateView: View {
    @StateObject private var viewModel = AnnotateViewModel()
    @Environment(\.undoManager) private var undoManager
    @State private var showUnsavedChangesAlert = false
    @State private var pendingSwitchURL: URL?
    @State private var pdfViewCoordinator: PDFViewerCoordinator?
    @State private var annotationObservers: [NSObjectProtocol] = []

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.document != nil {
                // MARK: - Toolbar
                AnnotationToolbar(
                    viewModel: viewModel,
                    undoManager: undoManager
                )

                Divider()

                // MARK: - Content Area
                HStack(spacing: 0) {
                    // Annotations List Panel (collapsible)
                    if viewModel.showAnnotationsList {
                        AnnotationsListPanel(
                            viewModel: viewModel,
                            onScrollToAnnotation: { annotation in
                                pdfViewCoordinator?.scrollToAnnotation(annotation)
                            }
                        )

                        Divider()
                    }

                    // PDF Viewer
                    PDFViewerRepresentable(
                        document: viewModel.document,
                        isInteractive: true,
                        allowsAnnotationEditing: true,
                        autoScales: true,
                        displayMode: .singlePageContinuous,
                        onViewCreated: { pdfView, coordinator in
                            coordinator.annotateViewModel = viewModel
                            pdfViewCoordinator = coordinator
                            setupAnnotationObservers(for: pdfView)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onDisappear {
            removeAnnotationObservers()
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Save") {
                viewModel.save()
                // Only switch if save succeeded (save is synchronous)
                if !viewModel.operationStatus.isError, let url = pendingSwitchURL {
                    viewModel.loadFile(url: url)
                }
                pendingSwitchURL = nil
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
            Text("You have unsaved annotations. Save before switching?")
        }
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

    // MARK: - Annotation Observers

    private func setupAnnotationObservers(for pdfView: PDFView) {
        removeAnnotationObservers()

        let annotationHitObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewAnnotationHit,
            object: pdfView,
            queue: .main
        ) { _ in
            viewModel.refreshAnnotationsList()
        }

        // Observe page changes for annotation refresh
        let pageChangedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { _ in
            viewModel.refreshAnnotationsList()
        }

        annotationObservers = [annotationHitObserver, pageChangedObserver]
    }

    private func removeAnnotationObservers() {
        for observer in annotationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        annotationObservers.removeAll()
    }
}
