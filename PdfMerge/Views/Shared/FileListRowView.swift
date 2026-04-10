import SwiftUI

struct FileListRowView: View {
    @Binding var file: PDFFileItem
    let onRemove: () -> Void
    let onUnlock: (PDFFileItem, String) -> Bool

    @State private var showPasswordPrompt = false

    var body: some View {
        HStack(spacing: 10) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)

            // Thumbnail with lock badge
            thumbnailView

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(file.pageCount) page\(file.pageCount == 1 ? "" : "s"), \(file.fileSizeFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove file")
        }
        .contentShape(Rectangle())
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail = file.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: AppConstants.thumbnailSize.width, height: AppConstants.thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if file.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .padding(3)
                    .background(.ultraThickMaterial, in: Circle())
                    .foregroundStyle(.orange)
                    .onTapGesture {
                        showPasswordPrompt = true
                    }
            }
        }
        .popover(isPresented: $showPasswordPrompt) {
            PasswordPromptView(
                isLocked: $file.isLocked,
                onUnlock: { password in
                    onUnlock(file, password)
                }
            )
            .padding()
            .frame(width: 260)
        }
    }
}
