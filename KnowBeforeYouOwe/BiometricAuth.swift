import Foundation
import LocalAuthentication

enum BiometricType {
    case none
    case faceID
    case touchID

    var title: String {
        switch self {
        case .none:
            return "Biometrics"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        }
    }
}

enum BiometricAuthError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Biometric unlock is not available on this device."
        }
    }
}

enum BiometricAuth {
    static func availableType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricAuthError.unavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: authError ?? BiometricAuthError.unavailable)
                }
            }
        }
    }
}
