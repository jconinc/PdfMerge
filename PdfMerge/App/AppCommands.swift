import SwiftUI

struct AppCommands: Commands {
    @Binding var selectedTool: Tool

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Section {
                ForEach(Tool.allCases) { tool in
                    if let shortcut = tool.keyboardShortcut {
                        Button(tool.label) {
                            selectedTool = tool
                        }
                        .keyboardShortcut(shortcut, modifiers: tool.keyboardShortcutModifiers)
                    } else {
                        Button(tool.label) {
                            selectedTool = tool
                        }
                    }
                }
            }
        }
    }
}
