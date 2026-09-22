import Foundation
import Domain

/// Persists ``AppSettings`` in `UserDefaults`.
///
/// Settings are a handful of scalars rather than records, so they do not belong in
/// the SwiftData store and are not part of the backup archive (§9.4).
@MainActor
public struct UserDefaultsAppSettingsStore: AppSettingsStore {
    /// Where values are read from and written to.
    private let defaults: UserDefaults

    /// Keys used in `UserDefaults`, namespaced to avoid collisions.
    private enum Key {
        /// Key for the display currency code.
        static let currencyCode = "settings.currencyCode"
        /// Key for the default reminder lead time.
        static let defaultReminderLeadTime = "settings.defaultReminderLeadTime"
        /// Key for the backup interval.
        static let backupInterval = "settings.backupInterval"
        /// Key for the receipt cache cap.
        static let receiptCacheCapMB = "settings.receiptCacheCapMB"
        /// Key for whether the app lock is enabled.
        static let appLockEnabled = "settings.appLockEnabled"
        /// Key for the app lock grace period.
        static let appLockGraceSeconds = "settings.appLockGraceSeconds"
        /// Key for whether onboarding has run.
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        /// Key for whether the starter-account note is still owed.
        static let showsStarterAccountNote = "settings.showsStarterAccountNote"
        /// Whether the Siri tip has been dismissed.
        static let hasDismissedShortcutTip = "settings.hasDismissedShortcutTip"
        /// Key for the under-development features that are switched on.
        static let enabledFeatureFlags = "settings.enabledFeatureFlags"
    }

    /// Creates a store.
    /// - Parameter defaults: Where to read and write. Defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Applies stored values to the given settings object.
    ///
    /// Any key that has never been written leaves that property at its §5.1 default.
    ///
    /// - Parameter settings: The settings to populate.
    public func load(into settings: AppSettings) {
        if let code = defaults.string(forKey: Key.currencyCode) {
            settings.currencyCode = code
        }
        if let raw = defaults.string(forKey: Key.defaultReminderLeadTime),
           let value = ReminderLeadTime(rawValue: raw) {
            settings.defaultReminderLeadTime = value
        }
        if let raw = defaults.string(forKey: Key.backupInterval),
           let value = BackupInterval(rawValue: raw) {
            settings.backupInterval = value
        }
        if defaults.object(forKey: Key.receiptCacheCapMB) != nil {
            settings.receiptCacheCapMB = defaults.integer(forKey: Key.receiptCacheCapMB)
        }
        if defaults.object(forKey: Key.appLockGraceSeconds) != nil {
            settings.appLockGraceSeconds = defaults.integer(forKey: Key.appLockGraceSeconds)
        }
        settings.appLockEnabled = defaults.bool(forKey: Key.appLockEnabled)
        settings.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        settings.showsStarterAccountNote = defaults.bool(forKey: Key.showsStarterAccountNote)
        settings.hasDismissedShortcutTip = defaults.bool(forKey: Key.hasDismissedShortcutTip)
        // `if let` rather than a bare read: an unwritten key must leave the defaults from
        // `FeatureFlag.isEnabledByDefault` alone. `compactMap` drops raw values whose flag
        // a later build removed, so a retired flag cleans itself up on the next save.
        if let raw = defaults.stringArray(forKey: Key.enabledFeatureFlags) {
            settings.enabledFeatureFlags = Set(raw.compactMap(FeatureFlag.init(rawValue:)))
        }
    }

    /// Persists the given settings.
    /// - Parameter settings: The settings to store.
    public func save(_ settings: AppSettings) {
        defaults.set(settings.currencyCode, forKey: Key.currencyCode)
        defaults.set(settings.defaultReminderLeadTime.rawValue, forKey: Key.defaultReminderLeadTime)
        defaults.set(settings.backupInterval.rawValue, forKey: Key.backupInterval)
        defaults.set(settings.receiptCacheCapMB, forKey: Key.receiptCacheCapMB)
        defaults.set(settings.appLockEnabled, forKey: Key.appLockEnabled)
        defaults.set(settings.appLockGraceSeconds, forKey: Key.appLockGraceSeconds)
        defaults.set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        defaults.set(settings.showsStarterAccountNote, forKey: Key.showsStarterAccountNote)
        defaults.set(settings.hasDismissedShortcutTip, forKey: Key.hasDismissedShortcutTip)
        defaults.set(
            settings.enabledFeatureFlags.map(\.rawValue).sorted(),
            forKey: Key.enabledFeatureFlags
        )
    }
}
