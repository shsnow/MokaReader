// WizardJVMRunner — Apache License 2.0

import Foundation

public enum JVMRuntimeError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case startupFailed(String)
    case dispatchFailed(status: Int, message: String)
    case invalidUTF8Response
    case encodingFailed
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
            case .invalidConfiguration(let message):
                return "Invalid JVM configuration: \(message)"
            case .startupFailed(let message):
                return "The Java VM could not start: \(message)"
            case .dispatchFailed(_, let message):
                return message
            case .invalidUTF8Response:
                return "The extension host returned a malformed response"
            case .encodingFailed:
                return "The request could not be encoded"
            case .decodingFailed(let message):
                return "The response could not be decoded: \(message)"
        }
    }
}
