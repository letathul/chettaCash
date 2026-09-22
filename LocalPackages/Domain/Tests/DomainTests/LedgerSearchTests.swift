import Foundation
import Testing
@testable import Domain

/// The text, tag and receipt clauses ``LedgerFilter`` gained for global search (§7.12).
///
/// The period, account and category clauses are covered by ``LedgerTests``; these cover
/// only what search added, and that adding it left the old behaviour alone.
@Suite("Ledger search filtering")
struct LedgerSearchTests {

    /// A fixed calendar so month boundaries never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: Noon on that day, which keeps it clear of boundary instants.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    /// The moment every test in this suite filters against.
    private var reference: Date { date(2026, 9, 15) }

    /// One transaction dated inside the reference month.
    /// - Parameters:
    ///   - merchant: The merchant name.
    ///   - memo: The optional note.
    ///   - location: The optional place.
    ///   - tags: The transaction's tags.
    ///   - receiptFileID: The attached receipt, if any.
    /// - Returns: The transaction.
    private func transaction(
        merchant: String = "",
        memo: String? = nil,
        location: String? = nil,
        tags: [String] = [],
        receiptFileID: String? = nil
    ) -> Transaction {
        Transaction(
            amountCents: 1_000,
            type: .expense,
            date: date(2026, 9, 10),
            merchant: merchant,
            location: location,
            memo: memo,
            tags: tags,
            receiptFileID: receiptFileID
        )
    }

    /// Applies a filter over all time, which is what the search screen defaults to.
    /// - Parameters:
    ///   - filter: The filter under test.
    ///   - transactions: The transactions to filter.
    /// - Returns: The matches.
    private func apply(
        _ filter: LedgerFilter,
        to transactions: [Transaction]
    ) -> [Transaction] {
        filter.apply(to: transactions, reference: reference, calendar: calendar)
    }

    // MARK: - Text

    @Test("Search matches the merchant, the memo, the location or a tag")
    func searchSpansEveryTextField() {
        let byMerchant = transaction(merchant: "Sainsbury's")
        let byMemo = transaction(merchant: "Shop", memo: "Birthday present")
        let byLocation = transaction(merchant: "Shop", location: "Birmingham")
        let byTag = transaction(merchant: "Shop", tags: ["birthday"])
        let unrelated = transaction(merchant: "Petrol")
        let all = [byMerchant, byMemo, byLocation, byTag, unrelated]

        let matches = apply(
            LedgerFilter(period: .allTime, search: "bir"), to: all
        )

        #expect(Set(matches.map(\.id)) == Set([byMemo.id, byLocation.id, byTag.id]))
    }

    @Test("Search ignores case and surrounding whitespace")
    func searchIsCaseInsensitiveAndTrimmed() {
        let target = transaction(merchant: "Sainsbury's")

        let matches = apply(
            LedgerFilter(period: .allTime, search: "  SAINSBURY  "), to: [target]
        )

        #expect(matches.count == 1)
    }

    @Test("An empty search term excludes nothing")
    func emptySearchMatchesEverything() {
        let all = [transaction(merchant: "One"), transaction(merchant: "Two")]

        let matches = apply(LedgerFilter(period: .allTime, search: "   "), to: all)

        #expect(matches.count == 2)
    }

    // MARK: - Tags

    @Test("Selecting two tags narrows to transactions carrying both")
    func tagsAreAnded() {
        let both = transaction(merchant: "Both", tags: ["work", "travel"])
        let one = transaction(merchant: "One", tags: ["work"])
        let neither = transaction(merchant: "Neither")

        let matches = apply(
            LedgerFilter(period: .allTime, tags: ["work", "travel"]),
            to: [both, one, neither]
        )

        #expect(matches.map(\.id) == [both.id])
    }

    // MARK: - Receipts

    @Test("Has receipt excludes transactions with no image attached")
    func receiptsOnlyRequiresAnImage() {
        let withReceipt = transaction(merchant: "Scanned", receiptFileID: "abc")
        let without = transaction(merchant: "Typed")

        let matches = apply(
            LedgerFilter(period: .allTime, receiptsOnly: true),
            to: [withReceipt, without]
        )

        #expect(matches.map(\.id) == [withReceipt.id])
    }

    // MARK: - Narrowing

    @Test("A filter carrying only a period is not narrowing anything")
    func defaultFilterIsNotNarrowing() {
        #expect(!LedgerFilter().isNarrowing)
        #expect(!LedgerFilter(period: .allTime).isNarrowing)
        #expect(LedgerFilter(period: .allTime, search: "tea").isNarrowing)
        #expect(LedgerFilter(period: .allTime, tags: ["work"]).isNarrowing)
        #expect(LedgerFilter(period: .allTime, receiptsOnly: true).isNarrowing)
    }

    @Test("The clauses search added leave a plain period-and-account filter alone")
    func existingBehaviourIsUnchanged() {
        let inside = transaction(merchant: "September")
        var outside = transaction(merchant: "July")
        outside.date = date(2026, 7, 10)

        let matches = apply(LedgerFilter(period: .thisMonth), to: [inside, outside])

        #expect(matches.map(\.id) == [inside.id])
    }
}
