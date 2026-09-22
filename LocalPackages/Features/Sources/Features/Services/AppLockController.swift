import Foundation
import Observation
import Domain

/// How a request to change the lock setting ended (§11).
public enum AppLockChangeResult: Sendable, Equatable {
    /// The setting was changed and persisted.
    case applied
    /// Turning the lock on was refused: the device has no usable biometric.
    case unavailable(BiometryKind)
    /// The authentication prompt was cancelled or failed.
    case refused(AppLockOutcome)
    /// A prompt is already in flight.
    case busy
}

/// Holds the app's locked state and drives authentication (§11).
@MainActor
@Observable
public final class AppLockController {
    /// Performs device-owner authentication.
    private let authenticator: any AppLockAuthenticating
    /// User preferences, whose `appLockEnabled` and grace period drive this.
    private let settings: AppSettings
    /// Persists a change to the lock setting.
    private let settingsStore: any AppSettingsStore

    /// Whether the app is currently locked.
    public private(set) var isLocked = false
    /// Whether an authentication prompt is in flight.
    public private(set) var isAuthenticating = false
    /// Whether the last attempt failed, so the lock screen can offer to retry.
    public private(set) var didFail = false
    /// How the last attempt ended, so the lock screen can say why it failed.
    public private(set) var lastOutcome: AppLockOutcome?
    /// What the device can authenticate with, once probed.
    public private(set) var availability: AppLockAvailability?
    /// When the app last left the foreground.
    private var backgroundedAt: Date?

    /// Creates the controller.
    /// - Parameters:
    ///   - authenticator: Performs authentication.
    ///   - settings: The shared preferences object.
    ///   - settingsStore: Persists a change to the lock setting.
    public init(
        authenticator: any AppLockAuthenticating,
        settings: AppSettings,
        settingsStore: any AppSettingsStore
    ) {
        self.authenticator = authenticator
        self.settings = settings
        self.settingsStore = settingsStore
    }

    /// Whether the lock is switched on.
    public var isEnabled: Bool { settings.appLockEnabled }

    /// How long a trip away is forgiven.
    public var graceSeconds: Int { settings.appLockGraceSeconds }

    /// Reads what the device can authenticate with, for the Settings card's copy.
    public func refreshAvailability() async {
        availability = await authenticator.availability()
    }

    /// Locks the app if the lock is on, at cold launch (§11).
    public func lockOnLaunchIfNeeded() {
        isLocked = AppLockPolicy.shouldLockOnLaunch(isEnabled: settings.appLockEnabled)
    }

    /// Records that the app has left the foreground.
    ///
    /// Ignored while a prompt is in flight. The system authentication sheet drives the
    /// scene inactive and back, which is otherwise indistinguishable from the user
    /// leaving and returning: stamping it here re-locked the app the instant it
    /// unlocked, which prompted again, which stamped again — the endless prompt loop.
    public func sceneWillResignActive() {
        guard !isAuthenticating else { return }
        backgroundedAt = .now
    }

    /// Re-locks on return to the foreground once the grace period has elapsed, and
    /// prompts once if it did (§11).
    ///
    /// Only a lock that engages *here* prompts. A lock screen already standing after a
    /// refusal waits for the user to tap Unlock instead, so a cancelled prompt cannot
    /// re-present itself.
    public func sceneDidBecomeActive() async {
        // Already locked means a lock screen is standing, from a refusal or from a
        // prompt still in flight. Either way this is the sheet coming down, not a
        // return from the background, and it must not raise a second prompt.
        guard !isLocked, !isAuthenticating else { return }
        let shouldLock = AppLockPolicy.shouldLockOnForeground(
            isEnabled: settings.appLockEnabled,
            backgroundedAt: backgroundedAt,
            graceSeconds: settings.appLockGraceSeconds
        )
        guard shouldLock else { return }
        isLocked = true
        didFail = false
        lastOutcome = nil
        await unlock()
    }

    /// Whether the app switcher snapshot should be covered (§11).
    /// - Parameter isActive: Whether the scene is currently active.
    /// - Returns: `true` when the blur overlay should show.
    public func shouldObscureSnapshot(isActive: Bool) -> Bool {
        AppLockPolicy.shouldObscureSnapshot(isEnabled: settings.appLockEnabled, isActive: isActive)
    }

    /// Asks the user to unlock.
    ///
    /// A device that can no longer authenticate at all — no enrolled biometric and no
    /// passcode — opens and switches the lock off rather than stranding the user
    /// outside their own data.
    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        didFail = false
        let outcome = await authenticator.authenticate(
            reason: .returnedToForeground,
            biometricsOnly: AppLockPolicy.usesBiometricsOnly(for: .returnedToForeground)
        )
        isAuthenticating = false
        lastOutcome = outcome

        switch outcome {
        case .success:
            isLocked = false
            backgroundedAt = nil
        case .unavailable:
            let availability = await authenticator.availability()
            self.availability = availability
            if availability.hasNoDeviceSecurity {
                isLocked = false
                backgroundedAt = nil
                settings.appLockEnabled = false
                settingsStore.save(settings)
            } else {
                didFail = true
            }
        case .cancelled, .failed, .lockedOut:
            didFail = true
        }
    }

    /// Turns the lock on or off.
    ///
    /// **Both directions authenticate** (§11). Disabling, so nobody holding an unlocked
    /// phone can switch the protection off. Enabling, so the lock is never armed with a
    /// biometric that turns out not to work on this device — that prompt refuses the
    /// passcode fallback, since a passcode entry would not prove Face ID works.
    ///
    /// - Parameter enabled: What the user is switching it to.
    /// - Returns: Whether the change was applied, and why not if it was refused.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> AppLockChangeResult {
        guard !isAuthenticating else { return .busy }
        let reason: AppLockReason = enabled ? .enablingLock : .disablingLock

        if AppLockPolicy.requiresAuthentication(toChangeFrom: settings.appLockEnabled, to: enabled) {
            if enabled {
                let availability = await authenticator.availability()
                self.availability = availability
                guard AppLockPolicy.canEnable(availability) else {
                    return .unavailable(availability.biometry)
                }
            }
            isAuthenticating = true
            let outcome = await authenticator.authenticate(
                reason: reason, biometricsOnly: AppLockPolicy.usesBiometricsOnly(for: reason)
            )
            isAuthenticating = false
            guard outcome == .success else { return .refused(outcome) }
        }

        settings.appLockEnabled = enabled
        settingsStore.save(settings)
        return .applied
    }

    /// Changes how long a trip away is forgiven.
    /// - Parameter seconds: The grace period.
    public func setGraceSeconds(_ seconds: Int) {
        settings.appLockGraceSeconds = seconds
        settingsStore.save(settings)
    }
}
