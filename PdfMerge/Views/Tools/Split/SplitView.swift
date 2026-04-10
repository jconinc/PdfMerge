import SwiftUI
import UniformTypeIdentifiers

struct SplitView: View {
    @StateObject private var viewModel = SplitViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Split")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, AppConstants.headingBottomPadding)

                // Drop zone
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

                if viewModel.document == nil {
                    // Recent files when no file loaded
                    RecentFilesSection(tool: .split) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                }

                if viewModel.document != nil {
                    // Mode picker
                    Picker("Split Mode", selection: $viewModel.splitMode) {
                        ForEach(SplitMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.top, AppConstants.sectionSpacing)

                    // Mode-specific content
                    switch viewModel.splitMode {
                    case .byRange:
                        SplitByRangeView(viewModel: viewModel)
                            .padding(.top, AppConstants.sectionSpacing)

                    case .everyN:
                        SplitEveryNView(viewModel: viewModel)
                            .padding(.top, AppConstants.sectionSpacing)

                    case .byPage:
                        SplitByPageView(viewModel: viewModel)
                            .padding(.top, AppConstants.sectionSpacing)
                    }

                    // Output directory (split produces multiple files, so filename field is not applicable)
                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(splitOutputDirectoryLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)

                                Spacer()

                                Button("Change\u{2026}") {
                                    chooseSplitOutputDirectory()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }

                            Toggle("Open in Preview after saving", isOn: $viewModel.outputSettings.openAfterOperation)
                                .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.top, AppConstants.sectionSpacing)

                    // Action button
                    ProgressActionButton(
                        label: "Split",
                        operationStatus: viewModel.operationStatus,
                        canExecute: viewModel.canExecute,
                        disabledReason: viewModel.disabledReason,
                        action: {
                            if viewModel.outputFilesExist() {
                                viewModel.showOverwriteConfirmation = true
                            } else {
                                viewModel.execute()
                            }
                        },
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Some output files already exist in the destination folder.",
            isPresented: $viewModel.showOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                viewModel.execute()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Running this split will overwrite existing files with the same names.")
        }
    }

    // MARK: - Output Directory

    private var splitOutputDirectoryLabel: String {
        if let dir = viewModel.outputSettings.saveDirectory {
            return dir.path(percentEncoded: false)
        }
        if let dir = viewModel.inputURL?.deletingLastPathComponent() {
            return dir.path(percentEncoded: false)
        }
        return "Same folder as input"
    }

    private func chooseSplitOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if let dir = viewModel.outputSettings.saveDirectory ?? viewModel.inputURL?.deletingLastPathComponent() {
            panel.directoryURL = dir
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.outputSettings.saveDirectory = url
    }
}
