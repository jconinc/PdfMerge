import SwiftUI

struct EditTextToolbar: View {
    @ObservedObject var viewModel: EditTextViewModel
    let undoManager: UndoManager?

    var body: some View {
        HStack(spacing: 4) {
            // MARK: - Mode Buttons
            Button {
                viewModel.isEditMode = false
                viewModel.clearDetectedFont()
            } label: {
                Image(systemName: "hand.point.up")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(!viewModel.isEditMode ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(!viewModel.isEditMode ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .help("Select / Pan")
            .accessibilityLabel(Text("Select / Pan"))

            Button {
                viewModel.isEditMode = true
            } label: {
                Image(systemName: "pencil.line")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.isEditMode ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(viewModel.isEditMode ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .help("Edit Text")
            .accessibilityLabel(Text("Edit Text"))

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // MARK: - Font Info (Read-Only)
            if let fontName = viewModel.detectedFont {
                Text(fontName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)

                if let fontSize = viewModel.detectedFontSize {
                    Text("\(Int(fontSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let textColor = viewModel.detectedTextColor {
                    Circle()
                        .fill(Color(nsColor: textColor))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 0.5))
                        .help("Text color")
                }

                if let warning = viewModel.fontWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help(warning)
                }

                Divider()
                    .frame(height: 20)
                    .padding(.horizontal, 4)
            }

            // MARK: - Undo / Redo
            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .disabled(undoManager?.canUndo != true)
            .help("Undo")
            .accessibilityLabel(Text("Undo"))
            .keyboardShortcut("z", modifiers: .command)

            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .disabled(undoManager?.canRedo != true)
            .help("Redo")
            .accessibilityLabel(Text("Redo"))
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Spacer()

            // MARK: - Save Buttons
            Button("Save As\u{2026}") {
                viewModel.saveAs()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.pendingEdits.isEmpty)
            .help("Save to a new file")

            Button("Save") {
                viewModel.save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)
            .help("Save edits to the current file")
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, AppConstants.panelPadding)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
