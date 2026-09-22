import AppIntents
import UIKit
import Domain

/// One of the user's accounts, as Siri and the Shortcuts editor see it.
///
/// Closed accounts are never offered: they are kept so history stays readable (§4.7),
/// not so new money can be recorded against them.
struct AccountEntity: AppEntity {
    /// The account's identifier, shared with ``Domain/Account``.
    let id: UUID
    /// The account's name, which is what Siri matches on.
    let name: String
    /// The last four digits the account carries, if the user recorded them.
    ///
    /// Shown beneath the name in the picker, and matched on alongside it. Two cards from one
    /// bank often differ only by their digits, and a Shortcut that logs by number is built by
    /// someone who thinks in those digits — so a picker that shows only names makes them
    /// choose between two identical rows.
    let last4: String?

    /// How the type is described in the Shortcuts editor.
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Account" }

    /// Supplies accounts to the picker and to Siri.
    static let defaultQuery = AccountEntityQuery()

    /// How one account is shown in a picker.
    var displayRepresentation: DisplayRepresentation {
        guard let last4 else { return DisplayRepresentation(title: "\(name)") }
        return DisplayRepresentation(title: "\(name)", subtitle: "••\(last4)")
    }
}

/// Finds the accounts an intent may be pointed at.
struct AccountEntityQuery: EntityStringQuery {

    /// Fetches accounts by identifier.
    ///
    /// Deliberately **not** withheld while the phone is locked, where the two searches below
    /// are. This confirms an identifier the caller already holds, so it discloses nothing
    /// new — and blanking it would break every saved Shortcut on a locked phone, including
    /// the write the owner actually wants (§15.3).
    ///
    /// - Parameter identifiers: The identifiers to fetch.
    /// - Returns: The matching open accounts.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        let wanted = Set(identifiers)
        return try await openAccounts().filter { wanted.contains($0.id) }
    }

    /// Fetches accounts whose name, or card digits, match what the user said.
    ///
    /// Case- and diacritic-insensitive, so "chequing" reaches "Chequing" and "cafe"
    /// reaches "Café" — the same folding the rest of the app matches names with.
    ///
    /// Digits are matched as well as names, so typing `9087` finds the card ending in it.
    /// Only an all-digit query is tried against the digits: a name containing a number
    /// would otherwise reach cards that merely share one of its figures.
    ///
    /// Withheld entirely while the phone is locked and the §11 lock is on: this is a search
    /// across every account the user has, which is exactly what the lock hides.
    ///
    /// - Parameter string: What the user said or typed.
    /// - Returns: The matching open accounts.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func entities(matching string: String) async throws -> [AccountEntity] {
        guard try await !hidesAccounts() else { return [] }
        let wanted = folded(string)
        guard !wanted.isEmpty else { return try await openAccounts() }
        let digits = wanted.allSatisfy(\.isNumber) ? wanted : nil
        return try await openAccounts().filter { account in
            if folded(account.name).contains(wanted) { return true }
            guard let digits, let last4 = account.last4 else { return false }
            return last4.contains(digits)
        }
    }

    /// The accounts offered when the picker is opened with nothing typed.
    ///
    /// Withheld while the phone is locked and the §11 lock is on. This is the plainest read
    /// of the lot — it enumerates every account by name, with the card's last four digits
    /// beneath each one, into a picker anybody can open.
    ///
    /// - Returns: Every open account, or none while they are private.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] {
        guard try await !hidesAccounts() else { return [] }
        return try await openAccounts()
    }

    /// Whether the accounts are private right now (§15.3).
    ///
    /// `isProtectedDataAvailable` is the system's promptless answer to "is this phone
    /// unlocked" — no `LAContext`, and so no Face ID sheet fired from inside a picker, which
    /// would be absurd and would not be answerable anyway.
    ///
    /// - Returns: Whether to withhold them.
    /// - Throws: A persistence error if building the graph fails.
    @MainActor
    private func hidesAccounts() async throws -> Bool {
        ShortcutPrivacyPolicy.hidesStoredData(
            lockEnabled: try await AppEnvironment.shared().settings.appLockEnabled,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        )
    }

    /// Every open account, in sort order.
    /// - Returns: The accounts.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    private func openAccounts() async throws -> [AccountEntity] {
        let accounts = try await AppEnvironment.shared().accounts.accounts(includeClosed: false)
        return accounts.map { AccountEntity(id: $0.id, name: $0.name, last4: $0.last4) }
    }

    /// Folds a name for comparison.
    /// - Parameter text: The text to fold.
    /// - Returns: The folded text.
    private func folded(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
