import Foundation
import Testing
@testable import Features
import Domain

/// Receipts that run to more than one page (§9.3).
///
/// A transaction stores one receipt identifier, so the pages have to be recoverable
/// from the store itself. The case that matters is removal: dropping only page one
/// would leave the rest behind, reachable by nothing and counted against no cap.
@MainActor
@Suite("Multi-page receipts")
struct ReceiptPagesTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The store fake.
        let store: FakeReceiptStore
        /// The coordinator under test.
        let coordinator: ReceiptStorageCoordinator
    }

    /// Builds a coordinator over empty stores.
    /// - Returns: The harness.
    private func makeHarness() -> Harness {
        let accounts = FakeAccountRepository()
        let store = FakeReceiptStore()
        return Harness(
            store: store,
            coordinator: ReceiptStorageCoordinator(
                store: store,
                transactions: FakeTransactionRepository(accounts: accounts),
                backups: FakeBackupWriter(),
                settings: AppSettings()
            )
        )
    }

    /// A transaction a receipt can belong to, at a fixed date.
    private var purchase: Domain.Transaction {
        Domain.Transaction(
            amountCents: 4_210,
            type: .expense,
            accountID: UUID(),
            date: Date(timeIntervalSince1970: 1_789_000_000),
            merchant: "Whole Foods"
        )
    }

    /// Three pages of bytes, each distinguishable from the others.
    private var pages: [Data] {
        [Data(repeating: 1, count: 64), Data(repeating: 2, count: 64), Data(repeating: 3, count: 64)]
    }

    @Test("Page one keeps the identifier the transaction stores")
    func pageOneIsTheTransactionsReceipt() {
        let harness = makeHarness()
        let transaction = purchase
        let expected = ReceiptNaming.fileID(
            date: transaction.date,
            merchant: transaction.merchant,
            amountCents: transaction.amountCents,
            ownerID: transaction.id
        )

        let ids = harness.coordinator.capturePages(pages, for: transaction)

        #expect(ids.first == expected)
    }

    @Test("Later pages are siblings, not separate receipts")
    func laterPagesAreSiblings() {
        let harness = makeHarness()

        let ids = harness.coordinator.capturePages(pages, for: purchase)

        #expect(ids.count == 3)
        let base = try? #require(ids.first)
        for id in ids.dropFirst() {
            #expect(ReceiptNaming.isPage(id, ofBaseFileID: base ?? ""))
        }
    }

    @Test("Capturing nothing attaches nothing")
    func emptyCaptureIsANoOp() {
        let harness = makeHarness()

        let ids = harness.coordinator.capturePages([], for: purchase)

        #expect(ids.isEmpty)
    }

    @Test("Every page is uploaded, not just the first")
    func flushUploadsEveryPage() async {
        let harness = makeHarness()
        harness.coordinator.capturePages(pages, for: purchase)

        await harness.coordinator.flushUploads()

        let stored = await harness.store.files.count
        #expect(stored == 3)
    }

    @Test("Every page is found again from the store after a relaunch")
    func pagesSurviveAnEmptyCache() async {
        let harness = makeHarness()
        let transaction = purchase
        let ids = harness.coordinator.capturePages(pages, for: transaction)
        await harness.coordinator.flushUploads()
        await harness.coordinator.clearCache()
        let base = try? #require(ids.first)

        let found = await harness.coordinator.pages(for: base ?? "")

        #expect(found.count == 3, "the cache is memory-only, so the store is the record")
        #expect(found.first == base, "page one leads")
    }

    @Test("Removing a receipt removes every page of it")
    func discardRemovesEveryPage() async {
        let harness = makeHarness()
        let ids = harness.coordinator.capturePages(pages, for: purchase)
        await harness.coordinator.flushUploads()
        let base = try? #require(ids.first)

        await harness.coordinator.discard(fileID: base ?? "")

        let remaining = await harness.store.files.count
        #expect(remaining == 0, "pages 2 and 3 would otherwise be unreachable forever")
    }

    @Test("Removing one receipt leaves another transaction's pages alone")
    func discardSparesOtherReceipts() async {
        let harness = makeHarness()
        let mine = harness.coordinator.capturePages(pages, for: purchase)
        let theirs = harness.coordinator.capturePages(pages, for: purchase)
        await harness.coordinator.flushUploads()
        let base = try? #require(mine.first)

        await harness.coordinator.discard(fileID: base ?? "")

        let remaining = await harness.store.files.keys.sorted()
        #expect(remaining.count == theirs.count)
    }
}
