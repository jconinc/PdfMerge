import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import Vision

struct OCRView: View {
    @StateObject private var viewModel = OCRViewModel()
    @State private var showOverwriteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("OCR")
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
                    RecentFilesSection(tool: .ocr) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                }

                if viewModel.document != nil {
                    loadedContent
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
    }

    // MARK: - Loaded Content

    @ViewBuilder
    private var loadedContent: some View {
        // File info
        if let url = viewModel.inputURL {
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
            }
            .padding(.top, AppConstants.sectionSpacing)
        }

        // Mode picker
        GroupBox("Mode") {
            Picker("Mode", selection: $viewModel.ocrMode) {
                ForEach(OCRMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.top, AppConstants.sectionSpacing)

        // Settings
        GroupBox("Settings") {
            VStack(alignment: .leading, spacing: 10) {
                // Language
                HStack {
                    Text("Language")
                        .font(.callout)
                    Spacer()
                    Picker("Language", selection: $viewModel.selectedLanguage) {
                        ForEach(viewModel.availableLanguages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                // Accuracy
                HStack {
                    Text("Accuracy")
                        .font(.callout)
                    Spacer()
                    Picker("Accuracy", selection: $viewModel.accuracy) {
                        Text("Fast").tag(VNRequestTextRecognitionLevel.fast)
                        Text("Accurate").tag(VNRequestTextRecognitionLevel.accurate)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }

                // Skip pages toggle
                Toggle("Skip pages that already have text", isOn: $viewModel.skipTextPages)
                    .font(.callout)
            }
            .padding(.vertical, 4)
        }
        .padding(.top, AppConstants.sectionSpacing)

        // Text preview (for extractText or both modes)
        if (viewModel.ocrMode == .extractText || viewModel.ocrMode == .both),
           !viewModel.extractedText.isEmpty {
            OCRTextPreviewView(text: viewModel.extractedText)
                .padding(.top, AppConstants.sectionSpacing)
        }

        // Output settings (hidden for extractText-only mode)
        if viewModel.ocrMode != .extractText {
            OutputSettingsSection(
                outputSettings: $viewModel.outputSettings,
                defaultFilename: viewModel.defaultFilename,
                defaultDirectory: viewModel.defaultDirectory
            )
            .padding(.top, AppConstants.sectionSpacing)
        }

        // Action button
        ProgressActionButton(
            label: "Run OCR",
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
            onCancel: {
                viewModel.cancel()
            }
        )
        .padding(.top, AppConstants.actionButtonTopPadding)
        .overwriteConfirmation(
            isPresented: $showOverwriteAlert,
            existingURL: viewModel.outputURL,
            onReplace: { viewModel.execute() },
            onSaveAsCopy: { viewModel.executeWithCopyName() },
            onCancel: { }
        )
    }
}
