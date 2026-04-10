import SwiftUI
import UniformTypeIdentifiers

struct CompressView: View {
    @StateObject private var viewModel = CompressViewModel()

    @State private var showOverwriteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Compress")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, AppConstants.headingBottomPadding)

            // Drop zone
            DropZoneView(
                allowedTypes: [.pdf],
                allowsMultiple: true,
                onDrop: { urls in
                    viewModel.loadFiles(urls)
                }
            )
            .frame(height: AppConstants.multiFileDropHeight)

            if viewModel.files.isEmpty {
                // Guidance + recent files
                VStack(spacing: 6) {
                    Text("Add one or more PDFs to compress them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, AppConstants.sectionSpacing)

                RecentFilesSection(tool: .compress) { url in
                    viewModel.loadFiles([url])
                }
                .onAppearLoad()
                .padding(.top, AppConstants.sectionSpacing)
            } else {
                // File list
                fileListSection
                    .padding(.top, AppConstants.sectionSpacing)

                // Preset picker
                presetSection
                    .padding(.top, AppConstants.sectionSpacing)

                // Size estimate
                if let estimate = viewModel.estimatedSize {
                    Text(estimate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }

            Spacer(minLength: AppConstants.sectionSpacing)

            if !viewModel.files.isEmpty {
                Divider()
                    .padding(.vertical, AppConstants.sectionSpacing)

                // Output settings — show filename field only for single file
                if viewModel.files.count <= 1 {
                    OutputSettingsSection(
                        outputSettings: $viewModel.outputSettings,
                        defaultFilename: viewModel.defaultFilename,
                        defaultDirectory: viewModel.defaultDirectory
                    )
                } else {
                    compressMultiOutputSection
                }

                // Compress button
                ProgressActionButton(
                    label: viewModel.buttonLabel,
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
        }
        .padding(AppConstants.panelPadding)
        .onChange(of: viewModel.selectedPreset) { _, _ in
            viewModel.updateEstimatedSize()
        }
        .confirmationDialog(
            "Some output files already exist.",
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { viewModel.execute() }
            if viewModel.files.count <= 1 {
                Button("Save as Copy") { viewModel.executeWithCopyName() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if viewModel.files.count > 1 {
                Text("Compressed files with the same names will be overwritten in the output folder.")
            } else {
                Text("Do you want to replace the existing file or save a copy with a different name?")
            }
        }
    }

    // MARK: - Multi-File Output (directory only, no filename)

    private var compressMultiOutputSection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each file will be compressed to the same folder with a \u{201C}_compress\u{201D} suffix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(viewModel.outputSettings.saveDirectory?.path(percentEncoded: false)
                         ?? viewModel.defaultDirectory?.path(percentEncoded: false)
                         ?? "Same folder as input")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Button("Change\u{2026}") {
                        chooseCompressOutputDirectory()
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

    private func chooseCompressOutputDirectory() {
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

    // MARK: - File List

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($viewModel.files) { $file in
                FileListRowView(
                    file: $file,
                    onRemove: {
                        viewModel.removeFile(file)
                    },
                    onUnlock: { item, password in
                        viewModel.unlockFile(item, password: password)
                    }
                )
            }

            HStack {
                Button("Add More\u{2026}") {
                    openAddMorePanel()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Clear All") {
                    viewModel.clearAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Preset Picker

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality Preset")
                .font(.headline)

            Picker("Quality Preset", selection: $viewModel.selectedPreset) {
                ForEach(CompressionPreset.allCases) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(preset.label) (\(preset.dpi) dpi)")
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(viewModel.selectedPreset.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Panels

    private func openAddMorePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        viewModel.loadFiles(panel.urls)
    }
}
