import Foundation
import Domain

/// The Settings view model's feature-flag switches (§7.6).
///
/// Split from ``SettingsViewModel`` to keep each file within the 300-line limit.
extension SettingsViewModel {

    /// The flags the menu offers, in a stable order.
    public var featureFlags: [FeatureFlag] { FeatureFlag.menuOrder }

    /// Reports whether an under-development feature is switched on.
    /// - Parameter flag: The feature to check.
    /// - Returns: `true` when the feature is on.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        settings.isEnabled(flag)
    }

    /// Switches an under-development feature on or off and persists the change.
    ///
    /// Writes immediately rather than on leaving the screen: a flag is flipped to see
    /// what it does, and the app is often force-quit before the screen is dismissed.
    ///
    /// - Parameters:
    ///   - flag: The feature to switch.
    ///   - enabled: Whether it should be on.
    public func setFeature(_ flag: FeatureFlag, enabled: Bool) {
        settings.setFeature(flag, enabled: enabled)
        persistSettings()
    }
}
