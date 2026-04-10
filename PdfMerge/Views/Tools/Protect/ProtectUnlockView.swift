import SwiftUI
import UniformTypeIdentifiers

struct ProtectUnlockView: View {
    @StateObject private var viewModel = ProtectUnlockViewModel()
    @State private var showOverwriteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Protect / Unlock")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, AppConstants.headingBottomPadding)

                // Mode picker
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(ProtectMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.top, AppConstants.sectionSpacing)
                .onChange(of: viewModel.mode) { _ in
                    // Update output filename suffix when mode changes
                    if let url = viewModel.inputURL {
                        let stem = url.deletingPathExtension().lastPathComponent
                        let suffix = viewModel.mode == .protect ? "_protected" : "_unlocked"
                        viewModel.outputSettings.filename = "\(stem)\(suffix)"
                    }
                }

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
                .padding(.top, AppConstants.sectionSpacing)

                if viewModel.document == nil {
                    RecentFilesSection(tool: .protectUnlock) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                }

                if viewModel.document != nil {
                    switch viewModel.mode {
                    case .protect:
                        protectContent
                            .padding(.top, AppConstants.sectionSpacing)

                    case .unlock:
                        unlockContent
                            .padding(.top, AppConstants.sectionSpacing)
                    }

                    // Output settings
                    OutputSettingsSection(
                        outputSettings: $viewModel.outputSettings,
                        defaultFilename: viewModel.outputSettings.filename,
                        defaultDirectory: viewModel.inputURL?.deletingLastPathComponent()
                    )
                    .padding(.top, AppConstants.sectionSpacing)

                    // Action button
                    ProgressActionButton(
                        label: viewModel.mode == .protect ? "Protect" : "Remove Password",
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
        .overwriteConfirmation(
            isPresented: $showOverwriteConfirm,
            existingURL: viewModel.outputURL,
            onReplace: { viewModel.execute() },
            onSaveAsCopy: {
                viewModel.executeWithCopyName()
            },
            onCancel: { }
        )
    }

    // MARK: - Protect Mode Content

    @ViewBuilder
    private var protectContent: some View {
        if viewModel.isProtected {
            InlineBannerView(
                message: "This PDF is already password protected. To change the password, unlock it first.",
                style: .warning
            )
        }

        VStack(alignment: .leading, spacing: 10) {
            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)

            SecureField("Confirm Password", text: $viewModel.confirmPassword)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.passwordError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Allow Printing", isOn: $viewModel.allowPrinting)
                Toggle("Allow Copying", isOn: $viewModel.allowCopying)
            }
            .font(.callout)
            .padding(.vertical, 4)
        }

        Text("Uses PDF standard encryption. The password will be required to open this file in any PDF reader.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Unlock Mode Content

    @ViewBuilder
    private var unlockContent: some View {
        if !viewModel.isProtected {
            InlineBannerView(
                message: "This PDF is not password protected.",
                style: .info
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("Enter current password", text: $viewModel.unlockPassword)
                    .textFieldStyle(.roundedBorder)

                if let error = viewModel.unlockError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
