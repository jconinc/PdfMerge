import SwiftUI

struct StatusBannerView: View {
    @Binding var operationStatus: OperationStatus
    let onShowInFinder: ((URL) -> Void)?

    @State private var isVisible = false

    var body: some View {
        Group {
            switch operationStatus {
            case .success(let message, let outputURL):
                bannerContent(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    message: message,
                    outputURL: outputURL
                )

            case .error(let message, _):
                bannerContent(
                    icon: "exclamationmark.circle.fill",
                    iconColor: .red,
                    message: message,
                    outputURL: nil
                )

            default:
                EmptyView()
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeOut(duration: AppConstants.bannerSlideDuration), value: isVisible)
        .onChange(of: operationStatus) { _, newValue in
            switch newValue {
            case .success, .error:
                isVisible = true
            default:
                isVisible = false
            }
        }
        .task(id: bannerTaskID) {
            // Auto-dismiss after timeout
            guard case .success = operationStatus else {
                guard case .error = operationStatus else { return }
                try? await Task.sleep(for: .seconds(AppConstants.bannerAutoDismiss))
                operationStatus = .idle
                return
            }
            try? await Task.sleep(for: .seconds(AppConstants.bannerAutoDismiss))
            operationStatus = .idle
        }
    }

    // MARK: - Banner Content

    @ViewBuilder
    private func bannerContent(
        icon: String,
        iconColor: Color,
        message: String,
        outputURL: URL?
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)

            Text(message)
                .font(.callout)
                .lineLimit(2)

            Spacer()

            if let url = outputURL {
                Button("Show in Finder") {
                    onShowInFinder?(url)
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }

            Button {
                operationStatus = .idle
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
    }

    // MARK: - Task Identity

    /// Changes whenever a new banner-worthy status appears so `.task` restarts the auto-dismiss timer.
    private var bannerTaskID: String {
        switch operationStatus {
        case .success(let msg, _): return "success-\(msg)"
        case .error(let msg, _): return "error-\(msg)"
        default: return "idle"
        }
    }
}
