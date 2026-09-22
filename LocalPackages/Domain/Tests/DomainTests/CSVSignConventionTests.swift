import Foundation
import Testing
@testable import Domain

/// Working out whether a positive figure in a bank's CSV is a purchase or a credit (§9.7).
@Suite("CSV sign convention")
struct CSVSignConventionTests {

    /// Builds the entries the inference reads.
    /// - Parameter pairs: Each row's descriptor and figure, the figure written as text.
    /// - Returns: The entries.
    private func entries(_ pairs: [(String, String)]) -> [(descriptor: String, amount: Decimal)] {
        pairs.compactMap { descriptor, amount in
            Decimal(string: amount).map { (descriptor: descriptor, amount: $0) }
        }
    }

    @Test("A payment printed positive means negative figures are the charges")
    func positivePaymentImpliesNegativeCharges() {
        // Chase: purchases negative, the payment that clears them positive.
        let convention = CSVSignConvention.infer(from: entries([
            ("BLUE BOTTLE", "-6.75"),
            ("PAYMENT THANK YOU", "500.00")
        ]))

        #expect(convention == .negativeIsCharge)
    }

    @Test("A payment printed negative means positive figures are the charges")
    func negativePaymentImpliesPositiveCharges() {
        // American Express: purchases positive, the payment negative.
        let convention = CSVSignConvention.infer(from: entries([
            ("BLUE BOTTLE", "6.75"),
            ("PAYMENT RECEIVED - THANK YOU", "-500.00")
        ]))

        #expect(convention == .positiveIsCharge)
    }

    @Test("With no payment line the majority sign is taken as the charge sign")
    func majoritySignDecidesWhenNoPaymentIsPrinted() {
        let convention = CSVSignConvention.infer(from: entries([
            ("BLUE BOTTLE", "6.75"),
            ("AMAZON", "41.20"),
            ("REFUND", "-9.99")
        ]))

        #expect(convention == .positiveIsCharge)
    }

    @Test("A payment outvotes the majority, because it is evidence rather than a guess")
    func aPaymentBeatsTheMajority() {
        let convention = CSVSignConvention.infer(from: entries([
            ("BLUE BOTTLE", "6.75"),
            ("AMAZON", "41.20"),
            ("AUTOPAY THANK YOU", "-500.00")
        ]))

        #expect(convention == .positiveIsCharge)
    }

    @Test("A file with nothing in it falls back to the commoner convention")
    func anEmptyFileFallsBack() {
        #expect(CSVSignConvention.infer(from: []) == .negativeIsCharge)
    }

    @Test("Zero-value rows never decide the convention")
    func zeroesAreIgnored() {
        let convention = CSVSignConvention.infer(from: entries([
            ("FREE SAMPLE", "0.00"),
            ("BLUE BOTTLE", "6.75")
        ]))

        #expect(convention == .positiveIsCharge)
    }

    @Test("The convention reads a figure back the way the file meant it")
    func creditIsReportedPerConvention() {
        #expect(CSVSignConvention.negativeIsCharge.isCredit(Decimal(50)))
        #expect(!CSVSignConvention.negativeIsCharge.isCredit(Decimal(-50)))
        #expect(CSVSignConvention.positiveIsCharge.isCredit(Decimal(-50)))
        #expect(!CSVSignConvention.positiveIsCharge.isCredit(Decimal(50)))
    }
}
