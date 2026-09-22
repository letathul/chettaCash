import Foundation
import Testing
@testable import Domain

/// Resolving a scan against the user's own accounts, categories and history (§9.7).
///
/// This is where a receipt's *words* become the user's *data*. The rules that matter:
/// history outranks the reader, a reader's label must name a category that already
/// exists, and nothing is ever created.
@Suite("Receipt prefill")
struct ReceiptPrefillBuilderTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// A fixed moment, so results never depend on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// The user's expense categories.
    private let groceries = Domain.Category(label: "Groceries", context: .expense)
    private let foodAndDrink = Domain.Category(label: "Food & drink", context: .expense)
    private let salary = Domain.Category(label: "Salary", context: .income)

    /// Every category the fixture user has.
    private var categories: [Domain.Category] { [groceries, foodAndDrink, salary] }

    /// Builds a past purchase at this merchant.
    /// - Parameters:
    ///   - merchant: The merchant name.
    ///   - categoryID: The category the user gave it.
    ///   - tags: The tags the user gave it.
    /// - Returns: The transaction.
    private func purchase(_ merchant: String, categoryID: UUID?, tags: [String] = []) -> Transaction {
        Transaction(categoryID: categoryID, date: now, merchant: merchant, tags: tags)
    }

    /// Builds the prefill for a scan.
    /// - Parameters:
    ///   - scan: What the receipt said.
    ///   - accounts: The user's accounts.
    ///   - history: The user's past transactions.
    ///   - context: Which picker the form is showing.
    /// - Returns: The prefill.
    private func prefill(
        _ scan: ReceiptScanResult,
        accounts: [Account] = [],
        history: [Transaction] = [],
        context: CategoryContext = .expense
    ) -> ReceiptPrefill {
        ReceiptPrefillBuilder.prefill(
            from: scan,
            resolvedAgainst: ReceiptResolutionContext(
                accounts: accounts,
                categories: categories,
                history: history,
                categoryContext: context
            )
        )
    }

    // MARK: - Category

    @Test("What the user chose for this merchant before beats what the reader says")
    func historyBeatsTheReader() {
        let scan = ReceiptScanResult(merchant: "Loblaws", categoryLabel: "Food & drink")
        let history = [purchase("Loblaws", categoryID: groceries.id)]

        let result = prefill(scan, history: history)

        #expect(result.categoryID == groceries.id, "the user's own past decision wins")
        #expect(result.filled.contains(ReceiptField.category))
    }

    @Test("The reader's label is used for a merchant never seen before")
    func readerLabelUsedForNewMerchant() {
        let scan = ReceiptScanResult(merchant: "Canadian Tire", categoryLabel: "Groceries")

        #expect(prefill(scan).categoryID == groceries.id)
    }

    @Test("A label matches regardless of case and accents")
    func labelMatchingIsForgiving() {
        let scan = ReceiptScanResult(merchant: "Shop", categoryLabel: "  GROCERIES ")

        #expect(prefill(scan).categoryID == groceries.id)
    }

    @Test("A partial label reaches the category that contains it")
    func partialLabelMatches() {
        let scan = ReceiptScanResult(merchant: "Shop", categoryLabel: "Food")

        #expect(prefill(scan).categoryID == foodAndDrink.id)
    }

    @Test("A label naming no category of the user's is discarded")
    func unknownLabelIsDiscarded() {
        let scan = ReceiptScanResult(merchant: "Shop", categoryLabel: "Pet supplies")

        let result = prefill(scan)

        #expect(result.categoryID == nil, "a scan never invents a category")
        #expect(!result.filled.contains(ReceiptField.category))
    }

    @Test("Only the categories this form's picker offers can be chosen")
    func respectsTheCategoryContext() {
        let scan = ReceiptScanResult(merchant: "Shop", categoryLabel: "Groceries")

        #expect(prefill(scan, context: .income).categoryID == nil)
    }

    @Test("A remembered category the picker no longer offers falls back to the reader")
    func archivedHistoryFallsBackToTheReader() {
        let retired = Domain.Category(label: "Old", context: .expense, isArchived: true)
        let scan = ReceiptScanResult(merchant: "Loblaws", categoryLabel: "Groceries")
        let history = [purchase("Loblaws", categoryID: retired.id)]

        let result = ReceiptPrefillBuilder.prefill(
            from: scan,
            resolvedAgainst: ReceiptResolutionContext(
                categories: categories + [retired], history: history
            )
        )

        #expect(result.categoryID == groceries.id)
    }

    // MARK: - Account

    @Test("The card on the receipt selects its account")
    func matchesTheAccount() {
        let visa = Account(name: "TD Visa", kind: .card, last4: "4821", cardNetwork: .visa)
        let scan = ReceiptScanResult(
            merchant: "Loblaws", tender: ReceiptTender(last4: "4821", network: .visa)
        )

        let result = prefill(scan, accounts: [visa])

        #expect(result.accountID == visa.id)
        #expect(result.filled.contains(ReceiptField.account))
    }

    @Test("An unrecognised card leaves the account alone")
    func unknownCardLeavesTheAccountAlone() {
        let visa = Account(name: "TD Visa", kind: .card, last4: "4821", cardNetwork: .visa)
        let scan = ReceiptScanResult(merchant: "Loblaws", tender: ReceiptTender(last4: "7777"))

        let result = prefill(scan, accounts: [visa])

        #expect(result.accountID == nil)
        #expect(!result.filled.contains(ReceiptField.account))
    }

    // MARK: - Tags

    @Test("Tags this merchant usually gets are offered but never applied")
    func offersTagsWithoutApplyingThem() {
        let scan = ReceiptScanResult(merchant: "Loblaws")
        let history = [
            purchase("Loblaws", categoryID: groceries.id, tags: ["weekly shop"]),
            purchase("Loblaws", categoryID: groceries.id, tags: ["weekly shop"])
        ]

        let result = prefill(scan, history: history)

        #expect(result.suggestedTags == ["weekly shop"])
    }

    // MARK: - Reported fields

    @Test("Every field the scan filled is reported")
    func reportsFilledFields() {
        let visa = Account(name: "TD Visa", kind: .card, last4: "4821", cardNetwork: .visa)
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 1, hour: 18, minute: 42)
        )
        let scan = ReceiptScanResult(
            amountCents: 4_210,
            merchant: "Loblaws",
            date: date,
            location: "120 Bloor St W",
            categoryLabel: "Groceries",
            tender: ReceiptTender(last4: "4821")
        )

        let result = prefill(scan, accounts: [visa])

        #expect(result.filled == [.amount, .merchant, .date, .time, .location, .category, .account])
    }

    @Test("A date with no printed time reports the day but not the time")
    func middayIsNotReportedAsATime() {
        let midday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))
        let scan = ReceiptScanResult(merchant: "Loblaws", date: midday)

        let result = ReceiptPrefillBuilder.prefill(
            from: scan, resolvedAgainst: ReceiptResolutionContext(categories: categories)
        )

        #expect(result.filled.contains(ReceiptField.date))
        #expect(
            !ReceiptPrefillBuilder.carriesTime(midday ?? now, calendar: calendar),
            "midday is the fallback, not a time the receipt printed"
        )
    }

    @Test("A scan that read nothing produces an empty prefill")
    func emptyScanIsEmptyPrefill() {
        let result = prefill(ReceiptScanResult())

        #expect(result.isEmpty)
        #expect(result.filled.isEmpty)
        #expect(result.categoryID == nil)
        #expect(result.accountID == nil)
    }
}
