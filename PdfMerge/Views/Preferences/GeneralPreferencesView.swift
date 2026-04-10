import SwiftUI

struct GeneralPreferencesView: View {
    @AppStorage(PreferenceKeys.openAfterOperation) private var openAfterOperation = true
    @AppStorage(PreferenceKeys.defaultSaveLocation) private var defaultSaveLocation: String = ""

    var body: some View {
        Form {
            Toggle("Open files in Preview after operation", isOn: $openAfterOperation)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default save location:")
                    Text(displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Change\u{2026}") {
                    chooseDirectory()
                }

                Button("Reset to Default") {
                    defaultSaveLocation = ""
                }
                .disabled(defaultSaveLocation.isEmpty)
            }
        }
        .padding()
    }

    private var displayPath: String {
        if defaultSaveLocation.isEmpty {
            return "Same folder as input file"
        }
        return defaultSaveLocation
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a default save location for output files."

        if panel.runModal() == .OK, let url = panel.url {
            defaultSaveLocation = url.path(percentEncoded: false)
        }
    }
}
