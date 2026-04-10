import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let allowedTypes: [UTType]
    let allowsMultiple: Bool
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var showRejection = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: AppConstants.dropZoneDashPattern)
                )
                .foregroundStyle(borderColor)
                .animation(.easeInOut(duration: AppConstants.dropZoneHoverDuration), value: isTargeted)

            VStack(spacing: 8) {
                if showRejection {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text("Only PDF files are accepted here.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: dropSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(dropLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Browse\u{2026}") {
                        openPanel()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .onDrop(of: allowedTypes.map(\.identifier), isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Computed

    private var borderColor: Color {
        if showRejection {
            return .red
        }
        return isTargeted ? .accentColor : .secondary.opacity(0.3)
    }

    private var dropSymbol: String {
        if allowedTypes.contains(.image) {
            return "photo.badge.plus"
        }
        return "doc.badge.plus"
    }

    private var dropLabel: String {
        if allowedTypes.contains(.image) {
            return "Drop images here"
        }
        return allowsMultiple ? "Drop PDFs here" : "Drop PDF here"
    }

    // MARK: - NSOpenPanel

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedTypes

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        if !urls.isEmpty {
            onDrop(urls)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Use an indexed array to preserve the original drop order
        // regardless of which async callbacks complete first.
        let lock = NSLock()
        var indexed: [(Int, URL)] = []
        let group = DispatchGroup()

        for (i, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) else {
                    return
                }

                let fileType = UTType(filenameExtension: url.pathExtension)
                let isAllowed = allowedTypes.contains { allowedType in
                    fileType?.conforms(to: allowedType) == true
                }

                if isAllowed {
                    lock.lock()
                    indexed.append((i, url))
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            let urls = indexed.sorted { $0.0 < $1.0 }.map(\.1)
            if urls.isEmpty {
                // Rejection flash
                showRejection = true
                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.rejectionMessageDismiss) {
                    showRejection = false
                }
            } else {
                if allowsMultiple {
                    onDrop(urls)
                } else {
                    onDrop(Array(urls.prefix(1)))
                }
            }
        }

        return true
    }
}
