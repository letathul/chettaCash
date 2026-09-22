import Foundation
import Testing
@testable import Domain

/// Reaching an account by the name a Shortcut supplies (§4.2).
///
/// A Wallet pass hands over a name, not digits, so a name has to find an account on its own.
/// It is the looser of the two keys — two cards from one bank are often named nearly the
/// same — which is why the digits outrank it and why a name reaching several accounts is
/// refused rather than guessed at.
@Suite("Quick expense account names")
struct QuickExpenseAccountNameTests {

    /// A fixed moment, so results never depend on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// Builds an account carrying a card's digits.
    /// - Parameters:
    ///   - name: The account's name.
    ///   - last4: The digits it carries, if any.
    ///   - isClosed: Whether it has been closed.
    /// - Returns: The account.
    private func account(_ name: String, last4: String? = nil, isClosed: Bool = false) -> Account {
        Account(name: name, kind: .card, isClosed: isClosed, last4: last4)
    }

    /// The account a match created, or a recorded failure.
    /// - Parameter match: The match to read.
    /// - Returns: The created account, or `nil` when nothing was created.
    private func created(_ match: QuickExpenseAccountMatch) -> Account? {
        guard case .create(let account) = match else {
            Issue.record("Expected an account to be created, got \(match)")
            return nil
        }
        return account
    }

    @Test("A name alone reaches the account that answers to it")
    func matchesByName() throws {
        let amex = account("Apple Card", last4: "9087")
        let accounts = [amex, account("Chequing", last4: "1234")]

        let match = QuickExpenseAccountResolver.resolve(
            accountName: "Apple Card", in: accounts
        )

        #expect(match == .matched(amex.id))
    }

    @Test(
        "A name matches whatever the case, accents or partial wording",
        arguments: ["apple card", "APPLE CARD", "  Apple Card  ", "Apple", "Apple Card Titanium"]
    )
    func matchesNameLoosely(_ typed: String) throws {
        let amex = account("Apple Card", last4: "9087")

        let match = QuickExpenseAccountResolver.resolve(
            accountName: typed, in: [amex, account("Chequing")]
        )

        #expect(match == .matched(amex.id))
    }

    @Test("An exact name beats an account that merely contains it")
    func exactNameWins() throws {
        let exact = account("Visa")
        let longer = account("Visa Platinum Rewards")

        let match = QuickExpenseAccountResolver.resolve(
            accountName: "Visa", in: [longer, exact]
        )

        #expect(match == .matched(exact.id))
    }

    @Test("The number overrules the name when both are given")
    func numberBeatsName() throws {
        let byDigits = account("Apple Card", last4: "9087")
        let byName = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "9087", accountName: "Chequing", in: [byDigits, byName]
        )

        #expect(match == .matched(byDigits.id))
    }

    @Test("The name still christens whatever the number creates")
    func nameNamesWhatTheNumberCreates() throws {
        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "5555", accountName: "Apple Card", in: []
        )

        let card = try #require(created(match))
        #expect(card.name == "Apple Card")
        #expect(card.last4 == "5555")
    }

    @Test("The name is preferred over an account picked in the editor")
    func nameBeatsPicker() throws {
        let named = account("Apple Card")
        let picked = account("Chequing")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, accountName: "Apple Card", in: [named, picked]
        )

        #expect(match == .matched(named.id))
    }

    @Test("A name reaching several accounts parks the entry, and creates nothing")
    func parksOnAmbiguousNames() {
        let accounts = [account("Visa Gold"), account("Visa Platinum")]

        let match = QuickExpenseAccountResolver.resolve(accountName: "Visa", in: accounts)

        #expect(match == .unassigned(.ambiguousName(count: 2)))
    }

    @Test("A name reaching no account parks the entry rather than minting a card")
    func parksOnAnUnrecognisedName() {
        let match = QuickExpenseAccountResolver.resolve(
            accountName: "Chequng", in: [account("Chequing")], sortIndex: 1, openingDate: now
        )

        #expect(
            match == .unassigned(.unrecognisedName),
            "a name is a string that might be a typo, where four digits name a card that exists"
        )
    }

    @Test("A closed account answering to the name is not matched, and nothing is created")
    func skipsClosedAccountsByName() {
        let closed = account("Apple Card", isClosed: true)

        let match = QuickExpenseAccountResolver.resolve(
            accountName: "Apple Card", in: [closed]
        )

        #expect(match == .unassigned(.unrecognisedName))
    }

    @Test("A blank name falls back to the picker rather than creating a nameless account")
    func blankNameIsAbsent() throws {
        let picked = account("Chequing")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, accountName: "   ", in: [picked]
        )

        #expect(match == .matched(picked.id))
    }
}
