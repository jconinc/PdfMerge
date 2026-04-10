import SwiftUI
import PDFKit

struct FieldsListPanel: View {
    let fieldsByPage: [(page: Int, fields: [FormFieldInfo])]
    let onFieldSelected: (FormFieldInfo) -> Void

    var body: some View {
        List {
            ForEach(fieldsByPage, id: \.page) { group in
                Section {
                    ForEach(group.fields) { field in
                        fieldRow(field)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onFieldSelected(field)
                            }
                    }
                } header: {
                    Text("Page \(group.page + 1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 240)
    }

    // MARK: - Field Row

    @ViewBuilder
    private func fieldRow(_ field: FormFieldInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: field.fieldType.sfSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(field.fieldName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Image(systemName: field.isFilled ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(field.isFilled ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}
