import SwiftUI
import Domain

/// Wraps the app in the §11 lock: an unlock screen, and a blur over the switcher
/// snapshot.
public struct AppLockGate<Content: View>: View {
    /// The lock's controller.
    @Bindable private var controller: AppLockController
    /// The app's content.
    @ViewBuilder private let content: () -> Content

    /// The current scene phase.
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the gate.
    /// - Parameters:
    ///   - controller: The lock's controller.
    ///   - content: The app's content.
    public init(
        controller: AppLockController,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.controller = controller
        self.content = content
    }

    /// The view body.
    public var body: some View {
        ZStack {
            content()
            if controller.isLocked {
                LockScreen(controller: controller)
                    .transition(.opacity)
            }
            // Covered while inactive, not just while backgrounded: iOS captures the
            // switcher snapshot during the inactive phase (§11).
            if controller.shouldObscureSnapshot(isActive: scenePhase == .active) {
                PrivacyCurtain()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: controller.isLocked)
        .task {
            controller.lockOnLaunchIfNeeded()
            guard controller.isLocked else { return }
            await controller.refreshAvailability()
            await controller.unlock()
        }
        // A thin forward: the controller owns the re-lock decision and the single
        // prompt that follows it, so the system sheet's own inactive/active churn
        // cannot be mistaken for the user leaving and returning (§11).
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await controller.sceneDidBecomeActive() }
            case .inactive, .background:
                controller.sceneWillResignActive()
            @unknown default:
                break
            }
        }
    }
}

/// The blur that stands in for the app in the switcher (§11).
struct PrivacyCurtain: View {
    /// The view body.
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Palette.brandPurple)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The unlock screen shown while the app is locked (§11).
struct LockScreen: View {
    /// The lock's controller.
    let controller: AppLockController

    /// The view body.
    var body: some View {
        ZStack {
            Palette.appBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.brandPurple)
                    .accessibilityHidden(true)
                Text("Chetta Cash is locked")
                    .font(Typography.screenTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                if controller.didFail {
                    Text(failureMessage)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.negativeRed)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await controller.unlock() }
                } label: {
                    Text(controller.isAuthenticating ? "Unlocking…" : "Unlock")
                        .font(Typography.rowPrimary.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Palette.brandPurple, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(controller.isAuthenticating)
            }
            .padding(24)
        }
    }

    /// What to tell the user after a failed attempt.
    private var failureMessage: String {
        switch controller.lastOutcome {
        case .cancelled:
            return "\(biometryName) was cancelled."
        case .lockedOut:
            return "\(biometryName) is locked. Unlock your iPhone with your passcode, then try again."
        case .unavailable:
            return "\(biometryName) is not available on this device right now."
        default:
            return "Authentication did not succeed."
        }
    }

    /// How the device's biometric is named in the failure copy.
    private var biometryName: String {
        let biometry = controller.availability?.biometry ?? .faceID
        return biometry == .none ? "Authentication" : biometry.displayName
    }
}
