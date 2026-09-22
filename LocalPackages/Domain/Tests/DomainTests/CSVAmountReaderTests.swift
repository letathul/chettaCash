import Foundation
import Testing
@testable import Domain

/// Reading a bank's amount cell into an exact signed figure (§9.7, §2).
@Suite("CSV amount reading")
struct CSVAmountReaderTests {

    @Test("A grouped figure with a currency symbol reads exactly")
    func currencySymbolsAndGroupingAreStripped() {
        #expect(CSVAmountReader.signedAmount("$1,234.56") == Decimal(string: "1234.56"))
    }

    @Test("Parentheses are accountancy's minus sign")
    func parenthesesMeanNegative() {
        #expect(CSVAmountReader.signedAmount("(42.10)") == Decimal(string: "-42.10"))
    }

    @Test("Parentheses around a currency symbol still read as negative")
    func parenthesesWrapEverythingElse() {
        #expect(CSVAmountReader.signedAmount("($42.10)") == Decimal(string: "-42.10"))
    }

    @Test("A trailing CR is a credit and a trailing DR a debit")
    func directionSuffixesAreHonoured() {
        #expect(CSVAmountReader.signedAmount("42.10 CR") == Decimal(string: "42.10"))
        #expect(CSVAmountReader.signedAmount("42.10 DR") == Decimal(string: "-42.10"))
    }

    @Test("A currency code is not mistaken for a direction suffix")
    func currencyCodesSurvive() {
        // "USD" ends in D, which would read as a debit if the letters before it went unchecked.
        #expect(CSVAmountReader.signedAmount("42.10 USD") == Decimal(string: "42.10"))
    }

    @Test("Both spellings of a minus sign are accepted")
    func unicodeMinusIsAccepted() {
        #expect(CSVAmountReader.signedAmount("-42.10") == Decimal(string: "-42.10"))
        #expect(CSVAmountReader.signedAmount("\u{2212}42.10") == Decimal(string: "-42.10"))
    }

    @Test("A leading plus is a sign, not a digit")
    func leadingPlusIsAccepted() {
        #expect(CSVAmountReader.signedAmount("+42.10") == Decimal(string: "42.10"))
    }

    @Test("A European figure reads as the number it prints, not as thousands")
    func europeanSeparatorsAreRead() {
        #expect(CSVAmountReader.signedAmount("1.234,56") == Decimal(string: "1234.56"))
        #expect(CSVAmountReader.signedAmount("1,23") == Decimal(string: "1.23"))
    }

    @Test("A whole-thousands figure is not read as a fraction")
    func groupingWithNoFractionIsWhole() {
        #expect(CSVAmountReader.signedAmount("1,234") == Decimal(string: "1234"))
    }

    @Test("A cell holding no figure reads as nothing rather than as zero")
    func emptyAndUnreadableCellsAreRefused() {
        #expect(CSVAmountReader.signedAmount("") == nil)
        #expect(CSVAmountReader.signedAmount("   ") == nil)
        #expect(CSVAmountReader.signedAmount("n/a") == nil)
    }

    @Test("A figure marked negative twice is simply negative")
    func doubledNegativesDoNotCancel() {
        #expect(CSVAmountReader.signedAmount("(-42.10)") == Decimal(string: "-42.10"))
    }
}
