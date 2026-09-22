import Foundation
import Testing
@testable import Features
import Domain

/// Phase 13 acceptance criterion: the app lock engages on foreground, prompts exactly
/// once, and changing the setting requires authenticating first (§11).
@MainActor
@Suite("App lock")
struct AppLockTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The authenticator fake.
        let authenticator: FakeLockAuthenticator
        /// The shared preferences object.
        let settings: AppSettings
        /// The controller under test.
        let controller: AppLockController
    }

    /// Builds a controller with the lock switched on or off.
    /// - Parameter enabled: Whether the lock starts on.
    /// - Returns: The harness.
    private func makeController(enabled: Bool) -> Harness {
        let authenticator = FakeLockAuthenticator()
        let settings = AppSettings()
        settings.appLockEnabled = enabled
        return Harness(
            authenticator: authenticator,
            settings: settings,
            controller: AppLockController(
                authenticator: authenticator,
                settings: settings,
                settingsStore: FakeSettingsStore()
            )
        )
    }

    @Test("A cold launch locks when the lock is on")
    func coldLaunchLocks() {
        let controller = makeController(enabled: true).controller

        controller.lockOnLaunchIfNeeded()

        #expect(controller.isLocked)
    }

    @Test("A cold launch does not lock when the lock is off")
    func coldLaunchWithoutLock() {
        let controller = makeController(enabled: false).controller

        controller.lockOnLaunchIfNeeded()

        #expect(controller.isLocked == false)
    }

    @Test("Returning to the foreground engages the lock and prompts once")
    func foregroundEngagesLock() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)
        controller.lockOnLaunchIfNeeded()
        await controller.unlock()
        #expect(controller.isLocked == false)
        authenticator.requests.removeAll()
        authenticator.outcomes = [.cancelled]

        controller.sceneWillResignActive()
        await controller.sceneDidBecomeActive()

        #expect(controller.isLocked, "the default grace of zero locks immediately")
        #expect(authenticator.requests.count == 1, "the lock prompts exactly once when it engages")
    }

    @Test("A grace period forgives a short trip away")
    func gracePeriodForgivesShortTrip() async {
        let harness = makeController(enabled: true)
        let (settings, controller) = (harness.settings, harness.controller)
        settings.appLockGraceSeconds = 300
        controller.lockOnLaunchIfNeeded()
        await controller.unlock()

        controller.sceneWillResignActive()
        await controller.sceneDidBecomeActive()

        #expect(controller.isLocked == false)
    }

    /// The regression this whole change exists for: the system sheet drives the scene
    /// inactive and back, which used to re-lock and re-prompt forever.
    @Test("The prompt's own scene churn does not re-lock the app")
    func promptChurnDoesNotRelock() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)
        // A real LAContext sheet resigns the scene while it is up.
        authenticator.onAuthenticate = { controller.sceneWillResignActive() }
        controller.lockOnLaunchIfNeeded()

        await controller.unlock()
        // The sheet comes down, and SwiftUI reports the scene active again.
        await controller.sceneDidBecomeActive()

        #expect(controller.isLocked == false, "the app stays open after a successful unlock")
        #expect(authenticator.requests.count == 1, "no second prompt is raised")
    }

    @Test("A refused unlock does not re-prompt when the sheet's dismissal reactivates the scene")
    func refusalDoesNotAutoRetry() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)
        authenticator.onAuthenticate = { controller.sceneWillResignActive() }
        authenticator.outcomes = [.cancelled]
        controller.lockOnLaunchIfNeeded()

        await controller.unlock()
        await controller.sceneDidBecomeActive()
        await controller.sceneDidBecomeActive()

        #expect(controller.isLocked, "a cancelled prompt leaves the lock screen up")
        #expect(controller.didFail)
        #expect(authenticator.requests.count == 1, "the user taps Unlock; nothing retries for them")
    }

    @Test("Successful authentication unlocks; a refusal keeps it locked")
    func authenticationOutcomes() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)
        controller.lockOnLaunchIfNeeded()
        authenticator.outcomes = [.failed]

        await controller.unlock()
        #expect(controller.isLocked)
        #expect(controller.didFail)
        #expect(controller.lastOutcome == .failed)

        authenticator.outcomes = [.success]
        await controller.unlock()
        #expect(controller.isLocked == false)
        #expect(controller.didFail == false)
    }

    @Test("Unlocking allows the passcode fallback")
    func unlockingAllowsPasscodeFallback() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)
        controller.lockOnLaunchIfNeeded()

        await controller.unlock()

        #expect(authenticator.requests == [
            RecordedAuthentication(reason: .returnedToForeground, biometricsOnly: false)
        ])
    }

    @Test("A device that can no longer authenticate opens and switches the lock off")
    func lostDeviceSecurityDoesNotStrandTheUser() async {
        let harness = makeController(enabled: true)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)
        authenticator.deviceAvailability = AppLockAvailability(
            biometry: .none, isEnrolled: false, hasPasscode: false
        )
        authenticator.outcomes = [.unavailable(.none)]
        controller.lockOnLaunchIfNeeded()

        await controller.unlock()

        #expect(controller.isLocked == false)
        #expect(settings.appLockEnabled == false, "the lock turns itself off rather than stranding")
    }

    @Test("The switcher snapshot is obscured whenever the scene is not active")
    func snapshotIsObscured() {
        let controller = makeController(enabled: true).controller

        #expect(controller.shouldObscureSnapshot(isActive: false))
        #expect(controller.shouldObscureSnapshot(isActive: true) == false)
    }

    @Test("Turning the lock off requires authenticating first")
    func disablingRequiresAuthentication() async {
        let harness = makeController(enabled: true)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)
        authenticator.outcomes = [.cancelled]

        let result = await controller.setEnabled(false)

        #expect(result == .refused(.cancelled))
        #expect(settings.appLockEnabled, "the lock stays on when authentication fails")
        #expect(authenticator.requests == [
            RecordedAuthentication(reason: .disablingLock, biometricsOnly: false)
        ])
    }

    @Test("Turning the lock off succeeds once authenticated")
    func disablingSucceedsWhenAuthenticated() async {
        let harness = makeController(enabled: true)
        let (settings, controller) = (harness.settings, harness.controller)

        let result = await controller.setEnabled(false)

        #expect(result == .applied)
        #expect(settings.appLockEnabled == false)
    }

    @Test("Turning the lock on verifies the biometric itself, with no passcode fallback")
    func enablingVerifiesBiometrics() async {
        let harness = makeController(enabled: false)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)

        let result = await controller.setEnabled(true)

        #expect(result == .applied)
        #expect(settings.appLockEnabled)
        #expect(authenticator.requests == [
            RecordedAuthentication(reason: .enablingLock, biometricsOnly: true)
        ])
    }

    @Test("A cancelled verification leaves the lock off")
    func enablingIsRefusedWhenVerificationFails() async {
        let harness = makeController(enabled: false)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)
        authenticator.outcomes = [.cancelled]

        let result = await controller.setEnabled(true)

        #expect(result == .refused(.cancelled))
        #expect(settings.appLockEnabled == false)
    }

    @Test("The lock cannot be turned on without an enrolled biometric")
    func enablingNeedsEnrolledBiometry() async {
        let harness = makeController(enabled: false)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)
        authenticator.deviceAvailability = AppLockAvailability(
            biometry: .none, isEnrolled: false, hasPasscode: true
        )

        let result = await controller.setEnabled(true)

        #expect(result == .unavailable(.none))
        #expect(settings.appLockEnabled == false)
        #expect(authenticator.requests.isEmpty, "there is no point prompting for a missing biometric")
    }

    @Test("An unenrolled biometric is refused too")
    func enablingNeedsBiometryActuallySetUp() async {
        let harness = makeController(enabled: false)
        let (authenticator, settings, controller) =
            (harness.authenticator, harness.settings, harness.controller)
        authenticator.deviceAvailability = AppLockAvailability(
            biometry: .faceID, isEnrolled: false, hasPasscode: true
        )

        let result = await controller.setEnabled(true)

        #expect(result == .unavailable(.faceID))
        #expect(settings.appLockEnabled == false)
        #expect(authenticator.requests.isEmpty)
    }

    @Test("Unlocking an app that is not locked raises no prompt")
    func unlockingWhileOpenDoesNothing() async {
        let harness = makeController(enabled: true)
        let (authenticator, controller) = (harness.authenticator, harness.controller)

        await controller.unlock()

        #expect(authenticator.requests.isEmpty)
    }
}
