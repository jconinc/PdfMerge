import SwiftUI
import AppKit

struct OCRTextPreviewView: View {
    let text: String

    var body: some View {
        GroupBox("Extracted Text") {
            VStack(alignment: .leading, spacing: 8) {
                // Stats caption
                HStack {
                    Text(statsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Scrollable text area
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 120, maxHeight: 300)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        copyAll()
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        saveAsText()
                    } label: {
                        Label("Save as .txt", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Stats

    private var statsLabel: String {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return "\(lines.count) line\(lines.count == 1 ? "" : "s"), \(words) word\(words == 1 ? "" : "s")"
    }

    // MARK: - Actions

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveAsText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "extracted_text.txt"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Errors are non-critical for text export; the user can try again
        }
    }
}
