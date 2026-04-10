import SwiftUI

struct RecentFilesSection: View {
    let tool: Tool
    let onSelect: (URL) -> Void

    @State private var recentFiles: [RecentFile] = []

    var body: some View {
        if !recentFiles.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)

                ForEach(recentFiles) { recentFile in
                    if let url = recentFile.url {
                        Button {
                            onSelect(url)
                        } label: {
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Text(recentFile.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Load Recent Files

    func loadRecentFiles() {
        recentFiles = RecentFilesService.getRecentFiles(for: tool)
    }
}

extension RecentFilesSection {
    /// Call this when the view appears to load recent files.
    func onAppearLoad() -> some View {
        self
            .onAppear {
                loadRecentFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: RecentFilesService.didChangeNotification)) { _ in
                loadRecentFiles()
            }
    }
}
