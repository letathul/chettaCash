import Foundation
import Testing
@testable import Domain

/// Learning a merchant's category and tags from the user's own history (§9.7).
///
/// The right category for a shop is not a universal fact — it is whatever this user
/// decided last time. These tests pin that down, and pin down the normalisation that
/// lets two spellings of one shop count as the same shop.
@Suite("Merchant category history")
struct MerchantCategoryIndexTests {

    /// A fixed moment, so results never depend on the wall clock.
    private var now: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// Builds a past purchase.
    /// - Parameters:
    ///   - merchant: The merchant name as printed.
    ///   - categoryID: The category the user gave it.
    ///   - tags: The tags the user gave it.
    ///   - daysAgo: How long ago it happened.
    /// - Returns: The transaction.
    private func purchase(
        _ merchant: String,
        categoryID: UUID? = nil,
        tags: [String] = [],
        daysAgo: Int = 0
    ) -> Transaction {
        Transaction(
            amountCents: 1_000,
            categoryID: categoryID,
            date: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400),
            merchant: merchant,
            tags: tags
        )
    }

    // MARK: - Normalisation

    @Test("Spellings of one shop collapse to one key", arguments: [
        "WHOLE FOODS MKT #10234",
        "Whole Foods Mkt",
        "whole foods mkt 10234",
        "  Whole  Foods  Mkt  "
    ])
    func normalisesSpellings(printed: String) {
        #expect(MerchantCategoryIndex.key(for: printed) == "whole-foods-mkt")
    }

    @Test("Accents do not separate two spellings of one shop")
    func foldsAccents() {
        #expect(MerchantCategoryIndex.key(for: "Café Olé") == MerchantCategoryIndex.key(for: "Cafe Ole"))
    }

    @Test("A name that is only a number keeps it")
    func keepsANumericName() {
        #expect(!MerchantCategoryIndex.key(for: "7-11").isEmpty)
    }

    @Test("An empty merchant has no key")
    func emptyMerchantHasNoKey() {
        #expect(MerchantCategoryIndex.key(for: "   ").isEmpty)
    }

    // MARK: - Category

    @Test("The category this merchant usually gets is the one returned")
    func returnsTheUsualCategory() {
        let groceries = UUID()
        let history = [
            purchase("WHOLE FOODS MKT #10234", categoryID: groceries, daysAgo: 30),
            purchase("Whole Foods Mkt", categoryID: groceries, daysAgo: 20),
            purchase("WHOLE FOODS", categoryID: UUID(), daysAgo: 10)
        ]

        let found = MerchantCategoryIndex.categoryID(for: "WHOLE FOODS MKT", in: history)

        #expect(found == groceries)
    }

    @Test("A single mis-tap does not overrule a habit")
    func mostUsedBeatsMostRecent() {
        let groceries = UUID()
        let mistake = UUID()
        let history = [
            purchase("Loblaws", categoryID: groceries, daysAgo: 40),
            purchase("Loblaws", categoryID: groceries, daysAgo: 30),
            purchase("Loblaws", categoryID: groceries, daysAgo: 20),
            purchase("Loblaws", categoryID: mistake, daysAgo: 1)
        ]

        let found = MerchantCategoryIndex.categoryID(for: "Loblaws", in: history)

        #expect(found == groceries, "three uses outweigh yesterday's slip")
    }

    @Test("A tie is broken by the more recent choice")
    func recencyBreaksTies() {
        let older = UUID()
        let newer = UUID()
        let history = [
            purchase("Loblaws", categoryID: older, daysAgo: 40),
            purchase("Loblaws", categoryID: newer, daysAgo: 2)
        ]

        #expect(MerchantCategoryIndex.categoryID(for: "Loblaws", in: history) == newer)
    }

    @Test("A system category is never learned")
    func ignoresSystemCategories() {
        let history = [
            purchase("Loblaws", categoryID: SystemCategoryID.transfer, daysAgo: 5),
            purchase("Loblaws", categoryID: SystemCategoryID.balanceAdjustment, daysAgo: 3)
        ]

        #expect(MerchantCategoryIndex.categoryID(for: "Loblaws", in: history) == nil)
    }

    @Test("A merchant never seen before has no category")
    func unknownMerchantHasNoCategory() {
        let history = [purchase("Loblaws", categoryID: UUID(), daysAgo: 5)]

        #expect(MerchantCategoryIndex.categoryID(for: "Canadian Tire", in: history) == nil)
    }

    @Test("Uncategorised history yields nothing rather than a guess")
    func uncategorisedHistoryYieldsNothing() {
        let history = [purchase("Loblaws", daysAgo: 5), purchase("Loblaws", daysAgo: 3)]

        #expect(MerchantCategoryIndex.categoryID(for: "Loblaws", in: history) == nil)
    }

    // MARK: - Tags

    @Test("A tag used twice on a merchant is suggested")
    func suggestsRepeatedTags() {
        let history = [
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 14),
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 7)
        ]

        #expect(MerchantCategoryIndex.tags(for: "Loblaws", in: history) == ["weekly shop"])
    }

    @Test("A tag used once is not suggested")
    func ignoresOneOffTags() {
        let history = [
            purchase("Loblaws", tags: ["party"], daysAgo: 14),
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 7),
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 1)
        ]

        let tags = MerchantCategoryIndex.tags(for: "Loblaws", in: history)

        #expect(tags == ["weekly shop"], "one use is not a habit")
    }

    @Test("Suggestions are ordered by how often they are used")
    func ordersTagsByUse() {
        let history = [
            purchase("Loblaws", tags: ["weekly shop", "shared"], daysAgo: 21),
            purchase("Loblaws", tags: ["weekly shop", "shared"], daysAgo: 14),
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 7)
        ]

        #expect(MerchantCategoryIndex.tags(for: "Loblaws", in: history) == ["weekly shop", "shared"])
    }

    @Test("The spelling the user typed is what comes back")
    func keepsTheUsersSpelling() {
        let history = [
            purchase("Loblaws", tags: ["Weekly Shop"], daysAgo: 14),
            purchase("Loblaws", tags: ["weekly shop"], daysAgo: 7)
        ]

        let tags = MerchantCategoryIndex.tags(for: "Loblaws", in: history)

        #expect(tags == ["Weekly Shop"], "case does not split one tag into two")
    }

    @Test("A merchant with no history suggests nothing")
    func noHistoryNoTags() {
        #expect(MerchantCategoryIndex.tags(for: "Canadian Tire", in: []).isEmpty)
    }
}
