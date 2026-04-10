import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PrintView: View {
    @StateObject private var viewModel = PrintViewModel()

    /// Holds a reference to the underlying PDFView (NSView) so we can pass it to the print operation.
    @State private var pdfViewRef: PDFView?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                Text("Print")
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
                    RecentFilesSection(tool: .print) { url in
                        viewModel.loadFile(url: url)
                    }
                    .onAppearLoad()
                    .padding(.top, AppConstants.sectionSpacing)
                }

                if viewModel.document != nil {
                    // PDF Preview - must remain visible during print
                    PDFViewerRepresentable(
                        document: viewModel.document,
                        isInteractive: false,
                        autoScales: true,
                        displayMode: .singlePageContinuous,
                        onViewCreated: { view, _ in
                            pdfViewRef = view
                        }
                    )
                    .frame(minHeight: 300)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    }
                    .padding(.top, AppConstants.sectionSpacing)

                    // Quick settings (read-only reference)
                    GroupBox("Document Info") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Pages:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(viewModel.pageCount)")
                            }
                            .font(.callout)

                            HStack {
                                Text("File Size:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(viewModel.fileSizeFormatted)
                            }
                            .font(.callout)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.top, AppConstants.sectionSpacing)

                    // Print button
                    Button {
                        if let view = pdfViewRef {
                            viewModel.printDocument(from: view)
                        }
                    } label: {
                        Label("Print\u{2026}", systemImage: "printer")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canExecute || pdfViewRef == nil)
                    .padding(.top, AppConstants.actionButtonTopPadding)
                }

                // Status banner
                StatusBannerView(
                    operationStatus: $viewModel.operationStatus,
                    onShowInFinder: nil
                )
            }
            .padding(AppConstants.panelPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
