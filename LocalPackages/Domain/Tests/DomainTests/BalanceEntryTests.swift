import Foundation
import Testing
@testable import Domain

@Suite("Unsigned balance entry")
struct BalanceEntryTests {

    @Test("A magnitude under the negative direction owes money")
    func negativeDirectionOwes() {
        #expect(BalanceEntry.signedCents(magnitude: 123_456, direction: .negative) == -123_456)
    }

    @Test("A magnitude under the positive direction is money held")
    func positiveDirectionHolds() {
        #expect(BalanceEntry.signedCents(magnitude: 123_456, direction: .positive) == 123_456)
    }

    @Test("A sign that slips into the typed magnitude never beats the chosen direction")
    func typedSignIsIgnored() {
        // Pasted text can carry a minus the decimal pad cannot produce. The control the
        // user actually touched wins, so the two can never disagree.
        #expect(BalanceEntry.signedCents(magnitude: -500, direction: .positive) == 500)
        #expect(BalanceEntry.signedCents(magnitude: 500, direction: .negative) == -500)
        #expect(BalanceEntry.signedCents(magnitude: -500, direction: .negative) == -500)
    }

    @Test("Zero stays zero in either direction, never negative zero")
    func zeroIsUnsigned() {
        #expect(BalanceEntry.signedCents(magnitude: 0, direction: .negative) == 0)
        #expect(BalanceEntry.signedCents(magnitude: 0, direction: .positive) == 0)
    }

    @Test("An existing balance seeds the direction it is already on")
    func directionRoundTrips() {
        #expect(BalanceEntry.direction(ofCents: -1) == .negative)
        #expect(BalanceEntry.direction(ofCents: -123_456) == .negative)
        #expect(BalanceEntry.direction(ofCents: 1) == .positive)
        #expect(BalanceEntry.direction(ofCents: 123_456) == .positive)
    }

    @Test("A zero balance seeds positive, because nothing is owed at zero")
    func zeroSeedsPositive() {
        #expect(BalanceEntry.direction(ofCents: 0) == .positive)
    }

    @Test("Magnitude and direction round-trip any stored balance", arguments: [
        -123_456, -1, 0, 1, 123_456
    ])
    func roundTrip(stored: Int) {
        let direction = BalanceEntry.direction(ofCents: stored)
        let magnitude = MoneyInput.magnitudeCents(
            from: MoneyInput.magnitudeText(fromCents: stored)
        )
        let rebuilt = BalanceEntry.signedCents(magnitude: magnitude ?? 0, direction: direction)
        #expect(rebuilt == stored)
    }

    @Test("A card defaults to owed and an account to in hand")
    func defaultsMatchTheKind() {
        #expect(BalanceEntry.defaultDirection(for: .card) == .negative)
        #expect(BalanceEntry.defaultDirection(for: .account) == .positive)
    }

    @Test("Each kind words its directions differently")
    func labelsDifferByKind() {
        #expect(BalanceEntry.label(for: .negative, kind: .card) == "Owed")
        #expect(BalanceEntry.label(for: .positive, kind: .card) == "In credit")
        #expect(BalanceEntry.label(for: .negative, kind: .account) == "Overdrawn")
        #expect(BalanceEntry.label(for: .positive, kind: .account) == "In hand")
    }
}

@Suite("Unsigned money parsing")
struct MoneyMagnitudeTests {

    @Test("A magnitude is never negative, whatever the text says", arguments: [
        "-1.00", "1.00", "\u{2212}1.00"
    ])
    func magnitudeIsUnsigned(input: String) {
        #expect(MoneyInput.magnitudeCents(from: input) == 100)
    }

    @Test("Text with no digits still fails to parse rather than reading as zero")
    func blankStillFails() {
        #expect(MoneyInput.magnitudeCents(from: "") == nil)
        #expect(MoneyInput.magnitudeCents(from: "abc") == nil)
        #expect(MoneyInput.magnitudeCents(from: "-") == nil)
    }

    @Test("Seeding a field drops the sign a decimal pad cannot type back")
    func magnitudeTextIsUnsigned() {
        #expect(MoneyInput.magnitudeText(fromCents: -123_456) == "1234.56")
        #expect(MoneyInput.magnitudeText(fromCents: 123_456) == "1234.56")
        #expect(MoneyInput.magnitudeText(fromCents: 0) == "0.00")
    }
}
