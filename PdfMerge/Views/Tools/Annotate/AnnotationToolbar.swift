import SwiftUI
import PDFKit

struct AnnotationToolbar: View {
    @ObservedObject var viewModel: AnnotateViewModel
    let undoManager: UndoManager?

    var body: some View {
        HStack(spacing: 4) {
            // MARK: - Tool Buttons
            ForEach(AnnotationToolType.allCases) { toolType in
                Button {
                    viewModel.selectedTool = toolType
                } label: {
                    Image(systemName: toolType.sfSymbol)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.selectedTool == toolType ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(viewModel.selectedTool == toolType ? Color.accentColor : Color.clear, lineWidth: 1)
                )
                .help(toolType.label)
                .accessibilityLabel(Text(toolType.label))
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // MARK: - Color Picker
            ColorPicker("", selection: $viewModel.selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
                .help("Annotation Color")
                .onChange(of: viewModel.selectedColor) { _, _ in
                    viewModel.persistColor()
                }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // MARK: - Stroke Weight Picker
            Picker("Stroke", selection: $viewModel.strokeWidth) {
                ForEach(AnnotateViewModel.StrokeWeight.allCases) { weight in
                    Text(weight.label).tag(weight)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .help("Stroke Weight")
            .onChange(of: viewModel.strokeWidth) { _, _ in
                viewModel.persistStrokeWidth()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // MARK: - Undo / Redo
            Button {
                undoManager?.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .disabled(undoManager?.canUndo != true)
            .help("Undo")
            .accessibilityLabel(Text("Undo"))
            .keyboardShortcut("z", modifiers: .command)

            Button {
                undoManager?.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .disabled(undoManager?.canRedo != true)
            .help("Redo")
            .accessibilityLabel(Text("Redo"))
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Spacer()

            // MARK: - Save Buttons
            Button("Save As\u{2026}") {
                viewModel.saveAs()
            }
            .buttonStyle(.bordered)
            .help("Save to a new file")

            Button("Save") {
                viewModel.save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave)
            .help("Save annotations to the current file")
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, AppConstants.panelPadding)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
