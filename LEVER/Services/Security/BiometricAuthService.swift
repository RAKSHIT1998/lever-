import Foundation
import LocalAuthentication

struct BiometricAuthService: BiometricAuthenticating {
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Deterministic stand-in for previews, tests and UI tests.
struct AlwaysAllowBiometrics: BiometricAuthenticating {
    var isAvailable: Bool { true }
    var biometryName: String { "Face ID" }
    func authenticate(reason: String) async -> Bool { true }
}
