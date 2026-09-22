import Foundation
import Testing
@testable import Domain

/// Matching a scanned receipt to the account it was paid from (§9.7).
///
/// The rule under test throughout is that **ambiguity returns nothing**. A wrong match
/// puts money against the wrong balance, and a filled field is skimmed where an empty
/// one is read — so every case that could mean two accounts must mean none.
@Suite("Receipt account matching")
struct AccountMatcherTests {

    /// Builds an account with card details.
    /// - Parameters:
    ///   - name: The display name.
    ///   - last4: The card's last four digits.
    ///   - network: The card's network.
    ///   - isClosed: Whether the account is closed.
    /// - Returns: The account.
    private func account(
        _ name: String,
        last4: String? = nil,
        network: CardNetwork? = nil,
        isClosed: Bool = false
    ) -> Account {
        Account(name: name, kind: .card, isClosed: isClosed, last4: last4, cardNetwork: network)
    }

    @Test("A card's digits pick out its account")
    func matchesOnDigits() {
        let visa = account("TD Visa", last4: "4821", network: .visa)
        let other = account("CIBC Card", last4: "9931", network: .mastercard)

        let matched = AccountMatcher.match(ReceiptTender(last4: "4821"), in: [visa, other])

        #expect(matched == visa.id)
    }

    @Test("The network breaks a tie between two cards sharing their last four digits")
    func networkBreaksDigitTie() {
        let visa = account("TD Visa", last4: "4821", network: .visa)
        let mastercard = account("CIBC", last4: "4821", network: .mastercard)

        let matched = AccountMatcher.match(
            ReceiptTender(last4: "4821", network: .mastercard), in: [visa, mastercard]
        )

        #expect(matched == mastercard.id)
    }

    @Test("Two cards sharing their digits, with no network printed, match nothing")
    func ambiguousDigitsMatchNothing() {
        let visa = account("TD Visa", last4: "4821", network: .visa)
        let mastercard = account("CIBC", last4: "4821", network: .mastercard)

        let matched = AccountMatcher.match(ReceiptTender(last4: "4821"), in: [visa, mastercard])

        #expect(matched == nil, "the receipt cannot say which of the two it was")
    }

    @Test("Digits that match no account never fall back to the network")
    func unmatchedDigitsDoNotFallBack() {
        let visa = account("TD Visa", last4: "4821", network: .visa)

        let matched = AccountMatcher.match(
            ReceiptTender(last4: "7777", network: .visa), in: [visa]
        )

        #expect(
            matched == nil,
            "a card the user has not set up must not select a different card of theirs"
        )
    }

    @Test("A network alone matches when only one account uses it")
    func matchesOnNetworkAlone() {
        let visa = account("TD Visa", last4: "4821", network: .visa)
        let mastercard = account("CIBC", last4: "9931", network: .mastercard)

        let matched = AccountMatcher.match(ReceiptTender(network: .visa), in: [visa, mastercard])

        #expect(matched == visa.id)
    }

    @Test("A network shared by two accounts matches nothing")
    func ambiguousNetworkMatchesNothing() {
        let first = account("TD Visa", last4: "4821", network: .visa)
        let second = account("RBC Visa", last4: "9931", network: .visa)

        let matched = AccountMatcher.match(ReceiptTender(network: .visa), in: [first, second])

        #expect(matched == nil)
    }

    @Test("A closed account is never matched")
    func skipsClosedAccounts() {
        let closed = account("Old Visa", last4: "4821", network: .visa, isClosed: true)

        let matched = AccountMatcher.match(ReceiptTender(last4: "4821"), in: [closed])

        #expect(matched == nil, "closed accounts are kept for history, not for new entries")
    }

    @Test("A closed account does not make an open one ambiguous")
    func closedAccountDoesNotBlockAnOpenOne() {
        let closed = account("Old Visa", last4: "4821", network: .visa, isClosed: true)
        let open = account("New Visa", last4: "4821", network: .visa)

        let matched = AccountMatcher.match(ReceiptTender(last4: "4821"), in: [closed, open])

        #expect(matched == open.id)
    }

    @Test("A receipt with no card details matches nothing")
    func emptyTenderMatchesNothing() {
        let visa = account("TD Visa", last4: "4821", network: .visa)

        #expect(AccountMatcher.match(ReceiptTender(), in: [visa]) == nil)
    }

    @Test("An account with no card details recorded is never matched")
    func accountWithoutCardDetails() {
        let plain = Account(name: "Cash", kind: .account)

        #expect(AccountMatcher.match(ReceiptTender(last4: "4821"), in: [plain]) == nil)
    }
}
