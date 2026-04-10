import Foundation

@MainActor
final class FilePasswordStore {
    static let shared = FilePasswordStore()

    private var passwordsByFileID: [UUID: String] = [:]

    private init() {}

    func setPassword(_ password: String, for fileID: UUID) {
        passwordsByFileID[fileID] = password
    }

    func password(for fileID: UUID) -> String? {
        passwordsByFileID[fileID]
    }

    func removePassword(for fileID: UUID) {
        passwordsByFileID.removeValue(forKey: fileID)
    }

    func removePasswords(for fileIDs: [UUID]) {
        for fileID in fileIDs {
            passwordsByFileID.removeValue(forKey: fileID)
        }
    }
}
