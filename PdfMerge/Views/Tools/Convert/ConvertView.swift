import SwiftUI

struct ConvertView: View {
    @StateObject private var viewModel = ConvertViewModel()

    @State private var showOverwriteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Convert")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, AppConstants.headingBottomPadding)

            // Mode picker (top-level: PDF to Images / Images to PDF)
            Picker("Mode", selection: $viewModel.mode) {
                Text(ConvertMode.pdfToImages.label).tag(ConvertMode.pdfToImages)
                Text(ConvertMode.imagesToPDF.label).tag(ConvertMode.imagesToPDF)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, AppConstants.sectionSpacing)
            .onChange(of: viewModel.mode) { _, _ in
                viewModel.clearAll()
            }

            // Mode-specific content
            switch viewModel.mode {
            case .pdfToImages:
                ConvertToImagesView(viewModel: viewModel)
            case .imagesToPDF:
                ConvertImagesToPDFView(viewModel: viewModel)
            case .pdfToWord, .pdfToExcel:
                // These modes are entered via the Advanced disclosure group
                ConvertAdvancedView(viewModel: viewModel)
            }

            // Advanced section (Word/Excel) -- shown below main modes
            if viewModel.mode == .pdfToImages || viewModel.mode == .imagesToPDF {
                ConvertAdvancedView(viewModel: viewModel)
                    .padding(.top, AppConstants.sectionSpacing)
            }

            Spacer(minLength: AppConstants.sectionSpacing)

            Divider()
                .padding(.vertical, AppConstants.sectionSpacing)

            // Output settings
            if viewModel.mode == .pdfToImages {
                // PDF to Images outputs multiple files -- show directory picker only
                outputDirectorySection
                    .padding(.bottom, AppConstants.sectionSpacing)
            } else {
                OutputSettingsSection(
                    outputSettings: $viewModel.outputSettings,
                    defaultFilename: viewModel.defaultFilename,
                    defaultDirectory: viewModel.defaultDirectory
                )
                .padding(.bottom, AppConstants.sectionSpacing)
            }

            // Action button
            ProgressActionButton(
                label: buttonLabel,
                operationStatus: viewModel.operationStatus,
                canExecute: viewModel.canExecute,
                disabledReason: viewModel.disabledReason,
                action: {
                    if viewModel.outputFileExists() {
                        showOverwriteConfirm = true
                    } else {
                        viewModel.execute()
                    }
                },
                onCancel: {
                    viewModel.cancel()
                }
            )
            .padding(.top, AppConstants.actionButtonTopPadding)

            // Status banner
            StatusBannerView(
                operationStatus: $viewModel.operationStatus,
                onShowInFinder: { url in
                    NSWorkspace.shared.showInFinder(url: url)
                }
            )
            .padding(.top, AppConstants.sectionSpacing)
        }
        .padding(AppConstants.panelPadding)
        .confirmationDialog(
            pdfToImagesOverwriteTitle,
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { viewModel.execute() }
            if viewModel.mode != .pdfToImages {
                Button("Save as Copy") { viewModel.executeWithCopyName() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if viewModel.mode == .pdfToImages {
                Text("Some image files in the output folder will be overwritten.")
            } else {
                Text("Do you want to replace the existing file or save a copy with a different name?")
            }
        }
    }

    private var pdfToImagesOverwriteTitle: String {
        if viewModel.mode == .pdfToImages {
            return "Some output images already exist."
        }
        return "A file named \"\(viewModel.outputURL?.lastPathComponent ?? "this file")\" already exists."
    }

    // MARK: - Button Label

    private var buttonLabel: String {
        switch viewModel.mode {
        case .pdfToImages:
            return "Convert to Images"
        case .imagesToPDF:
            let count = viewModel.imageFiles.count
            return "Convert \(count) Image\(count == 1 ? "" : "s") to PDF"
        case .pdfToWord:
            return "Convert to Word"
        case .pdfToExcel:
            return "Convert to Excel"
        }
    }

    // MARK: - Output Directory (for pdfToImages mode)

    private var outputDirectorySection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(directoryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Button("Change\u{2026}") {
                        chooseOutputDirectory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                Toggle("Open in Preview after saving", isOn: $viewModel.outputSettings.openAfterOperation)
                    .font(.callout)
            }
            .padding(.vertical, 4)
        }
    }

    private var directoryLabel: String {
        if let dir = viewModel.outputSettings.saveDirectory {
            return dir.path(percentEncoded: false)
        }
        if let dir = viewModel.defaultDirectory {
            return dir.path(percentEncoded: false)
        }
        return "Same folder as input"
    }

    // MARK: - Panels

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if let dir = viewModel.outputSettings.saveDirectory ?? viewModel.defaultDirectory {
            panel.directoryURL = dir
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.outputSettings.saveDirectory = url
    }
}
