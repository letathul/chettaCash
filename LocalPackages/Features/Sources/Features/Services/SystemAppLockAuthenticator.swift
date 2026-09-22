import Foundation
import LocalAuthentication
import Domain

/// Authenticates with Face ID, Touch ID or the device passcode (§11).
///
/// Unlocking uses `.deviceOwnerAuthentication`, so a biometric that fails or is locked
/// out falls back to the passcode instead of shutting the user out of their own data.
/// Turning the lock *on* asks for `.deviceOwnerAuthenticationWithBiometrics` instead:
/// that prompt exists to prove the biometric works, which a passcode entry would not
/// establish.
///
/// The app's `Info.plist` must carry `NSFaceIDUsageDescription`. Without it iOS will
/// not offer Face ID at all — the prompt drops straight to the passcode keypad — and
/// evaluating a biometric policy terminates the app on device. `canEvaluatePolicy`
/// still returns `true` in that state, so it is not a guard against this.
///
/// Stateless: `LAContext` is single-use and not `Sendable`, so a fresh one is made
/// per call.
public struct SystemAppLockAuthenticator: AppLockAuthenticating {

    /// Creates the authenticator.
    public init() {}

    /// What the device can currently authenticate with.
    ///
    /// - Returns: The biometric on offer, whether it is enrolled, and whether a
    ///   passcode is set.
    public func availability() async -> AppLockAvailability {
        let context = LAContext()
        // `biometryType` is only populated once a policy has been evaluated for
        // feasibility, so probe first and read the type afterwards.
        let isEnrolled = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        )
        let biometry = Self.kind(of: context.biometryType)
        let hasPasscode = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        return AppLockAvailability(
            biometry: biometry, isEnrolled: isEnrolled, hasPasscode: hasPasscode
        )
    }

    /// Asks the user to authenticate.
    /// - Parameters:
    ///   - reason: Why the app is asking, shown in the system prompt.
    ///   - biometricsOnly: When `true`, only a biometric satisfies the request and no
    ///     passcode fallback is offered.
    /// - Returns: How the attempt ended.
    public func authenticate(
        reason: AppLockReason, biometricsOnly: Bool
    ) async -> AppLockOutcome {
        let context = LAContext()
        let policy: LAPolicy = biometricsOnly
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        var probeError: NSError?
        guard context.canEvaluatePolicy(policy, error: &probeError) else {
            return Self.outcome(for: probeError, biometry: Self.kind(of: context.biometryType))
        }

        do {
            let granted = try await context.evaluatePolicy(
                policy, localizedReason: reason.prompt
            )
            return granted ? .success : .failed
        } catch {
            return Self.outcome(for: error, biometry: Self.kind(of: context.biometryType))
        }
    }

    /// Maps a `LocalAuthentication` failure onto the domain outcome.
    /// - Parameters:
    ///   - error: The error `LocalAuthentication` reported, if any.
    ///   - biometry: The biometric the context offered.
    /// - Returns: The matching outcome.
    private static func outcome(for error: (any Error)?, biometry: BiometryKind) -> AppLockOutcome {
        guard let code = (error as? NSError).flatMap({ LAError.Code(rawValue: $0.code) }) else {
            return .failed
        }
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .biometryLockout:
            return .lockedOut
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            return .unavailable(biometry)
        default:
            return .failed
        }
    }

    /// Maps `LABiometryType` onto the domain's biometric kind.
    /// - Parameter type: What the context reported.
    /// - Returns: The matching kind, or ``BiometryKind/none`` for anything unknown.
    private static func kind(of type: LABiometryType) -> BiometryKind {
        switch type {
        case .touchID: return .touchID
        case .faceID: return .faceID
        case .opticID: return .opticID
        default: return .none
        }
    }
}

/// The wording shown in the system authentication prompt.
extension AppLockReason {
    /// The sentence iOS displays alongside the prompt.
    var prompt: String {
        switch self {
        case .coldLaunch, .returnedToForeground:
            return "Unlock Chetta Cash"
        case .enablingLock:
            return "Confirm it is you to turn the app lock on"
        case .disablingLock:
            return "Confirm it is you before turning the lock off"
        }
    }
}
