import SwiftUI
import PDFKit

struct AnnotationsListPanel: View {
    @ObservedObject var viewModel: AnnotateViewModel
    let onScrollToAnnotation: (PDFAnnotation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Text("Annotations")
                    .font(.headline)

                Spacer()

                Text("\(viewModel.annotations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showAnnotationsList.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
                .help(viewModel.showAnnotationsList ? "Hide Annotations Panel" : "Show Annotations Panel")
                .accessibilityLabel(Text("Toggle Annotations Panel"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // MARK: - Annotations List
            if viewModel.annotationsByPage.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "pencil.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No annotations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.annotationsByPage, id: \.pageIndex) { group in
                        Section {
                            ForEach(group.annotations, id: \.self) { annotation in
                                AnnotationRow(
                                    annotation: annotation,
                                    viewModel: viewModel
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onScrollToAnnotation(annotation)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.removeAnnotation(annotation)
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

// MARK: - Annotation Row

private struct AnnotationRow: View {
    let annotation: PDFAnnotation
    let viewModel: AnnotateViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.annotationIcon(for: annotation))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.annotationLabel(for: annotation))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(viewModel.annotationPreviewText(for: annotation))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
