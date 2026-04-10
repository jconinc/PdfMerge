import SwiftUI
import UniformTypeIdentifiers

struct ConvertToImagesView: View {
    @ObservedObject var viewModel: ConvertViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.sectionSpacing) {
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

            // Recent files when no document loaded
            if viewModel.document == nil {
                RecentFilesSection(tool: .convert) { url in
                    viewModel.loadFile(url: url)
                }
                .onAppearLoad()
            }

            // Settings (visible once a PDF is loaded)
            if viewModel.document != nil {
                fileInfoRow

                GroupBox("Format") {
                    VStack(alignment: .leading, spacing: 10) {
                        // Image format picker
                        Picker("Image Format", selection: $viewModel.imageFormat) {
                            Text("JPG").tag(ConvertService.ImageFormat.jpg)
                            Text("PNG").tag(ConvertService.ImageFormat.png)
                            Text("TIFF").tag(ConvertService.ImageFormat.tiff)
                        }
                        .pickerStyle(.segmented)

                        // Resolution picker
                        Picker("Resolution", selection: $viewModel.resolution) {
                            Text("72 dpi").tag(72)
                            Text("150 dpi").tag(150)
                            Text("300 dpi").tag(300)
                            Text("600 dpi").tag(600)
                        }

                        // Optional page range
                        HStack {
                            Text("Pages:")
                                .font(.callout)
                            TextField("e.g. 1-5, 8 (blank for all)", text: $viewModel.pageRangeText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - File Info

    @ViewBuilder
    private var fileInfoRow: some View {
        if let url = viewModel.inputURL, let doc = viewModel.document {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s") \u{2022} \(url.fileSizeFormatted)")
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
}
