import SwiftUI

struct PasswordPromptView: View {
    @Binding var isLocked: Bool
    let onUnlock: (String) -> Bool

    @State private var password = ""
    @State private var showError = false
    @State private var isExpanded = true

    var body: some View {
        if isLocked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)

                    Text("This PDF is password protected.")
                        .font(.callout)
                }

                HStack(spacing: 8) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            attemptUnlock()
                        }

                    Button("Unlock") {
                        attemptUnlock()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(password.isEmpty)
                }

                if showError {
                    Text("That password isn't correct -- please try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.easeInOut(duration: AppConstants.passwordExpandDuration), value: isLocked)
        }
    }

    // MARK: - Actions

    private func attemptUnlock() {
        if onUnlock(password) {
            // isLocked state is updated by the ViewModel via FileListManager;
            // no need to set it here — the binding refreshes when the files array syncs.
            showError = false
            password = ""
        } else {
            showError = true
            password = ""
        }
    }
}
