import Foundation
import Testing
import SwiftData
@testable import Data
@testable import Domain

/// Storing merchant-to-category pins (§4.8).
///
/// The pin is keyed by the normalised merchant rather than by its identifier, so the
/// interesting behaviour is the upsert: re-pinning a shop must replace what is there,
/// never leave two pins where only one can ever win.
@Suite("Merchant pin persistence")
struct MerchantRulePersistenceTests {

    /// A fixed moment, so results never depend on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// Builds a repository over an empty in-memory store.
    /// - Returns: The repository.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    private func makeRepository() throws -> SwiftDataMerchantCategoryRuleRepository {
        let container = try ModelContainerFactory.make(inMemory: true)
        return SwiftDataMerchantCategoryRuleRepository(modelContainer: container)
    }

    @Test("A pin round-trips through the store")
    func pinRoundTrips() async throws {
        let repository = try makeRepository()
        let categoryID = UUID()
        let pin = try #require(
            MerchantCategoryRule.make(
                merchant: "Whole Foods Mkt", categoryID: categoryID, updatedAt: now
            )
        )

        try await repository.save(pin)
        let stored = try await repository.rule(merchantKey: pin.merchantKey)

        #expect(stored == pin)
    }

    @Test("Re-pinning a merchant replaces the pin rather than adding a second")
    func upsertsOnMerchantKey() async throws {
        let repository = try makeRepository()
        let groceries = UUID()
        let household = UUID()
        let first = try #require(
            MerchantCategoryRule.make(
                merchant: "WHOLE FOODS MKT #10234", categoryID: groceries, updatedAt: now
            )
        )
        let second = try #require(
            MerchantCategoryRule.make(
                merchant: "Whole Foods Mkt", categoryID: household, updatedAt: now
            )
        )

        try await repository.save(first)
        try await repository.save(second)
        let all = try await repository.rules()

        #expect(all.count == 1, "two spellings of one shop are one pin")
        #expect(all.first?.categoryID == household, "the newer pin wins")
    }

    @Test("Two different merchants keep separate pins")
    func keepsDistinctMerchantsApart() async throws {
        let repository = try makeRepository()
        let loblaws = try #require(
            MerchantCategoryRule.make(merchant: "Loblaws", categoryID: UUID(), updatedAt: now)
        )
        let canadianTire = try #require(
            MerchantCategoryRule.make(
                merchant: "Canadian Tire", categoryID: UUID(), updatedAt: now
            )
        )

        try await repository.save(loblaws)
        try await repository.save(canadianTire)
        let all = try await repository.rules()

        #expect(all.count == 2)
    }

    @Test("Pins come back most recently updated first")
    func ordersByRecency() async throws {
        let repository = try makeRepository()
        let older = try #require(
            MerchantCategoryRule.make(
                merchant: "Loblaws", categoryID: UUID(),
                updatedAt: now.addingTimeInterval(-86_400)
            )
        )
        let newer = try #require(
            MerchantCategoryRule.make(
                merchant: "Canadian Tire", categoryID: UUID(), updatedAt: now
            )
        )

        try await repository.save(older)
        try await repository.save(newer)
        let all = try await repository.rules()

        #expect(all.first?.merchantKey == newer.merchantKey)
    }

    @Test("Deleting a pin leaves the rest alone")
    func deletesOnePin() async throws {
        let repository = try makeRepository()
        let loblaws = try #require(
            MerchantCategoryRule.make(merchant: "Loblaws", categoryID: UUID(), updatedAt: now)
        )
        let canadianTire = try #require(
            MerchantCategoryRule.make(
                merchant: "Canadian Tire", categoryID: UUID(), updatedAt: now
            )
        )
        try await repository.save(loblaws)
        try await repository.save(canadianTire)

        try await repository.delete(id: loblaws.id)
        let all = try await repository.rules()

        #expect(all.count == 1)
        #expect(all.first?.merchantKey == canadianTire.merchantKey)
    }

    @Test("An unpinned merchant reads back as nothing")
    func unknownMerchantHasNoPin() async throws {
        let repository = try makeRepository()

        let stored = try await repository.rule(merchantKey: "canadian-tire")

        #expect(stored == nil)
    }

    @Test("An empty key matches nothing rather than the first row")
    func emptyKeyMatchesNothing() async throws {
        let repository = try makeRepository()
        let pin = try #require(
            MerchantCategoryRule.make(merchant: "Loblaws", categoryID: UUID(), updatedAt: now)
        )
        try await repository.save(pin)

        let stored = try await repository.rule(merchantKey: "")

        #expect(stored == nil, "a merchant that normalises to nothing must not borrow a pin")
    }
}
