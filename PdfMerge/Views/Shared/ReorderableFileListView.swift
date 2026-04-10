import SwiftUI

struct ReorderableFileListView: View {
    @Binding var files: [PDFFileItem]
    let onRemove: (PDFFileItem) -> Void
    let onUnlock: (PDFFileItem, String) -> Bool
    var onReorder: ((IndexSet, Int) -> Void)?
    let onClearAll: () -> Void
    let onAddMore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack {
                Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Add More\u{2026}") {
                    onAddMore()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Clear All") {
                    onClearAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
                .disabled(files.isEmpty)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            // File list
            List {
                ForEach($files) { $file in
                    FileListRowView(
                        file: $file,
                        onRemove: {
                            onRemove(file)
                        },
                        onUnlock: { item, password in
                            onUnlock(item, password)
                        }
                    )
                }
                .onMove { source, destination in
                    if let onReorder {
                        onReorder(source, destination)
                    } else {
                        files.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }
}
