import Foundation
import Testing
@testable import Domain

/// The dedup key an import recognises a repeated purchase by (§4.2).
@Suite("Transaction fingerprints")
struct TransactionFingerprintTests {

    /// The card every fingerprint in this suite is taken against.
    private let card = Fixtures.account(name: "Visa", kind: .card)

    @Test("The same purchase spelled two ways fingerprints identically")
    func spellingsCollapse() {
        let typed = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )
        let printed = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3),
            merchant: "BLUE BOTTLE #1042"
        )

        let typedKey = typed.transactionHash(calendar: Fixtures.utc)
        let printedKey = printed.transactionHash(calendar: Fixtures.utc)

        #expect(typedKey == printedKey)
    }

    @Test("A fingerprint does not change when it is computed again")
    func stableAcrossComputations() {
        // The whole point: `Hasher` is seeded per process, so a hash-based key would
        // differ on the next launch and every import would re-add everything.
        let purchase = Fixtures.transaction(
            .expense, cents: 1_299, account: card, merchant: "Uniqlo"
        )

        let first = purchase.transactionHash(calendar: Fixtures.utc)
        let second = purchase.transactionHash(calendar: Fixtures.utc)

        #expect(first == second)
    }

    @Test("An expense and an income of the same magnitude do not collide")
    func signSeparatesEqualMagnitudes() {
        let charge = Fixtures.transaction(
            .expense, cents: 5_000, account: card, date: Fixtures.day(-2), merchant: "Acme"
        )
        let refund = Fixtures.transaction(
            .income, cents: 5_000, account: card, date: Fixtures.day(-2), merchant: "Acme"
        )

        let chargeKey = charge.transactionHash(calendar: Fixtures.utc)
        let refundKey = refund.transactionHash(calendar: Fixtures.utc)

        #expect(chargeKey != refundKey)
    }

    @Test("A different day, amount or card each produce a different fingerprint")
    func everyComponentMatters() {
        let base = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )
        let otherCard = Fixtures.account(name: "Amex", kind: .card)

        var laterDay = base
        laterDay.date = Fixtures.day(-2)
        var otherAmount = base
        otherAmount.amountCents = 676
        var otherAccount = base
        otherAccount.accountID = otherCard.id

        let baseKey = base.transactionHash(calendar: Fixtures.utc)

        #expect(laterDay.transactionHash(calendar: Fixtures.utc) != baseKey)
        #expect(otherAmount.transactionHash(calendar: Fixtures.utc) != baseKey)
        #expect(otherAccount.transactionHash(calendar: Fixtures.utc) != baseKey)
    }

    @Test("The separator never appears inside a component")
    func separatorIsUnambiguous() {
        // `MerchantCategoryIndex.key` emits only [a-z0-9-], so a merchant cannot smuggle
        // a separator in and shift every field one place along.
        let hostile = Fixtures.transaction(
            .expense, cents: 100, account: card, merchant: "A|B|C Store |||"
        )

        let key = hostile.transactionHash(calendar: Fixtures.utc)
        let parts = key.components(separatedBy: TransactionFingerprint.separator)

        #expect(parts.count == 5)
        #expect(parts[0] == TransactionFingerprint.version)
    }

    @Test("A row with no merchant still fingerprints")
    func emptyMerchantIsUsable() {
        let bare = Fixtures.transaction(.expense, cents: 100, account: card, merchant: "")

        let key = bare.transactionHash(calendar: Fixtures.utc)

        #expect(!key.isEmpty)
        #expect(key.components(separatedBy: TransactionFingerprint.separator).count == 5)
    }

    @Test("The day-and-amount key ignores the merchant, which is what makes a conflict")
    func dayAmountKeyIgnoresMerchant() {
        let mine = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3), merchant: "Blue Bottle"
        )
        let theirs = Fixtures.transaction(
            .expense, cents: 675, account: card, date: Fixtures.day(-3),
            merchant: "SQ *BLUE BOTTLE COFFEE"
        )

        let mineKey = TransactionFingerprint.dayAmountKey(
            accountID: mine.accountID,
            date: mine.date,
            signedCents: BalanceEngine.signedAmountCents(for: mine),
            calendar: Fixtures.utc
        )
        let theirsKey = TransactionFingerprint.dayAmountKey(
            accountID: theirs.accountID,
            date: theirs.date,
            signedCents: BalanceEngine.signedAmountCents(for: theirs),
            calendar: Fixtures.utc
        )

        // Same day-and-amount key, different full key: exactly a fuzzy conflict.
        #expect(mineKey == theirsKey)
        #expect(mine.transactionHash(calendar: Fixtures.utc)
                != theirs.transactionHash(calendar: Fixtures.utc))
    }

    @Test("A day renders as a zero-padded ISO date")
    func dayIsIsoFormatted() {
        let january = Date(timeIntervalSince1970: 1_767_312_000)  // 2026-01-02 00:00 UTC

        let rendered = TransactionFingerprint.day(january, calendar: Fixtures.utc)

        #expect(rendered == "2026-01-02")
    }
}
