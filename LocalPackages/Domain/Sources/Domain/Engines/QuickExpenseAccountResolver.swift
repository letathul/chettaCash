import Foundation

/// Which account a Shortcut's entry belongs to, and whether one must be created first.
public enum QuickExpenseAccountMatch: Sendable, Equatable {
    /// An account already exists for this entry: the one picked, or the one the supplied
    /// number or name identified.
    case matched(UUID)
    /// Nothing identified an existing account, so this one is safe to create and record against.
    case create(Account)
    /// Nothing identified an account safely, so the entry is written without one and left
    /// for the user to assign by hand (§15.5).
    case unassigned(QuickExpenseAccountDoubt)
}

/// Why a Shortcut's account could not be settled, and the entry was parked instead (§15.5).
public enum QuickExpenseAccountDoubt: Sendable, Equatable {
    /// Fewer than four digits survived normalisation, so the number names no card.
    case unreadableNumber
    /// Several accounts carry those digits.
    case ambiguousNumber(count: Int)
    /// Several accounts answer to that name.
    case ambiguousName(count: Int)
    /// No account answers to that name, and a name may not create one (§15.4).
    case unrecognisedName
    /// The picked account is no longer in the app.
    case unknownPickedAccount
    /// The picked account has been closed, and closed accounts take no new money (§4.7).
    case closedPickedAccount
    /// Neither an account, a number, nor a name was supplied.
    case nothingSupplied
}

/// Resolves the account a Shortcut logs against, creating one only where that cannot be
/// wrong, and parking the entry wherever it could be (§15.4, §15.5).
///
/// **Why text outranks the picker.** A Shortcut is built once and run for months, and its
/// account picker is frozen at the moment it was built. A number or a name arrives with the
/// entry — off a Wallet card, a bank notification, or a field typed at run time — so it
/// describes *this* purchase where the picker only describes its author's intent long ago.
///
/// **Why the number outranks the name.** Four digits identify one card exactly. A name is
/// what a person calls it, and two cards from one bank are often named nearly the same, so
/// digits are consulted first whenever they were supplied.
///
/// **Why four digits may create an account and a name may not.** Digits matching nothing
/// mean a card the user demonstrably holds and has not set up yet, and inventing it with a
/// zero opening balance adds no phantom money: ``BalanceEngine`` derives the balance from
/// that zero plus the entries recorded against it. A name matching nothing is far more often
/// a typo, and "Chequng" would mint a phantom ``AccountKind/card`` — negative when owed, and
/// wrong in Net Worth — that nobody asked for. The name still christens whatever the number
/// creates. This is the same split ``StatementAccountProvisioner`` makes for statement
/// import, and the digit half reuses its matching rules through
/// ``AccountMatcher/candidates(_:in:)`` so they are stated once.
///
/// **Why nothing here throws.** The three answers to doubt are not equally bad. Guessing
/// posts real money to the wrong balance, silently. Refusing loses what the user told the
/// app — and from a headless automation it loses it with nobody watching. Parking keeps the
/// entry, stays honest about what is unknown, and puts it where the user will see it. So
/// every doubt returns ``QuickExpenseAccountMatch/unassigned(_:)`` and the caller writes the
/// entry with no account.
public enum QuickExpenseAccountResolver {

    /// How many digits identify a card.
    ///
    /// Four, because four is all ``Account/last4`` stores — the app matches on the printed tail
    /// of a number and never keeps enough to identify the card to anyone else (§9.7).
    public static let digitCount = 4

    /// The four digits that identify a card within a number as it was supplied.
    ///
    /// Everything that is not a digit is dropped and the last four are kept, so a full number,
    /// a masked one and the bare tail all reduce to the same thing: `"4532 1122 3344 9087"`,
    /// `"4532********9087"` and `"9087"` each yield `"9087"`.
    ///
    /// - Parameter text: The number as the Shortcut supplied it.
    /// - Returns: The four digits, or `nil` when the text holds fewer than four.
    public static func digits(from text: String) -> String? {
        let digits = text.filter(\.isNumber)
        guard digits.count >= digitCount else { return nil }
        return String(digits.suffix(digitCount))
    }

    /// Every open account a name could mean, before the sole-candidate rule is applied.
    ///
    /// Exact match first, then containment in either direction accepted only when one account
    /// survives — the same rule ``ReceiptPrefillBuilder/match(_:in:)`` applies to category
    /// labels, and folded the same way, so "apple card" reaches "Apple Card" and a Wallet pass
    /// called "Apple Card" still reaches an account the user simply called "Apple".
    ///
    /// Closed accounts are never offered: they are kept for history (§4.7), not for new entries.
    ///
    /// - Parameters:
    ///   - name: The name as supplied.
    ///   - accounts: The accounts to match against.
    /// - Returns: The candidates, which may be empty or hold several.
    public static func candidates(named name: String, in accounts: [Account]) -> [Account] {
        let wanted = ReceiptPrefillBuilder.normalized(name)
        guard !wanted.isEmpty else { return [] }
        let open = accounts.filter { !$0.isClosed }

        let exact = open.filter { ReceiptPrefillBuilder.normalized($0.name) == wanted }
        if !exact.isEmpty { return exact }
        return open.filter {
            let candidate = ReceiptPrefillBuilder.normalized($0.name)
            return !candidate.isEmpty && (candidate.contains(wanted) || wanted.contains(candidate))
        }
    }

    /// Works out which account an entry belongs to.
    ///
    /// - Parameters:
    ///   - pickedID: The account chosen in the Shortcuts editor, if one was. Checked against
    ///     `accounts` rather than trusted: a saved Shortcut holds this identifier for months,
    ///     long enough for the account to be closed or for a restored backup to replace it.
    ///   - accountNumber: The account number supplied as text. Blank counts as absent, so a
    ///     Shortcut that leaves the field empty falls through rather than parking.
    ///   - accountName: The account name supplied as text. Finds an account, and names one
    ///     that the number has to create.
    ///   - accounts: The accounts to match against. **Closed ones must be included**: the
    ///     matchers skip them themselves, but they still occupy a sort position, and the
    ///     picked-account check needs to tell "closed" apart from "gone".
    ///   - groupID: The group a created account would join.
    ///   - sortIndex: The ordering position a created account would take.
    ///   - openingDate: The date a created account's zero opening balance applies from.
    /// - Returns: The account to record against, the card to create first, or the doubt that
    ///   parks the entry.
    public static func resolve(
        pickedID: UUID? = nil,
        accountNumber: String? = nil,
        accountName: String? = nil,
        in accounts: [Account],
        groupID: UUID? = nil,
        sortIndex: Int = 0,
        openingDate: Date = .now
    ) -> QuickExpenseAccountMatch {
        let placement = Placement(
            groupID: groupID, sortIndex: sortIndex, openingDate: openingDate
        )
        let name = trimmed(accountName)
        if let supplied = trimmed(accountNumber) {
            return byNumber(supplied, name: name, in: accounts, placement: placement)
        }
        if let name { return byName(name, in: accounts) }
        if let pickedID { return byPicker(pickedID, in: accounts) }
        return .unassigned(.nothingSupplied)
    }

    /// Where a created account is placed, bundled so the helpers stay short-signatured.
    private struct Placement {
        /// The group it joins.
        let groupID: UUID?
        /// Its ordering position.
        let sortIndex: Int
        /// The date its zero opening balance applies from.
        let openingDate: Date
    }

    /// Resolves a supplied number against the accounts that exist.
    /// - Parameters:
    ///   - number: The number as supplied, already known to be non-blank.
    ///   - name: The name to give a created card, already trimmed.
    ///   - accounts: The accounts to match against.
    ///   - placement: Where a created card would sit.
    /// - Returns: The matching account, the card to create, or the doubt that parks the entry.
    private static func byNumber(
        _ number: String,
        name: String?,
        in accounts: [Account],
        placement: Placement
    ) -> QuickExpenseAccountMatch {
        guard let last4 = digits(from: number) else { return .unassigned(.unreadableNumber) }
        let candidates = AccountMatcher.candidates(ReceiptTender(last4: last4), in: accounts)

        if candidates.count == 1, let only = candidates.first { return .matched(only.id) }
        if candidates.count > 1 {
            return .unassigned(.ambiguousNumber(count: candidates.count))
        }
        var card = StatementAccountProvisioner.makeCard(
            last4: last4,
            groupID: placement.groupID,
            sortIndex: placement.sortIndex,
            openingDate: placement.openingDate
        )
        // A blank name leaves makeCard's own "Card ••9087", which at least says which card it
        // is — better than a nameless row in every list that renders one.
        if let name { card.name = name }
        return .create(card)
    }

    /// Resolves a supplied name against the accounts that exist.
    ///
    /// A name reaching nothing parks the entry rather than creating an account. Four digits
    /// name a card that exists; a name is a string that might be a typo, and the cost of
    /// being wrong is a phantom credit card the user has to find and delete (§15.4).
    ///
    /// - Parameters:
    ///   - name: The name as supplied, already known to be non-blank.
    ///   - accounts: The accounts to match against.
    /// - Returns: The matching account, or the doubt that parks the entry.
    private static func byName(
        _ name: String,
        in accounts: [Account]
    ) -> QuickExpenseAccountMatch {
        let candidates = candidates(named: name, in: accounts)

        if candidates.count == 1, let only = candidates.first { return .matched(only.id) }
        if candidates.count > 1 {
            return .unassigned(.ambiguousName(count: candidates.count))
        }
        return .unassigned(.unrecognisedName)
    }

    /// Checks that the account picked in the editor is still one money may be recorded against.
    ///
    /// The identifier alone proves nothing. It was captured when the Shortcut was built and
    /// nothing has kept it honest since — the account may have been closed (§4.7), or replaced
    /// wholesale by a restored backup. Writing against it unchecked files the entry against a
    /// row that is not there, which no balance reflects and nothing announces.
    ///
    /// - Parameters:
    ///   - pickedID: The identifier the Shortcut stored.
    ///   - accounts: The accounts to match against, closed ones included.
    /// - Returns: The matching account, or the doubt that parks the entry.
    private static func byPicker(
        _ pickedID: UUID,
        in accounts: [Account]
    ) -> QuickExpenseAccountMatch {
        guard let picked = accounts.first(where: { $0.id == pickedID }) else {
            return .unassigned(.unknownPickedAccount)
        }
        guard !picked.isClosed else { return .unassigned(.closedPickedAccount) }
        return .matched(picked.id)
    }

    /// Trims a supplied string, treating blank as absent.
    /// - Parameter text: The text to trim.
    /// - Returns: The trimmed text, or `nil` when it held nothing.
    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
