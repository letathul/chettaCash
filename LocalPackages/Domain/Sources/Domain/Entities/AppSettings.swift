import Foundation
import Observation

/// User-facing preferences (§5.1).
///
/// The currency code is a display label only. It changes which symbol and code are
/// rendered, applied uniformly to every amount. There is no per-account currency,
/// no exchange rate and no home-currency concept — do not build conversion logic.
@MainActor
@Observable
public final class AppSettings {
    /// ISO 4217 code used to render every amount.
    public var currencyCode: String = "USD"
    /// Lead time used when a reminder is set to ``ReminderLeadTime/useDefault``.
    public var defaultReminderLeadTime: ReminderLeadTime = .threeDaysBefore
    /// How often a backup archive is written.
    public var backupInterval: BackupInterval = .weekly
    /// Size cap for the local receipt cache, in megabytes.
    public var receiptCacheCapMB: Int = 200
    /// Whether Face ID or the device passcode gates the app.
    public var appLockEnabled: Bool = false
    /// Seconds in the background before the lock re-engages.
    public var appLockGraceSeconds: Int = 0
    /// Whether onboarding has run.
    public var hasCompletedOnboarding: Bool = false
    /// Whether the user has dismissed the Siri tip on the Ledger (§10).
    ///
    /// The tip teaches the Add Expense phrase. Once dismissed it stays dismissed —
    /// a tip that comes back is an advert.
    public var hasDismissedShortcutTip: Bool = false
    /// Whether the Dashboard still owes the user the starter-account explanation.
    ///
    /// Set when ``StarterAccountPolicy`` supplies a fallback account, and cleared when
    /// the user dismisses the note. Creating an account on the user's behalf is never
    /// silent (§7.10).
    public var showsStarterAccountNote: Bool = false
    /// The account the Dashboard is scoped to, or `nil` to show every open account (S7.1).
    ///
    /// Lets someone with a dedicated spending account hide balances they check less
    /// often (a savings account, say) without closing or hiding those accounts anywhere
    /// else. An id that no longer resolves to an open account -- closed, deleted -- is
    /// treated exactly like `nil` rather than erroring.
    public var focusedAccountID: UUID?
    /// The under-development features currently switched on.
    ///
    /// Seeded from ``FeatureFlag/isEnabledByDefault`` rather than left empty, so a flag
    /// that ever needs to ship on does not also need a change to how flags are stored.
    public var enabledFeatureFlags: Set<FeatureFlag> = Set(
        FeatureFlag.allCases.filter(\.isEnabledByDefault)
    )

    /// Reports whether an under-development feature is switched on.
    /// - Parameter flag: The feature to check.
    /// - Returns: `true` when the feature is on.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFeatureFlags.contains(flag)
    }

    /// Switches an under-development feature on or off.
    ///
    /// Does not persist: the caller saves through its ``AppSettingsStore``, matching how
    /// every other preference on this object is written.
    ///
    /// - Parameters:
    ///   - flag: The feature to switch.
    ///   - enabled: Whether it should be on.
    public func setFeature(_ flag: FeatureFlag, enabled: Bool) {
        if enabled {
            enabledFeatureFlags.insert(flag)
        } else {
            enabledFeatureFlags.remove(flag)
        }
    }

    /// The currency codes the Settings picker offers (§7.6).
    public static let selectableCurrencyCodes = ["USD", "EUR", "GBP", "CAD", "JPY"]

    /// The five lead times the default-reminder picker offers (§7.6).
    ///
    /// ``ReminderLeadTime/useDefault`` is excluded: it means "use this setting", so
    /// offering it here would be circular.
    public static let selectableDefaultLeadTimes: [ReminderLeadTime] = [
        .off, .sameDay, .oneDayBefore, .threeDaysBefore, .oneWeekBefore
    ]

    /// Creates settings with their default values.
    public init() {}
}

/// Loads and persists ``AppSettings``.
///
/// Declared here so `Features` can persist a change without knowing where settings
/// are stored.
@MainActor
public protocol AppSettingsStore {
    /// Applies stored values to the given settings object.
    /// - Parameter settings: The settings to populate.
    func load(into settings: AppSettings)

    /// Persists the given settings.
    /// - Parameter settings: The settings to store.
    func save(_ settings: AppSettings)
}
