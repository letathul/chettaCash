import Foundation
import Testing
@testable import Domain

/// Working out which column of a bank's CSV is which, from the header alone (§9.7).
@Suite("CSV header matching")
struct CSVHeaderMatcherTests {

    @Test("A Chase export gives up its transaction date, not its posting date")
    func chaseHeaderPrefersTheTransactionDate() {
        let columns = CSVHeaderMatcher.columns(for: [
            "Transaction Date", "Post Date", "Description", "Category", "Type", "Amount"
        ])

        #expect(columns.transactionDate == "Transaction Date")
        #expect(columns.postingDate == "Post Date")
        #expect(columns.dateColumn == "Transaction Date")
        #expect(columns.descriptor == "Description")
        #expect(columns.amount == .single("Amount"))
    }

    @Test("A file with only a posting date uses it, because it is the only date there is")
    func postingDateStandsInWhenAlone() {
        let columns = CSVHeaderMatcher.columns(for: ["Posting Date", "Description", "Amount"])

        #expect(columns.transactionDate == nil)
        #expect(columns.dateColumn == "Posting Date")
        #expect(columns.isUsable)
    }

    @Test("An Amex export names its date simply Date")
    func bareDateIsRecognised() {
        let columns = CSVHeaderMatcher.columns(for: ["Date", "Description", "Amount"])

        #expect(columns.dateColumn == "Date")
        #expect(columns.amount == .single("Amount"))
    }

    @Test("A split debit and credit pair beats looking for one amount column")
    func splitColumnsAreRecognised() {
        let columns = CSVHeaderMatcher.columns(for: [
            "Date", "Description", "Debit", "Credit", "Balance"
        ])

        #expect(columns.amount == .debitCredit(debit: "Debit", credit: "Credit"))
    }

    @Test("British wording for a split pair is recognised too")
    func paidInAndPaidOutAreRecognised() {
        let columns = CSVHeaderMatcher.columns(for: [
            "Date", "Description", "Paid Out", "Paid In"
        ])

        #expect(columns.amount == .debitCredit(debit: "Paid Out", credit: "Paid In"))
    }

    @Test("No column is claimed by two fields at once")
    func aColumnIsClaimedOnlyOnce() {
        let columns = CSVHeaderMatcher.columns(for: ["Date", "Posted", "Description", "Amount"])

        // "Posted" is the posting date, so "Date" must be left for the transaction date
        // rather than both fields pointing at the same column.
        #expect(columns.postingDate == "Posted")
        #expect(columns.transactionDate == "Date")
    }

    @Test("A reference number is not mistaken for the description")
    func decoyColumnsAreLeftAlone() {
        let columns = CSVHeaderMatcher.columns(for: [
            "Date", "Reference Number", "Description", "Amount"
        ])

        #expect(columns.descriptor == "Description")
    }

    @Test("A header with no date at all is refused rather than half-read")
    func aHeaderWithoutADateIsUnusable() {
        let columns = CSVHeaderMatcher.columns(for: ["Description", "Amount"])

        #expect(!columns.isUsable)
    }

    @Test("Casing and spacing in a header never matter")
    func headersAreComparedOnTheirSlug() {
        let columns = CSVHeaderMatcher.columns(for: ["TRANSACTION DATE", "  Merchant ", "AMOUNT"])

        #expect(columns.dateColumn == "TRANSACTION DATE")
        #expect(columns.descriptor == "  Merchant ")
    }
}
