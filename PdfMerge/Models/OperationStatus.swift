import Foundation

enum OperationStatus: Equatable {
    case idle
    case running(progress: Double, message: String)
    case success(message: String, outputURL: URL?)
    case error(message: String, isRecoverable: Bool)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    static func == (lhs: OperationStatus, rhs: OperationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case let (.running(lProgress, lMessage), .running(rProgress, rMessage)):
            return lProgress == rProgress && lMessage == rMessage
        case let (.success(lMessage, lURL), .success(rMessage, rURL)):
            return lMessage == rMessage && lURL == rURL
        case let (.error(lMessage, lRecoverable), .error(rMessage, rRecoverable)):
            return lMessage == rMessage && lRecoverable == rRecoverable
        default:
            return false
        }
    }
}
