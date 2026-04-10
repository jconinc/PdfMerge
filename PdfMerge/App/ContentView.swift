import SwiftUI

struct ContentView: View {
    @Binding var selectedTool: Tool

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTool: $selectedTool)
                .navigationSplitViewColumnWidth(AppConstants.sidebarWidth)
        } detail: {
            detailView(for: selectedTool)
        }
        .navigationTitle(selectedTool.label)
        .frame(
            minWidth: AppConstants.minimumWindowWidth,
            minHeight: AppConstants.minimumWindowHeight
        )
    }

    @ViewBuilder
    private func detailView(for tool: Tool) -> some View {
        switch tool {
        case .merge:
            MergeView()
        case .split:
            SplitView()
        case .rotate:
            RotateView()
        case .compress:
            CompressView()
        case .extractPages:
            ExtractPagesView()
        case .ocr:
            OCRView()
        case .annotate:
            AnnotateView()
        case .editText:
            EditTextView()
        case .fillForm:
            FillFormView()
        case .convert:
            ConvertView()
        case .print:
            PrintView()
        case .protectUnlock:
            ProtectUnlockView()
        }
    }
}
