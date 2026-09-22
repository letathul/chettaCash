import Foundation
import Observation
import Domain

/// The three onboarding steps (§7.10).
///
/// Scope is exactly these three. There is deliberately no starter-subscription or
/// starter-budget step.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    /// A static value-prop screen with one CTA and no skip link.
    case welcome
    /// Adding accounts, several in one pass.
    case accounts
    /// Requesting the real notification permission.
    case notifications

    /// The case's identity, for `ForEach`.
    public var id: Int { rawValue }
}

/// Drives onboarding (§7.10).
@MainActor
@Observable
public final class OnboardingViewModel {
    /// Creates accounts and groups.
    private let accountRepository: any AccountRepository
    /// Requests notification permission.
    private let notifications: any NotificationAuthorizing
    /// Persists the completion flag.
    private let settingsStore: any AppSettingsStore

    /// User preferences, whose `hasCompletedOnboarding` gates this flow.
    public let settings: AppSettings

    /// Which step is showing.
    public private(set) var step: OnboardingStep = .welcome
    /// Groups available to choose from.
    public private(set) var groups: [Domain.AccountGroup] = []
    /// Accounts created during this pass, in the order they were added.
    public private(set) var addedAccounts: [Domain.Account] = []
    /// Whether permission has been granted.
    public private(set) var notificationsAuthorized = false
    /// A save failure to surface above the content (§7.0).
    public private(set) var errorMessage: String?

    /// Creates the view model.
    /// - Parameters:
    ///   - accountRepository: Creates accounts and groups.
    ///   - notifications: Requests notification permission.
    ///   - settingsStore: Persists the completion flag.
    ///   - settings: The shared preferences object.
    public init(
        accountRepository: any AccountRepository,
        notifications: any NotificationAuthorizing,
        settingsStore: any AppSettingsStore,
        settings: AppSettings
    ) {
        self.accountRepository = accountRepository
        self.notifications = notifications
        self.settingsStore = settingsStore
        self.settings = settings
    }

    // MARK: - Derived state

    /// Whether at least one account exists, which is what enables Continue (§7.10).
    public var hasAnyAccount: Bool { !addedAccounts.isEmpty }

    /// The Continue button's label, which explains itself while disabled.
    public var continueTitle: String {
        hasAnyAccount ? "Continue" : "Add an account to continue"
    }

    /// The next sort position within a group.
    /// - Parameter groupID: The group an account is being added to.
    /// - Returns: The position to give the new account.
    public func nextSortIndex(inGroup groupID: UUID?) -> Int {
        addedAccounts.filter { $0.groupID == groupID }.count
    }

    // MARK: - Navigation

    /// Loads any groups that already exist.
    public func load() async {
        groups = (try? await accountRepository.groups()) ?? []
        notificationsAuthorized = await notifications.currentStatus() == .authorized
    }

    /// Moves to the next step.
    public func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// Marks onboarding done, so the flow runs once (§7.10).
    public func finish() {
        settings.hasCompletedOnboarding = true
        settingsStore.save(settings)
    }

    // MARK: - Accounts (§7.10 step 2)

    /// Creates a group so an account is never orphaned (§7.6).
    ///
    /// Returns the group so the caller can open the add-account sheet scoped to it.
    ///
    /// - Parameter name: The group's display name.
    /// - Returns: The saved group, or `nil` when the write failed.
    @discardableResult
    public func addGroup(named name: String) async -> Domain.AccountGroup? {
        let group = Domain.AccountGroup(name: name, sortIndex: groups.count)
        do {
            try await accountRepository.save(group)
            groups = try await accountRepository.groups()
            errorMessage = nil
            return group
        } catch {
            errorMessage = "Could not save that group."
            return nil
        }
    }

    /// Returns the accounts added this pass that belong to one group.
    /// - Parameter group: The group to list.
    /// - Returns: That group's accounts, in the order they were added.
    public func addedAccounts(in group: Domain.AccountGroup) -> [Domain.Account] {
        addedAccounts.filter { $0.groupID == group.id }
    }

    /// Saves an account and appends it to the "just added" list.
    ///
    /// The form stays open and clears rather than closing, so several accounts can be
    /// added in one pass (§7.10).
    ///
    /// - Parameter draft: The account to persist.
    /// - Returns: `true` when it saved.
    @discardableResult
    public func add(_ draft: Domain.Account) async -> Bool {
        var account = draft
        account.openingBalanceCents = BalanceEngine.normalizedOpeningBalanceCents(
            draft.openingBalanceCents, kind: draft.kind
        )
        do {
            try await accountRepository.save(account)
            if let saved = try await accountRepository.account(id: account.id) {
                addedAccounts.append(saved)
            } else {
                addedAccounts.append(account)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save that account."
            return false
        }
    }

    // MARK: - Starter account (§7.10)

    /// Creates the fallback Cash account when the user finishes with none.
    ///
    /// Separate from ``finish()`` rather than folded into it so that stays synchronous:
    /// it is called directly from several places and gains nothing from being `async`.
    public func ensureStarterAccount() async {
        await StarterAccountCoordinator(
            accounts: accountRepository, settings: settings, settingsStore: settingsStore
        ).ensureUsableAccount()
    }

    // MARK: - Notifications (§7.10 step 3)

    /// Triggers the real system permission prompt.
    ///
    /// Not a mock toggle: this is the one chance iOS gives to ask.
    public func requestNotifications() async {
        notificationsAuthorized = await notifications.requestAuthorization()
    }
}
