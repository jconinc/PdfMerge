import SwiftUI

struct ProgressActionButton: View {
    let label: String
    let operationStatus: OperationStatus
    let canExecute: Bool
    let disabledReason: String?
    let action: () async -> Void
    let onCancel: () -> Void

    @State private var showCancel = false

    var body: some View {
        switch operationStatus {
        case .running(let progress, let message):
            runningView(progress: progress, message: message)

        default:
            idleView
        }
    }

    // MARK: - Idle State

    private var idleView: some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canExecute)
        .help(canExecute ? "" : (disabledReason ?? ""))
    }

    // MARK: - Running State

    private func runningView(progress: Double, message: String) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progress, total: 1.0) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showCancel {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .task(id: "cancelDelay") {
            showCancel = false
            try? await Task.sleep(for: .seconds(AppConstants.cancelButtonDelay))
            showCancel = true
        }
    }
}
