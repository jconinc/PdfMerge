import SwiftUI

struct OutputSettingsSection: View {
    @Binding var outputSettings: OutputSettings
    let defaultFilename: String
    let defaultDirectory: URL?

    var body: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                // Filename
                TextField("Filename", text: $outputSettings.filename)
                    .textFieldStyle(.roundedBorder)

                // Directory picker
                HStack {
                    Text(directoryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    Button("Change\u{2026}") {
                        chooseDirectory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                // Open after operation
                Toggle("Open in Preview after saving", isOn: $outputSettings.openAfterOperation)
                    .font(.callout)
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            if outputSettings.filename.isEmpty {
                outputSettings.filename = defaultFilename
            }
            if outputSettings.saveDirectory == nil {
                outputSettings.saveDirectory = defaultDirectory
            }
        }
    }

    // MARK: - Computed

    private var directoryLabel: String {
        if let dir = outputSettings.saveDirectory {
            return dir.path(percentEncoded: false)
        }
        if let dir = defaultDirectory {
            return dir.path(percentEncoded: false)
        }
        return "Same folder as input"
    }

    // MARK: - Directory Picker

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        if let dir = outputSettings.saveDirectory ?? defaultDirectory {
            panel.directoryURL = dir
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputSettings.saveDirectory = url
    }
}
