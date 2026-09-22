import Foundation
import Testing
@testable import Domain

/// Working out which account a Shortcut's expense belongs to (§15.4, §15.5, §9.7).
///
/// The interesting decisions are the asymmetric ones. A number naming *no* account creates
/// one, because a card with a zero opening balance invents no money. A number naming
/// *several* creates nothing, because picking one would post real money to the wrong
/// balance. And nothing here throws: every doubt parks the entry instead, so the Shortcut
/// never loses what the user told it.
@Suite("Quick expense account resolution")
struct QuickExpenseAccountResolverTests {

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

    /// The account a match landed on, or a recorded failure.
    /// - Parameter match: The match to read.
    /// - Returns: The created account, or `nil` when nothing was created.
    private func created(_ match: QuickExpenseAccountMatch) -> Account? {
        guard case .create(let account) = match else {
            Issue.record("Expected an account to be created, got \(match)")
            return nil
        }
        return account
    }

    // MARK: - Normalisation

    @Test(
        "A number reduces to its last four digits however it was written",
        arguments: [
            "9087", "••9087", "...9087", "4532 1122 3344 9087",
            "4532********9087", "xxxx-xxxx-xxxx-9087"
        ]
    )
    func normalisesToLastFour(_ typed: String) {
        #expect(QuickExpenseAccountResolver.digits(from: typed) == "9087")
    }

    @Test("A number with fewer than four digits names no card")
    func refusesShortNumbers() {
        #expect(QuickExpenseAccountResolver.digits(from: "12") == nil)
        #expect(QuickExpenseAccountResolver.digits(from: "") == nil)
        #expect(QuickExpenseAccountResolver.digits(from: "Visa") == nil)
    }

    // MARK: - Matching

    @Test("A number matching one account resolves to it")
    func matchesOneAccount() throws {
        let card = account("Amex", last4: "9087")
        let accounts = [card, account("Chequing", last4: "1234")]

        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "9087", in: accounts
        )

        #expect(match == .matched(card.id))
    }

    @Test("The number wins over an account picked in the editor")
    func numberBeatsPicker() throws {
        let card = account("Amex", last4: "9087")
        let picked = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, accountNumber: "9087", in: [card, picked]
        )

        #expect(match == .matched(card.id))
    }

    @Test("The picked account is used when no number is supplied")
    func fallsBackToPicker() throws {
        let picked = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, in: [picked]
        )

        #expect(match == .matched(picked.id))
    }

    @Test("A blank number falls back to the picker rather than failing")
    func blankNumberIsAbsent() throws {
        let picked = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, accountNumber: "   ", in: [picked]
        )

        #expect(match == .matched(picked.id))
    }

    // MARK: - Doubt parks the entry

    @Test("A number naming several accounts parks the entry, and creates nothing")
    func parksOnAmbiguousNumbers() {
        let accounts = [account("Amex", last4: "9087"), account("Visa", last4: "9087")]

        let match = QuickExpenseAccountResolver.resolve(accountNumber: "9087", in: accounts)

        #expect(match == .unassigned(.ambiguousNumber(count: 2)))
    }

    @Test("A number too short to name a card parks rather than being turned into one")
    func parksOnUnreadableNumbers() {
        let match = QuickExpenseAccountResolver.resolve(accountNumber: "12", in: [])

        #expect(match == .unassigned(.unreadableNumber))
    }

    @Test("Neither an account, a number nor a name parks the entry")
    func parksOnEmptyInput() {
        let match = QuickExpenseAccountResolver.resolve(in: [])

        #expect(match == .unassigned(.nothingSupplied))
    }

    // MARK: - The picked account is checked, never trusted

    @Test("A picked account that is no longer in the app parks the entry")
    func parksOnAVanishedPickedAccount() {
        let survivor = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: UUID(), in: [survivor]
        )

        #expect(
            match == .unassigned(.unknownPickedAccount),
            "a saved Shortcut holds its picked identifier long enough to outlive the account"
        )
    }

    @Test("A picked account that has been closed parks the entry")
    func parksOnAClosedPickedAccount() {
        let closed = account("Old Amex", last4: "9087", isClosed: true)

        let match = QuickExpenseAccountResolver.resolve(pickedID: closed.id, in: [closed])

        #expect(
            match == .unassigned(.closedPickedAccount),
            "closed accounts are kept for history, not for new money"
        )
    }

    @Test("A picked account that is open and present still resolves")
    func resolvesALivePickedAccount() {
        let picked = account("Chequing", last4: "1234")

        let match = QuickExpenseAccountResolver.resolve(
            pickedID: picked.id, in: [picked, account("Amex", last4: "9087")]
        )

        #expect(match == .matched(picked.id))
    }

    // MARK: - Creation

    @Test("A number matching nothing creates a card carrying it")
    func createsUnknownCard() throws {
        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "4532 1122 3344 9087",
            in: [account("Chequing", last4: "1234")],
            sortIndex: 1,
            openingDate: now
        )

        let card = try #require(created(match))
        #expect(card.last4 == "9087")
        #expect(card.kind == .card)
        #expect(card.openingBalanceCents == 0)
        #expect(card.openingBalanceDate == now)
        #expect(card.sortIndex == 1)
        #expect(card.isClosed == false)
    }

    @Test("A created card takes the supplied name")
    func createdCardTakesTheName() throws {
        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "9087", accountName: "  Amex Travel  ", in: []
        )

        let card = try #require(created(match))
        #expect(card.name == "Amex Travel")
    }

    @Test("A created card with no name given still says which card it is")
    func createdCardNamesItself() throws {
        let match = QuickExpenseAccountResolver.resolve(accountNumber: "9087", in: [])

        let card = try #require(created(match))
        #expect(card.name == "Card ••9087")
    }

    @Test("A closed account carrying the digits is not matched, and a card is created")
    func skipsClosedAccounts() throws {
        let closed = account("Old Amex", last4: "9087", isClosed: true)

        let match = QuickExpenseAccountResolver.resolve(accountNumber: "9087", in: [closed])

        let card = try #require(created(match))
        #expect(card.id != closed.id)
        #expect(card.last4 == "9087")
    }

    // MARK: - Placement

    @Test("A created card joins the group it was given")
    func createdCardJoinsTheGroup() throws {
        let group = UUID()

        let match = QuickExpenseAccountResolver.resolve(
            accountNumber: "9087", in: [], groupID: group
        )

        let card = try #require(created(match))
        #expect(card.groupID == group)
    }
}
