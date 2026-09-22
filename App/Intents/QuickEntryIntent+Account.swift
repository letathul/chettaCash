import AppIntents
import Foundation
import Domain

/// The account a quick entry lands on, once the parameters have been reconciled.
struct ResolvedExpenseAccount {
    /// The account's identifier, whether it was found or is about to be created.
    ///
    /// `nil` when nothing named an account safely. The expense is still written; it is
    /// parked, and the Today card asks the user where it belongs (§15.5).
    let id: UUID?
    /// The account's name, for the spoken result. Empty for a parked entry.
    let name: String
    /// The account to write before the transaction, when one has to be created.
    let created: Domain.Account?
    /// Why the entry was parked, when it was.
    let doubt: QuickExpenseAccountDoubt?
}

/// Reconciling a quick entry's account picker with its account number (§15.4, §9.7).
///
/// Split from ``QuickEntryIntent`` itself to keep each file within the 300-line limit.
extension QuickEntryIntent {

    /// Works out which account this expense belongs to.
    ///
    /// The decision itself is ``QuickExpenseAccountResolver``'s, which is pure and tested in
    /// the fast Domain suite. What happens here is only the part that needs the database: the
    /// account list to match against, and the group and sort position a created card would
    /// take. Those mirror ``StatementImportCoordinator/resolveAccount(for:now:)`` so a card
    /// created from a Shortcut lands where one created from a statement import would.
    ///
    /// Closed accounts are included in the list deliberately, and the list is now load-bearing
    /// twice. The matchers skip closed accounts themselves, but they still occupy a sort
    /// position, so counting them keeps a created card at the end of the list rather than on
    /// top of an existing one — and the resolver needs them present to tell an account that
    /// was *closed* apart from one that is simply *gone*.
    ///
    /// - Parameter dependencies: The app's dependency graph.
    /// - Returns: The account to record against, one to create first if needed, or the doubt
    ///   that parks the entry.
    /// - Throws: A persistence error if the fetch fails, or the framework's own request when
    ///   the account picker has to be put to the user.
    @MainActor
    func resolveAccount(dependencies: AppDependencies) async throws -> ResolvedExpenseAccount {
        let picked = try await pickedAccount()
        let all = try await dependencies.accounts.accounts(includeClosed: true)
        let groups = try await dependencies.accounts.groups()

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked?.id,
            accountNumber: accountNumber,
            accountName: accountName,
            in: all,
            groupID: groups.first?.id,
            sortIndex: all.count
        )

        switch match {
        case .create(let card):
            return ResolvedExpenseAccount(
                id: card.id, name: card.name, created: card, doubt: nil
            )
        case .matched(let id):
            // The resolver has already proved this identifier against the same list, so the
            // account is known to be there and open. The picker's own copy of the name is
            // therefore safe to trust, and saves a second fetch.
            if let picked, picked.id == id {
                return ResolvedExpenseAccount(
                    id: id, name: picked.name, created: nil, doubt: nil
                )
            }
            let found = try await dependencies.accounts.account(id: id)
            return ResolvedExpenseAccount(
                id: id, name: found?.name ?? "", created: nil, doubt: nil
            )
        case .unassigned(let doubt):
            return ResolvedExpenseAccount(id: nil, name: "", created: nil, doubt: doubt)
        }
    }

    /// The account chosen in the editor, asking for one when nothing else identifies it.
    ///
    /// An optional parameter is never prompted for on its own, so the ask has to be made
    /// here — but only when neither a number nor a name was supplied, since either names the
    /// account by itself and interrupting a Shortcut to confirm what it already said would
    /// defeat the point of running it in the background.
    ///
    /// Text that was supplied but cannot be used counts as supplied. Quietly falling back to
    /// the picker would answer a typo with a question about something else, where the
    /// resolver's parked entry names what was wrong with it.
    ///
    /// A prompt that yields nothing is not an error. It leaves the resolver with nothing,
    /// which parks the entry rather than losing it — the right answer when a headless
    /// automation had no one there to ask.
    ///
    /// The error ``QuickEntryIntent/requestAccount()`` throws is deliberately **not** caught.
    /// That throw is how App Intents asks: the framework catches it, puts the question to the
    /// user, and runs the intent again with the answer. Swallowing it would mean the prompt
    /// never appears.
    ///
    /// - Returns: The chosen account, or `nil` when the text will name it instead.
    /// - Throws: The framework's own request, so it can present the picker.
    @MainActor
    private func pickedAccount() async throws -> AccountEntity? {
        if let account { return account }
        let supplied = [accountNumber, accountName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard supplied.isEmpty else { return nil }
        return try await requestAccount()
    }
}
