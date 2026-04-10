import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ConvertAdvancedView: View {
    @ObservedObject var viewModel: ConvertViewModel

    var body: some View {
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: AppConstants.sectionSpacing) {
                Text("Convert PDFs to Word or Excel using a bundled conversion engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if !viewModel.pythonAvailable {
                    InlineBannerView(
                        message: "Word and Excel conversion isn't set up yet. Ask John to run the setup script.",
                        style: .warning
                    )
                } else {
                    // Mode toggle: Word / Excel
                    Picker("Convert to", selection: $viewModel.mode) {
                        Text("Word (.docx)").tag(ConvertMode.pdfToWord)
                        Text("Excel (.xlsx)").tag(ConvertMode.pdfToExcel)
                    }
                    .pickerStyle(.segmented)

                    // Single-file drop zone for PDF
                    DropZoneView(
                        allowedTypes: [.pdf],
                        allowsMultiple: false
                    ) { urls in
                        if let url = urls.first {
                            viewModel.loadFile(url: url)
                        }
                    }
                    .frame(height: AppConstants.singleFileDropHeight)

                    // File info when loaded
                    if let url = viewModel.inputURL, let doc = viewModel.document {
                        advancedFileInfoRow(url: url, document: doc)
                    }

                    // No-text-layer warning
                    if viewModel.document != nil && !viewModel.hasTextLayer {
                        InlineBannerView(
                            message: "This PDF appears to be scanned. Run OCR first for better conversion results.",
                            style: .warning
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - File Info Row

    @ViewBuilder
    private func advancedFileInfoRow(url: URL, document: PDFDocument) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s") \u{2022} \(url.fileSizeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.clearAll()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove file")
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
    }
}
