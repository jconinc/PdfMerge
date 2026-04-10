import SwiftUI
import UniformTypeIdentifiers

struct MergeView: View {
    @StateObject private var viewModel = MergeViewModel()

    @State private var showOverwriteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Merge")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, AppConstants.headingBottomPadding)

            // Drop zone
            DropZoneView(
                allowedTypes: [.pdf],
                allowsMultiple: true,
                onDrop: { urls in
                    viewModel.addFiles(urls)
                }
            )
            .frame(height: AppConstants.multiFileDropHeight)

            if viewModel.files.isEmpty {
                // Recent files when no files loaded
                RecentFilesSection(tool: .merge) { url in
                    viewModel.addFiles([url])
                }
                .onAppearLoad()
                .padding(.top, AppConstants.sectionSpacing)
            } else {
                // File list with reorder, add more, clear all
                ReorderableFileListView(
                    files: $viewModel.files,
                    onRemove: { item in
                        viewModel.removeFile(item)
                    },
                    onUnlock: { item, password in
                        viewModel.unlockFile(item, password: password)
                    },
                    onReorder: { source, destination in
                        viewModel.moveFiles(from: source, to: destination)
                    },
                    onClearAll: {
                        viewModel.clearAll()
                    },
                    onAddMore: {
                        openAddMorePanel()
                    }
                )
                .padding(.top, AppConstants.sectionSpacing)
            }

            Spacer(minLength: AppConstants.sectionSpacing)

            Divider()
                .padding(.vertical, AppConstants.sectionSpacing)

            // Output settings
            OutputSettingsSection(
                outputSettings: $viewModel.outputSettings,
                defaultFilename: viewModel.defaultFilename,
                defaultDirectory: viewModel.files.first?.url.deletingLastPathComponent()
            )

            // Merge button
            ProgressActionButton(
                label: "Merge \(viewModel.files.count) PDFs",
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
        .overwriteConfirmation(
            isPresented: $showOverwriteConfirm,
            existingURL: viewModel.outputURL,
            onReplace: {
                viewModel.execute()
            },
            onSaveAsCopy: {
                viewModel.executeWithCopyName()
            },
            onCancel: { }
        )
    }

    // MARK: - Panels

    private func openAddMorePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        viewModel.addFiles(panel.urls)
    }
}
