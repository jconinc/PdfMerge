import SwiftUI

enum BannerStyle {
    case info
    case warning

    var icon: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .info: .blue
        case .warning: .orange
        }
    }

    var backgroundColor: Color {
        switch self {
        case .info: .blue.opacity(0.08)
        case .warning: .orange.opacity(0.08)
        }
    }
}

struct InlineBannerView: View {
    let message: String
    let style: BannerStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style.icon)
                .foregroundStyle(style.foregroundColor)
                .font(.callout)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(style.backgroundColor)
        }
    }
}
