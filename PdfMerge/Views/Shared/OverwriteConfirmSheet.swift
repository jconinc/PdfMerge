import SwiftUI

struct OverwriteConfirmSheet: ViewModifier {
    @Binding var isPresented: Bool
    let existingURL: URL?
    let onReplace: () -> Void
    let onSaveAsCopy: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "A file named \"\(existingURL?.lastPathComponent ?? "this file")\" already exists.",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    onReplace()
                }

                Button("Save as Copy") {
                    onSaveAsCopy()
                }

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
            } message: {
                Text("Do you want to replace the existing file or save a copy with a different name?")
            }
    }
}

extension View {
    func overwriteConfirmation(
        isPresented: Binding<Bool>,
        existingURL: URL?,
        onReplace: @escaping () -> Void,
        onSaveAsCopy: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(
            OverwriteConfirmSheet(
                isPresented: isPresented,
                existingURL: existingURL,
                onReplace: onReplace,
                onSaveAsCopy: onSaveAsCopy,
                onCancel: onCancel
            )
        )
    }
}
