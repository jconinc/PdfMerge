import Foundation

// MARK: - PDFToolError

enum PDFToolError: LocalizedError {
    case incorrectPassword
    case corruptedPDF
    case noTextLayer
    case alreadyOptimized
    case xfaForm
    case noFormFields
    case pythonNotSetUp
    case invalidPageRange(String)
    case operationCancelled

    var errorDescription: String? {
        switch self {
        case .incorrectPassword:
            return "The password is incorrect. Please try again."
        case .corruptedPDF:
            return "This PDF appears to be damaged and can't be opened."
        case .noTextLayer:
            return "This PDF has no selectable text. Run OCR first to add a text layer."
        case .alreadyOptimized:
            return "This PDF is already as small as it can get."
        case .xfaForm:
            return "This PDF uses XFA forms, which aren't supported. Open it in Adobe Acrobat instead."
        case .noFormFields:
            return "This PDF doesn't contain any fillable form fields."
        case .pythonNotSetUp:
            return "Word/Excel conversion isn't set up yet. Run the setup script first."
        case .invalidPageRange(let detail):
            return "Invalid page range: \(detail)"
        case .operationCancelled:
            return "The operation was cancelled."
        }
    }
}

// MARK: - ErrorMapper

enum ErrorMapper {

    /// Translates a Swift error into a plain-English message suitable for display.
    static func map(_ error: Error) -> String {
        if let toolError = error as? PDFToolError {
            return toolError.localizedDescription
        }

        if !(error is CocoaError),
           !(error is POSIXError),
           let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }

        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return "This file has been moved or deleted."
            case .fileWriteOutOfSpace:
                return "There isn't enough disk space to complete this operation."
            case .fileWriteNoPermission, .fileReadNoPermission:
                return "Can't save here -- try your Desktop instead."
            default:
                break
            }
        }

        if let posixError = error as? POSIXError {
            switch posixError.code {
            case .EACCES:
                return "Can't save here -- try your Desktop instead."
            case .ENOSPC:
                return "There isn't enough disk space to complete this operation."
            default:
                break
            }
        }

        return "Something went wrong. Please try again."
    }
}
