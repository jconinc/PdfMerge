import SwiftUI

struct FloatingEditBar: View {
    let originalText: String
    let isFontApproximate: Bool
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var editedText: String
    @State private var showDeleteConfirmation = false
    @FocusState private var isFocused: Bool

    init(
        originalText: String,
        isFontApproximate: Bool,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.isFontApproximate = isFontApproximate
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._editedText = State(initialValue: originalText)
    }

    private var isOverflowWarning: Bool {
        editedText.count > originalText.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Replacement text", text: $editedText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(minWidth: 200, maxWidth: 400)
                    .focused($isFocused)
                    .onSubmit {
                        confirmEdit()
                    }
                    .onExitCommand {
                        onCancel()
                    }

                Button {
                    confirmEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Confirm edit (Return)")

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel (Escape)")
            }

            // Warnings
            HStack(spacing: 12) {
                if isOverflowWarning {
                    Label("Text may overflow its original bounds", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if isFontApproximate {
                    Label("Font approximated \u{2014} visual match may vary", systemImage: "textformat.alt")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .onAppear {
            isFocused = true
        }
        .alert("Remove text?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                onConfirm("")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove this text entirely?")
        }
    }

    private func confirmEdit() {
        let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            showDeleteConfirmation = true
        } else if trimmed != originalText {
            onConfirm(trimmed)
        } else {
            onCancel()
        }
    }
}
