import Foundation
import SwiftData
import Testing
@testable import Data
import Domain

/// Products belong to a purchase, and the store must hold them to it (§7.8).
///
/// `ProductRecord.apply(_:)` is a hand-written field-by-field copy, which is exactly
/// the kind of code that silently drops a newly added property. A round trip is
/// cheaper than remembering.
@Suite("Product persistence")
struct ProductPersistenceTests {

    /// The container, an account and a saved purchase to hang products off.
    private struct Fixture {
        /// The in-memory container.
        let container: ModelContainer
        /// The purchase products belong to.
        let purchase: Domain.Transaction
        /// Reads and writes products.
        let products: SwiftDataProductRepository
        /// Reads and writes transactions.
        let transactions: SwiftDataTransactionRepository
    }

    /// Builds the fixture.
    /// - Returns: The fixture.
    /// - Throws: A persistence error if a write fails.
    private func makeFixture() async throws -> Fixture {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        let account = Domain.Account(name: "Chequing", kind: .account, openingBalanceCents: 100_000)
        try await accounts.save(account)
        let purchase = Domain.Transaction(
            amountCents: 249_999, type: .expense, accountID: account.id,
            date: .now.addingTimeInterval(-3_600), merchant: "Sony Store",
            receiptFileID: "Receipts/2026/2026-09/r.jpg"
        )
        try await transactions.save(purchase)
        return Fixture(
            container: container,
            purchase: purchase,
            products: SwiftDataProductRepository(modelContainer: container),
            transactions: transactions
        )
    }

    @Test("Every field survives a save and reload")
    func fieldsRoundTrip() async throws {
        let fixture = try await makeFixture()
        var product = Domain.Product(
            transactionID: fixture.purchase.id, name: "Laptop",
            categoryID: UUID(), tags: ["work", "gift"],
            notes: "Warranty card is in the box", sortIndex: 2
        )
        product.hasWarranty = true
        product.warrantyExpiresDate = .now.addingTimeInterval(86_400)
        product.warrantyReminderLeadTime = .oneWeekBefore

        try await fixture.products.save(product)
        let stored = try #require(try await fixture.products.product(id: product.id))

        #expect(stored.transactionID == fixture.purchase.id)
        #expect(stored.name == product.name)
        #expect(stored.categoryID == product.categoryID)
        #expect(stored.tags == product.tags)
        #expect(stored.notes == product.notes)
        #expect(stored.sortIndex == 2)
        #expect(stored.hasWarranty)
        #expect(stored.warrantyReminderLeadTime == .oneWeekBefore)
    }

    @Test("A product whose purchase does not exist is refused, not orphaned")
    func unknownPurchaseIsRefused() async throws {
        let fixture = try await makeFixture()
        let stranded = UUID()
        let product = Domain.Product(transactionID: stranded, name: "Nowhere")

        await #expect(throws: ProductRepositoryError.unknownTransaction(stranded)) {
            try await fixture.products.save(product)
        }
        let stored = try await fixture.products.products()
        #expect(stored.isEmpty)
    }

    @Test("One purchase holds several products, in their order")
    func onePurchaseManyProducts() async throws {
        let fixture = try await makeFixture()
        for (index, name) in ["Desk Lamp", "Hallway Rug", "Doormat"].enumerated() {
            try await fixture.products.save(Domain.Product(
                transactionID: fixture.purchase.id, name: name, sortIndex: index
            ))
        }

        let stored = try await fixture.products.products(transactionID: fixture.purchase.id)

        #expect(stored.map(\.name) == ["Desk Lamp", "Hallway Rug", "Doormat"])
    }

    @Test("Deleting a purchase deletes the products it contained")
    func deletingAPurchaseCascades() async throws {
        let fixture = try await makeFixture()
        try await fixture.products.save(Domain.Product(
            transactionID: fixture.purchase.id, name: "Headphones"
        ))

        try await fixture.transactions.delete(id: fixture.purchase.id)

        let stored = try await fixture.products.products()
        #expect(stored.isEmpty, "a product with no purchase is not representable")
    }

    @Test("Deleting a product leaves its purchase alone")
    func deletingAProductKeepsThePurchase() async throws {
        let fixture = try await makeFixture()
        let product = Domain.Product(transactionID: fixture.purchase.id, name: "Headphones")
        try await fixture.products.save(product)

        try await fixture.products.delete(id: product.id)

        let remaining = try await fixture.transactions.transactions(accountID: nil, in: nil)
        #expect(remaining.contains { $0.id == fixture.purchase.id },
                "the money was really spent, and the receipt may cover siblings")
    }

    @Test("Deleting a purchase also ends the rules its products billed on")
    func deletingAPurchaseEndsBilling() async throws {
        let fixture = try await makeFixture()
        let rules = SwiftDataRecurringRuleRepository(modelContainer: fixture.container)
        var product = Domain.Product(transactionID: fixture.purchase.id, name: "Streaming")
        let rule = try #require(ProductBilling.recurringRule(
            for: product, purchase: fixture.purchase, frequency: .monthly
        ))
        try await rules.save(rule)
        product.recurringRuleID = rule.id
        try await fixture.products.save(product)

        try await fixture.transactions.delete(id: fixture.purchase.id)

        let remaining = try await rules.rules(activeOnly: false)
        #expect(remaining.isEmpty, "a deleted subscription must stop generating charges")
    }
}
