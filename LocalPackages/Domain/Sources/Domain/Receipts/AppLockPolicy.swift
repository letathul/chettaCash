import Foundation

/// Why the app is asking the user to authenticate (§11).
public enum AppLockReason: String, Sendable {
    /// The app is starting from cold.
    case coldLaunch
    /// The app has returned to the foreground after the grace period.
    case returnedToForeground
    /// The user is turning the lock on, which verifies biometrics work first.
    case enablingLock
    /// The user is turning the lock off, which requires authenticating first.
    case disablingLock
}

/// Which biometric the device offers (§11).
public enum BiometryKind: String, Sendable, Equatable {
    /// No biometric hardware.
    case none
    /// Touch ID.
    case touchID
    /// Face ID.
    case faceID
    /// Optic ID.
    case opticID

    /// How the biometric is named in user-facing copy.
    public var displayName: String {
        switch self {
        case .none: return "a passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
}

/// What the device can currently authenticate with (§11).
public struct AppLockAvailability: Sendable, Equatable {
    /// The biometric hardware the device has.
    public let biometry: BiometryKind
    /// Whether that biometric is enrolled and usable right now.
    public let isEnrolled: Bool
    /// Whether a device passcode is set, so device-owner authentication is possible.
    public let hasPasscode: Bool

    /// Creates an availability snapshot.
    /// - Parameters:
    ///   - biometry: The biometric hardware the device has.
    ///   - isEnrolled: Whether that biometric is usable right now.
    ///   - hasPasscode: Whether a device passcode is set.
    public init(biometry: BiometryKind, isEnrolled: Bool, hasPasscode: Bool) {
        self.biometry = biometry
        self.isEnrolled = isEnrolled
        self.hasPasscode = hasPasscode
    }

    /// A device with no security at all: no enrolled biometric and no passcode.
    ///
    /// Such a device cannot authenticate, so holding the lock closed would strand the
    /// user outside their own data.
    public var hasNoDeviceSecurity: Bool { !isEnrolled && !hasPasscode }
}

/// How an authentication attempt ended (§11).
///
/// Richer than a `Bool` because the Settings card and the lock screen have to explain
/// *why* a request did not succeed — "you cancelled" and "this device has no Face ID"
/// call for different copy and different recovery.
public enum AppLockOutcome: Sendable, Equatable {
    /// The user authenticated.
    case success
    /// The user or the system dismissed the prompt.
    case cancelled
    /// The presented credential did not match.
    case failed
    /// The device cannot authenticate: no hardware, not enrolled, or no passcode.
    case unavailable(BiometryKind)
    /// Too many failures; biometrics need a device unlock before they work again.
    case lockedOut
}

/// Decides when the app should be locked (§11).
///
/// Face ID or Touch ID, falling back to the device passcode. The lock engages on cold
/// launch and on return to the foreground once the grace period has elapsed.
public enum AppLockPolicy {

    /// Whether a cold launch should be locked.
    /// - Parameter isEnabled: Whether the user has the lock turned on.
    /// - Returns: `true` when the app should start locked.
    public static func shouldLockOnLaunch(isEnabled: Bool) -> Bool {
        isEnabled
    }

    /// Whether returning to the foreground should re-lock the app.
    ///
    /// With the default grace of zero seconds this locks immediately, which is what
    /// §11 specifies. A longer grace lets the user flick to another app and back
    /// without re-authenticating.
    ///
    /// A `nil` `backgroundedAt` means the app never left the foreground, so it must
    /// **not** lock: the only reason the scene went inactive was something drawn over
    /// it, such as our own authentication sheet. Locking here is what produced the
    /// endless prompt loop — the cold-launch case is covered by
    /// ``shouldLockOnLaunch(isEnabled:)`` instead.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the user has the lock turned on.
    ///   - backgroundedAt: When the app last left the foreground, if it has.
    ///   - now: The moment it is returning.
    ///   - graceSeconds: How long a trip away is forgiven.
    /// - Returns: `true` when the app should lock.
    public static func shouldLockOnForeground(
        isEnabled: Bool,
        backgroundedAt: Date?,
        now: Date = .now,
        graceSeconds: Int
    ) -> Bool {
        guard isEnabled else { return false }
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= Double(graceSeconds)
    }

    /// Whether the app switcher's snapshot should be obscured (§11).
    ///
    /// Covered while inactive, not just while backgrounded: the snapshot iOS takes
    /// for the switcher is captured during the inactive phase, so waiting for
    /// `background` would photograph the user's balances first.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the user has the lock turned on.
    ///   - isActive: Whether the scene is currently active.
    /// - Returns: `true` when the blur overlay should be shown.
    public static func shouldObscureSnapshot(isEnabled: Bool, isActive: Bool) -> Bool {
        isEnabled && !isActive
    }

    /// Whether changing the lock setting needs authentication first (§11).
    ///
    /// Both directions authenticate. Disabling, so nobody holding an unlocked phone
    /// can switch the protection off; enabling, so the lock is never armed with a
    /// biometric that turns out not to work on this device.
    ///
    /// - Parameters:
    ///   - current: Whether the lock is currently on.
    ///   - desired: What the user is switching it to.
    /// - Returns: `true` when the change must be authenticated.
    public static func requiresAuthentication(toChangeFrom current: Bool, to desired: Bool) -> Bool {
        current != desired
    }

    /// Whether a request should be satisfied by biometrics alone, with no passcode
    /// fallback (§11).
    ///
    /// Only when turning the lock on: the point of that prompt is to prove the
    /// biometric itself works, which a passcode entry would not establish. Every other
    /// prompt allows the fallback so a biometric failure cannot strand the user.
    ///
    /// - Parameter reason: Why the app is asking.
    /// - Returns: `true` when only a biometric will do.
    public static func usesBiometricsOnly(for reason: AppLockReason) -> Bool {
        reason == .enablingLock
    }

    /// Whether the lock may be switched on at all (§11).
    ///
    /// - Parameter availability: What the device can authenticate with.
    /// - Returns: `true` when an enrolled biometric is present to verify.
    public static func canEnable(_ availability: AppLockAvailability) -> Bool {
        availability.biometry != .none && availability.isEnrolled
    }
}

/// Performs device-owner authentication (§11).
///
/// Declared here so `Features` can ask without importing `LocalAuthentication`, and
/// so tests can substitute a fake rather than driving a real biometric prompt.
public protocol AppLockAuthenticating: Sendable {
    /// What the device can currently authenticate with.
    ///
    /// - Returns: The biometric on offer, whether it is enrolled, and whether a
    ///   passcode is set.
    func availability() async -> AppLockAvailability

    /// Asks the user to authenticate.
    /// - Parameters:
    ///   - reason: Why the app is asking, shown in the system prompt.
    ///   - biometricsOnly: When `true`, only a biometric satisfies the request and no
    ///     passcode fallback is offered.
    /// - Returns: How the attempt ended.
    func authenticate(reason: AppLockReason, biometricsOnly: Bool) async -> AppLockOutcome
}
