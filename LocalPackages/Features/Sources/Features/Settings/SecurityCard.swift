import SwiftUI
import Domain

/// The Security card in Settings (§7.6 item 4, §11).
///
/// **Both directions authenticate**: disabling, so nobody holding an unlocked phone can
/// switch the protection off; enabling, so the lock is never armed with a biometric
/// that turns out not to work on this device.
struct SecurityCard: View {
    /// The lock's controller.
    let controller: AppLockController

    /// How the last attempt to change the setting ended, when it was refused.
    @State private var lastResult: AppLockChangeResult?

    /// The grace periods offered.
    private let graceOptions = [0, 30, 60, 300]

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Security").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    ToggleRow(
                        title: "Require \(biometryName)",
                        isOn: Binding(
                            get: { controller.isEnabled },
                            set: { desired in
                                guard !controller.isAuthenticating else { return }
                                Task { lastResult = await controller.setEnabled(desired) }
                            }
                        )
                    ) { isOn in
                        isOn
                            ? "Locks when you leave the app, and hides it in the app switcher"
                            : "Anyone with your phone can open Chetta Cash"
                    }
                    if let message = refusalMessage {
                        Text(message)
                            .font(Typography.errorCaption)
                            .foregroundStyle(Palette.negativeRed)
                    }
                    if controller.isEnabled {
                        Divider().overlay(Palette.borderSubtle)
                        OptionPickerRow(
                            label: "Lock after",
                            options: graceOptions,
                            selection: Binding(
                                get: { controller.graceSeconds },
                                set: { controller.setGraceSeconds($0) }
                            ),
                            display: graceLabel,
                            subtitle: graceDetail
                        )
                    }
                }
            }
        }
        .task { await controller.refreshAvailability() }
    }

    /// How the device's biometric is named in the row's title and messages.
    private var biometryName: String {
        controller.availability?.biometry.displayName ?? "Face ID"
    }

    /// Why the last change was refused, or `nil` when it was applied.
    private var refusalMessage: String? {
        switch lastResult {
        case .applied, .busy, .none:
            return nil
        case .unavailable(.none):
            return "This device has no Face ID or Touch ID, so the lock cannot be turned on."
        case .unavailable:
            return "Set \(biometryName) up in iPhone Settings to use the app lock."
        case .refused(.lockedOut):
            return "\(biometryName) is locked. Unlock your iPhone with your passcode, then try again."
        case .refused:
            return "\(biometryName) is needed to change the lock."
        }
    }

    /// The label for a grace period.
    /// - Parameter seconds: The grace period.
    /// - Returns: The label.
    private func graceLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Immediately"
        case 30: return "30 seconds"
        case 60: return "1 minute"
        default: return "5 minutes"
        }
    }

    /// What a grace period means in practice, shown beneath its label in the picker.
    /// - Parameter seconds: The grace period.
    /// - Returns: The explanatory line.
    private func graceDetail(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "Ask every time you come back to the app"
        case 30: return "A short grace for switching apps"
        case 60: return "Stays open for a minute in the background"
        default: return "Stays open for five minutes in the background"
        }
    }
}
