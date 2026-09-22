import Foundation
import Testing
@testable import Domain

@Suite("Currency display names")
struct CurrencyFormatterTests {

    // Mirrors `AppSettings.selectableCurrencyCodes`, which is main-actor isolated and
    // so cannot be used as a `@Test` argument list.
    @Test("Every selectable code resolves to a name, not the bare code", arguments: [
        "USD", "EUR", "GBP", "CAD", "JPY"
    ])
    func selectableCodesHaveNames(code: String) {
        let name = CurrencyFormatter.displayName(for: code)
        #expect(name != code)
        #expect(!name.isEmpty)
    }

    @Test("A code the locale cannot name falls back to the code itself")
    func unknownCodeFallsBack() {
        #expect(CurrencyFormatter.displayName(for: "ZZZ") == "ZZZ")
    }
}

/// Pins the shape of a formatted amount (§8.1).
///
/// These assert structure rather than exact glyphs: the symbol, the grouping separator
/// and the sign placement are all locale-dependent, so a test hard-coding `"$1,234.56"`
/// would pass only on a US-locale machine. What must not drift is that every amount
/// carries the code's symbol, always shows exactly two fraction digits, and puts a
/// negative sign somewhere on a negative amount.
@Suite("Currency amount formatting")
struct CurrencyAmountFormattingTests {

    @Test("Zero, sub-unit and whole amounts all keep two fraction digits", arguments: [
        "USD", "EUR", "GBP", "CAD", "JPY"
    ])
    func alwaysTwoFractionDigits(code: String) {
        let separator = Locale.current.decimalSeparator ?? "."
        for cents in [0, 1, 10, 100, 123_456] {
            let text = CurrencyFormatter.string(fromCents: cents, currencyCode: code)
            let fraction = text.components(separatedBy: separator).last ?? ""
            #expect(fraction.count == 2, "\(code) \(cents) formatted as \(text)")
        }
    }

    @Test("A negative amount is marked negative and a positive one is not")
    func negativeAmountsCarryASign() {
        let negative = CurrencyFormatter.string(fromCents: -123_456, currencyCode: "USD")
        let positive = CurrencyFormatter.string(fromCents: 123_456, currencyCode: "USD")
        #expect(negative.contains("-") || negative.contains("\u{2212}") || negative.contains("("))
        #expect(!positive.contains("-"))
        #expect(!positive.contains("\u{2212}"))
    }

    @Test("Zero is not rendered as a negative zero")
    func zeroIsUnsigned() {
        let text = CurrencyFormatter.string(fromCents: 0, currencyCode: "USD")
        #expect(!text.contains("-"))
        #expect(!text.contains("\u{2212}"))
    }

    @Test("The same magnitude formats identically either side of zero, sign aside")
    func magnitudeIsSymmetric() {
        let negative = CurrencyFormatter.string(fromCents: -4_250, currencyCode: "USD")
        let positive = CurrencyFormatter.string(fromCents: 4_250, currencyCode: "USD")
        let stripped = negative
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "")
        #expect(stripped == positive)
    }

    @Test("An unknown code still formats, falling back to the bare code")
    func unknownCodeStillFormats() {
        let text = CurrencyFormatter.string(fromCents: 100, currencyCode: "ZZZ")
        #expect(text.contains("ZZZ"))
        #expect(!text.isEmpty)
    }
}
