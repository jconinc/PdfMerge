import SwiftUI

struct SidebarView: View {
    @Binding var selectedTool: Tool

    var body: some View {
        List(Tool.allCases, selection: $selectedTool) { tool in
            Label(tool.label, systemImage: tool.sfSymbol)
                .tag(tool)
                .accessibilityLabel(tool.label)
        }
        .listStyle(.sidebar)
    }
}
