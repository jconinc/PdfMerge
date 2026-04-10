import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case merge
    case split
    case rotate
    case compress
    case extractPages
    case ocr
    case annotate
    case editText
    case fillForm
    case convert
    case print
    case protectUnlock

    var id: Self { self }

    var label: String {
        switch self {
        case .merge: "Merge"
        case .split: "Split"
        case .rotate: "Rotate"
        case .compress: "Compress"
        case .extractPages: "Extract Pages"
        case .ocr: "OCR"
        case .annotate: "Annotate"
        case .editText: "Edit Text"
        case .fillForm: "Fill Form"
        case .convert: "Convert"
        case .print: "Print"
        case .protectUnlock: "Protect / Unlock"
        }
    }

    var sfSymbol: String {
        switch self {
        case .merge: "doc.on.doc"
        case .split: "scissors"
        case .rotate: "rotate.right"
        case .compress: "arrow.down.doc"
        case .extractPages: "doc.text.magnifyingglass"
        case .ocr: "text.viewfinder"
        case .annotate: "pencil.and.outline"
        case .editText: "pencil.line"
        case .fillForm: "list.clipboard"
        case .convert: "arrow.triangle.2.circlepath"
        case .print: "printer"
        case .protectUnlock: "lock.shield"
        }
    }

    var keyboardShortcut: KeyEquivalent? {
        switch self {
        case .merge: "1"
        case .split: "2"
        case .rotate: "3"
        case .compress: "4"
        case .extractPages: "5"
        case .ocr: "6"
        case .annotate: "7"
        case .editText: "e"
        case .fillForm: "8"
        case .convert: "9"
        case .print: "0"
        case .protectUnlock: nil
        }
    }

    var keyboardShortcutModifiers: EventModifiers {
        .command
    }
}
