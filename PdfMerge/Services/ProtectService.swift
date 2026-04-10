import Foundation
import PDFKit

/// Permissions to apply when protecting a PDF.
struct PDFPermissions {
    var allowPrinting: Bool
    var allowCopying: Bool

    static let allAllowed = PDFPermissions(allowPrinting: true, allowCopying: true)
    static let none = PDFPermissions(allowPrinting: false, allowCopying: false)
}

enum ProtectService {

    // MARK: - Errors

    enum ProtectError: LocalizedError {
        case documentUnreadable(URL)
        case protectionFailed
        case unlockFailed
        case incorrectPassword

        var errorDescription: String? {
            switch self {
            case .documentUnreadable(let url):
                return "Could not open \(url.lastPathComponent). It may be damaged or not a valid PDF."
            case .protectionFailed:
                return "Could not apply password protection. Please try again."
            case .unlockFailed:
                return "Could not remove the password from this file."
            case .incorrectPassword:
                return "The password you entered is incorrect. Please try again."
            }
        }
    }

    // MARK: - Protect

    /// Apply password protection to a PDF file.
    /// - Parameters:
    ///   - inputURL: Source PDF file.
    ///   - outputURL: Destination for the protected PDF.
    ///   - password: Owner password to set.
    ///   - permissions: Access permissions to grant.
    /// - Returns: The output URL.
    @discardableResult
    static func protect(
        inputURL: URL,
        outputURL: URL,
        password: String,
        permissions: PDFPermissions
    ) async throws -> URL {
        guard let document = PDFDocument(url: inputURL) else {
            throw ProtectError.documentUnreadable(inputURL)
        }

        // If the document is locked, we can't protect it further without unlocking first
        if document.isLocked {
            throw ProtectError.documentUnreadable(inputURL)
        }

        // Owner password controls permissions; user password controls opening.
        // They must differ — if identical, any reader can bypass printing/copying
        // restrictions with the open password. Use a random owner password that
        // the user never sees, so permissions can't be overridden.
        let ownerPassword = UUID().uuidString

        var options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: ownerPassword,
            .userPasswordOption: password
        ]

        // Set permissions via PDF write options
        if !permissions.allowPrinting {
            options[.allowsPrintingOption] = false
        }
        if !permissions.allowCopying {
            options[.allowsCopyingOption] = false
        }

        return try FileService.atomicWrite(document, to: outputURL, options: options)
    }

    // MARK: - Unlock

    /// Remove password protection from a PDF file.
    /// - Parameters:
    ///   - inputURL: Source (locked) PDF file.
    ///   - outputURL: Destination for the unlocked PDF.
    ///   - password: Password to unlock the source.
    /// - Returns: The output URL.
    @discardableResult
    static func unlock(
        inputURL: URL,
        outputURL: URL,
        password: String
    ) async throws -> URL {
        guard let document = PDFDocument(url: inputURL) else {
            throw ProtectError.documentUnreadable(inputURL)
        }

        if document.isLocked {
            guard document.unlock(withPassword: password) else {
                throw ProtectError.incorrectPassword
            }
        }

        // Write the unlocked document without password options
        // This produces an unprotected PDF
        guard let data = document.dataRepresentation() else {
            throw ProtectError.unlockFailed
        }

        return try FileService.atomicWrite(data, to: outputURL)
    }
}
