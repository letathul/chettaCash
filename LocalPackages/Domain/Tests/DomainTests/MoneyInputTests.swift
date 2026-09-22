import Foundation
import Testing
@testable import Domain

@Suite("Money input parsing")
struct MoneyInputTests {

    @Test("Plain decimal amounts parse to cents", arguments: [
        ("0", 0), ("1", 100), ("1.5", 150), ("1.50", 150),
        ("12.34", 1_234), ("0.09", 9), ("100.00", 10_000)
    ])
    func plainAmounts(input: String, expected: Int) {
        #expect(MoneyInput.cents(from: input) == expected)
    }

    @Test("Grouped input is read as whole units, not as a decimal")
    func groupedInput() {
        #expect(MoneyInput.cents(from: "1,234") == 123_400)
        #expect(MoneyInput.cents(from: "1,234.56") == 123_456)
        #expect(MoneyInput.cents(from: "1.234,56") == 123_456)
    }

    @Test("A separator followed by one or two digits is a decimal point")
    func trailingSeparatorIsDecimal() {
        #expect(MoneyInput.cents(from: "1,23") == 123)
        #expect(MoneyInput.cents(from: "1,2") == 120)
    }

    @Test("A leading minus is preserved")
    func negativeAmounts() {
        #expect(MoneyInput.cents(from: "-12.34") == -1_234)
        #expect(MoneyInput.cents(from: "\u{2212}12.34") == -1_234)
    }

    @Test("Currency symbols and spacing are ignored")
    func decoratedInput() {
        #expect(MoneyInput.cents(from: " $12.34 ") == 1_234)
        #expect(MoneyInput.cents(from: "£9.99") == 999)
    }

    @Test("Text with no digits does not parse", arguments: ["", "   ", "abc", ".", ","])
    func rejectsNonNumeric(input: String) {
        #expect(MoneyInput.cents(from: input) == nil)
    }

    @Test("Absurdly long input is rejected rather than overflowing")
    func rejectsOverflow() {
        #expect(MoneyInput.cents(from: String(repeating: "9", count: 30)) == nil)
    }

    @Test("Round-tripping cents through editable text preserves the value", arguments: [
        0, 5, 99, 100, 1_234, -1_234, 123_456_789
    ])
    func roundTrip(cents: Int) {
        let text = MoneyInput.editableText(fromCents: cents)
        #expect(MoneyInput.cents(from: text) == cents)
    }
}
