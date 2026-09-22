import Foundation
import Testing
@testable import Domain

/// A subscription product's billing rule (§7.7, §4.5).
///
/// The rule's amount comes from the **purchase**: a product carries no price of its
/// own, so there is nowhere else for it to come from.
@Suite("Product billing")
struct ProductBillingTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment every test evaluates against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)) ?? .now
    }

    /// A date offset from ``now`` by whole days.
    /// - Parameter days: Days to offset.
    /// - Returns: The offset date.
    private func day(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    /// Builds a purchase.
    /// - Parameters:
    ///   - merchant: Where it was bought.
    ///   - cents: What it cost.
    ///   - accountID: The account it was paid from.
    /// - Returns: The transaction.
    private func purchase(
        merchant: String = "Streaming",
        cents: Int = 999,
        accountID: UUID? = nil
    ) -> Transaction {
        Transaction(
            amountCents: cents, type: .expense, accountID: accountID ?? UUID(),
            date: day(-10), merchant: merchant
        )
    }

    @Test("A subscription's rule takes its amount from the purchase")
    func recurringChargeCreatesRule() throws {
        let bought = purchase(merchant: "Streaming", cents: 999, accountID: UUID())
        var product = Product(transactionID: bought.id, name: "Streaming")
        product.categoryID = UUID()

        let rule = try #require(
            ProductBilling.recurringRule(for: product, purchase: bought, frequency: .monthly)
        )

        #expect(rule.name == "Streaming")
        #expect(rule.amountCents == 999, "the product has no price of its own")
        #expect(rule.type == .expense)
        #expect(rule.accountID == bought.accountID)
        #expect(rule.categoryID == product.categoryID)
        #expect(rule.productID == product.id)
        #expect(rule.isActive)
    }

    @Test("A free purchase bills nothing")
    func freePurchaseCreatesNoRule() {
        let bought = purchase(cents: 0, accountID: UUID())
        let product = Product(transactionID: bought.id, name: "Hand-me-down")

        #expect(ProductBilling.recurringRule(
            for: product, purchase: bought, frequency: .monthly
        ) == nil)
    }

    @Test("The first charge falls one period after purchase, not on it")
    func firstChargeIsAfterPurchase() throws {
        let bought = purchase(cents: 999, accountID: UUID())
        let product = Product(transactionID: bought.id, name: "Streaming")

        let rule = try #require(
            ProductBilling.recurringRule(for: product, purchase: bought, frequency: .monthly)
        )

        #expect(rule.startDate > bought.date)
        #expect(rule.startDate == calendar.date(byAdding: .month, value: 1, to: bought.date))
    }

    @Test("The rule generates real Ledger occurrences through the Phase 6 engine")
    func ruleGeneratesLedgerTransactions() throws {
        let bought = purchase(cents: 999, accountID: UUID())
        let product = Product(transactionID: bought.id, name: "Streaming")
        let rule = try #require(
            ProductBilling.recurringRule(for: product, purchase: bought, frequency: .monthly)
        )

        let outcome = RecurringEngine.reconcile(
            rules: [rule], existingTransactions: [], now: day(70), calendar: calendar
        )

        #expect(outcome.newTransactions.count >= 2)
        #expect(outcome.newTransactions.allSatisfy { $0.recurringRuleID == rule.id })
        #expect(outcome.newTransactions.allSatisfy { $0.amountCents == 999 })
        #expect(outcome.newTransactions.allSatisfy { $0.accountID == bought.accountID })
    }

    @Test("A product that already has a rule never gets a second")
    func neverCreatesSecondRule() {
        let bought = purchase(cents: 999, accountID: UUID())
        var product = Product(transactionID: bought.id, name: "Streaming")
        product.recurringRuleID = UUID()

        #expect(ProductBilling.recurringRule(
            for: product, purchase: bought, frequency: .monthly
        ) == nil)
    }

    @Test("Editing a subscription updates its rule without moving the schedule")
    func editingUpdatesRuleInPlace() throws {
        let bought = purchase(cents: 999, accountID: UUID())
        var product = Product(transactionID: bought.id, name: "Streaming")
        let original = try #require(
            ProductBilling.recurringRule(for: product, purchase: bought, frequency: .monthly)
        )

        product.name = "Streaming Plus"
        var dearer = bought
        dearer.amountCents = 1_499
        let updated = ProductBilling.updated(
            original, from: product, purchase: dearer, frequency: .monthly
        )

        #expect(updated.id == original.id)
        #expect(updated.name == "Streaming Plus")
        #expect(updated.amountCents == 1_499)
        #expect(updated.startDate == original.startDate, "the schedule is not moved")
    }
}
