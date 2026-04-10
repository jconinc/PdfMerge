import SwiftUI

struct ErrorMessageView: View {
    let message: String
    var showRepair: Bool = false
    var onRepair: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)

            Text(message)
                .font(.caption)
                .foregroundStyle(.red)

            if showRepair, let onRepair {
                Button("Repair") {
                    onRepair()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
}
