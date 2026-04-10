import SwiftUI

struct EditsListPanel: View {
    @ObservedObject var viewModel: EditTextViewModel
    let onScrollToEdit: (TextEdit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Text("Edits")
                    .font(.headline)

                Spacer()

                Text("\(viewModel.pendingEdits.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showEditsList.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
                .help(viewModel.showEditsList ? "Hide Edits Panel" : "Show Edits Panel")
                .accessibilityLabel(Text("Toggle Edits Panel"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // MARK: - Edits List
            if viewModel.editsByPage.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "pencil.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No edits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.editsByPage, id: \.pageIndex) { group in
                        Section {
                            ForEach(group.edits) { edit in
                                EditRow(edit: edit)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onScrollToEdit(edit)
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.removeEdit(edit)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text(group.pageLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 220)
        .background(.background)
    }
}

// MARK: - Edit Row

private struct EditRow: View {
    let edit: TextEdit

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(edit.originalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough()

                Text(edit.replacementText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if edit.isFontApproximate {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Font approximated")
            }
        }
        .padding(.vertical, 2)
    }
}
