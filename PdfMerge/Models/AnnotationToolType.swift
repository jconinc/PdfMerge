import Foundation

enum AnnotationToolType: String, CaseIterable, Identifiable {
    case selectPan
    case highlight
    case underline
    case strikethrough
    case freehand
    case textNote
    case popupNote
    case arrow
    case rectangle
    case circle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selectPan: "Select & Pan"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .freehand: "Freehand"
        case .textNote: "Text Note"
        case .popupNote: "Popup Note"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        }
    }

    var sfSymbol: String {
        switch self {
        case .selectPan: "hand.point.up"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .freehand: "scribble"
        case .textNote: "text.cursor"
        case .popupNote: "note.text"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .circle: "circle"
        }
    }
}
