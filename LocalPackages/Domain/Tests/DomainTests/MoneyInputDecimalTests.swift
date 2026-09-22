import Foundation
import Testing
@testable import Domain

/// Converting an App Intents currency parameter into cents (§2).
///
/// App Intents hands currency over as a `Decimal`, which is exact for decimal
/// fractions — so these tests pin down that the boundary never reaches for `Double`,
/// and that a third decimal place is rounded rather than silently truncated.
@Suite("Decimal money input")
struct MoneyInputDecimalTests {

    @Test("A plain amount converts exactly", arguments: [
        (Decimal(string: "0") ?? .nan, 0),
        (Decimal(string: "1") ?? .nan, 100),
        (Decimal(string: "12.10") ?? .nan, 1_210),
        (Decimal(string: "0.01") ?? .nan, 1),
        (Decimal(string: "1234.56") ?? .nan, 123_456)
    ])
    func convertsExactly(decimal: Decimal, cents: Int) {
        #expect(MoneyInput.cents(from: decimal) == cents)
    }

    @Test("A third decimal place rounds half-up", arguments: [
        (Decimal(string: "1.004") ?? .nan, 100),
        (Decimal(string: "1.005") ?? .nan, 101),
        (Decimal(string: "1.006") ?? .nan, 101)
    ])
    func roundsToTheCent(decimal: Decimal, cents: Int) {
        #expect(MoneyInput.cents(from: decimal) == cents, "a third decimal is a slip, not a coin")
    }

    @Test("A negative amount is refused rather than flipped")
    func refusesNegatives() {
        let cents = MoneyInput.cents(from: Decimal(string: "-5.00") ?? 0)

        #expect(cents == nil, "which way money moves is the type's business, not the amount's")
    }

    @Test("An amount too large to represent is refused")
    func refusesOverflow() {
        let huge = Decimal(string: "999999999999999999999") ?? 0

        #expect(MoneyInput.cents(from: huge) == nil)
    }

    // MARK: - The Shortcut's plain number parameter

    @Test("A typed number converts exactly", arguments: [
        (0.0, 0), (0.01, 1), (0.07, 7), (0.29, 29), (1.15, 115),
        (8.20, 820), (12.10, 1210), (42.10, 4210), (1234.56, 123_456)
    ])
    func convertsATypedNumber(value: Double, cents: Int) {
        #expect(
            MoneyInput.cents(fromAmount: value) == cents,
            "binary floating point must not lose a cent on the way in"
        )
    }

    @Test("A third decimal place is resolved by what the number really holds")
    func resolvesAThirdDecimalPlace() {
        // 1.005 is not representable: the nearest Double is 1.00499…, so 100 is the
        // faithful answer. Pinned so a future change to the conversion is deliberate.
        #expect(MoneyInput.cents(fromAmount: 1.005) == 100)
    }

    @Test("A negative or unusable number is refused", arguments: [
        -5.0, -0.01, Double.infinity, Double.nan
    ])
    func refusesUnusableNumbers(value: Double) {
        #expect(MoneyInput.cents(fromAmount: value) == nil)
    }

    @Test("A typed number agrees with the same amount typed as text")
    func typedNumberAgreesWithText() {
        #expect(MoneyInput.cents(fromAmount: 1234.56) == MoneyInput.cents(from: "1234.56"))
    }

    @Test("A decimal amount agrees with the same amount typed as text")
    func agreesWithTypedText() {
        let fromDecimal = MoneyInput.cents(from: Decimal(string: "1234.56") ?? 0)
        let fromText = MoneyInput.cents(from: "1234.56")

        #expect(fromDecimal == fromText, "one amount must not depend on which door it came in")
    }

    @Test("Text becomes an exact decimal under the same separator rule as cents")
    func textReadsIntoAnExactDecimal() {
        #expect(MoneyInput.decimal(from: "1234.56") == Decimal(string: "1234.56"))
        #expect(MoneyInput.decimal(from: "1,234.56") == Decimal(string: "1234.56"))
        #expect(MoneyInput.decimal(from: "1.234,56") == Decimal(string: "1234.56"))
    }

    @Test("A grouped figure with no fraction is whole, not fractional")
    func groupingWithoutAFractionIsWhole() {
        #expect(MoneyInput.decimal(from: "1,234") == Decimal(string: "1234"))
    }

    @Test("A figure with no whole part is read from its fraction alone")
    func aBareFractionIsRead() {
        #expect(MoneyInput.decimal(from: ".50") == Decimal(string: "0.50"))
    }

    @Test("A sign never reaches the magnitude")
    func theMagnitudeIsUnsigned() {
        // The sign is the caller's business — CSVAmountReader settles it before asking.
        #expect(MoneyInput.decimal(from: "-42.10") == Decimal(string: "42.10"))
    }

    @Test("Text holding no digits reads as nothing rather than as zero")
    func textWithoutDigitsIsRefused() {
        #expect(MoneyInput.decimal(from: "") == nil)
        #expect(MoneyInput.decimal(from: "n/a") == nil)
    }

    @Test("A decimal magnitude round-trips through cents")
    func decimalAndCentsAgree() {
        let magnitude = MoneyInput.decimal(from: "1,234.56")
        #expect(magnitude.flatMap(MoneyInput.cents(from:)) == 123_456)
    }
}
