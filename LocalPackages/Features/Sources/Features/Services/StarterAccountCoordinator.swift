import Foundation
import Domain

/// Keeps at least one usable account in the app (§7.10).
///
/// Applies ``StarterAccountPolicy`` and persists what it asks for. A value type built
/// at the call site rather than a stored dependency, so the view models that need it
/// gain no extra state.
///
/// Every failure is swallowed: this is a safety net that runs on skip, on foreground
/// and after a close, and it must never block or interrupt the flow it sits behind.
@MainActor
public struct StarterAccountCoordinator {
    /// Reads and writes accounts and groups.
    private let accounts: any AccountRepository
    /// The shared preferences object, whose note flag this sets.
    private let settings: AppSettings
    /// Persists the note flag.
    private let settingsStore: any AppSettingsStore

    /// Creates the coordinator.
    /// - Parameters:
    ///   - accounts: Reads and writes accounts and groups.
    ///   - settings: The shared preferences object.
    ///   - settingsStore: Persists the note flag.
    public init(
        accounts: any AccountRepository,
        settings: AppSettings,
        settingsStore: any AppSettingsStore
    ) {
        self.accounts = accounts
        self.settings = settings
        self.settingsStore = settingsStore
    }

    /// Creates the starter account when no open account remains.
    ///
    /// Safe to call repeatedly: the policy returns nothing once an open account exists.
    ///
    /// - Parameter now: The opening-balance date to stamp. Defaults to the current time.
    /// - Returns: `true` when an account was created, which is also when the note is owed.
    @discardableResult
    public func ensureUsableAccount(now: Date = .now) async -> Bool {
        guard let stored = try? await accounts.accounts(includeClosed: true),
              let groups = try? await accounts.groups(),
              let starter = StarterAccountPolicy.starter(
                  accounts: stored, groups: groups, now: now
              )
        else { return false }

        do {
            // The group must land first: the repository resolves the account's
            // groupID against stored groups and silently nils an unknown one.
            if let group = starter.group {
                try await accounts.save(group)
            }
            try await accounts.save(starter.account)
        } catch {
            return false
        }

        settings.showsStarterAccountNote = true
        settingsStore.save(settings)
        return true
    }
}
