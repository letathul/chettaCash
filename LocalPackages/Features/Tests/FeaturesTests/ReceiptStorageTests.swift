import Foundation
import Testing
@testable import Features
import Domain

/// Phase 13 acceptance criterion: clearing the cache skips a pending upload (§9.5).
@MainActor
@Suite("Receipt storage")
struct ReceiptStorageTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The store fake.
        let store: FakeReceiptStore
        /// The backup writer fake.
        let backups: FakeBackupWriter
        /// The shared preferences object.
        let settings: AppSettings
        /// The coordinator under test.
        let coordinator: ReceiptStorageCoordinator
    }

    /// Builds a coordinator over empty stores.
    /// - Parameter capMB: The cache cap, or `0` for unlimited.
    /// - Returns: The harness.
    private func makeHarness(capMB: Int = 200) -> Harness {
        let accounts = FakeAccountRepository()
        let store = FakeReceiptStore()
        let backups = FakeBackupWriter()
        let settings = AppSettings()
        settings.receiptCacheCapMB = capMB
        return Harness(
            store: store, backups: backups, settings: settings,
            coordinator: ReceiptStorageCoordinator(
                store: store,
                transactions: FakeTransactionRepository(accounts: accounts),
                backups: backups,
                settings: settings
            )
        )
    }

    /// Builds a transaction a receipt can belong to.
    /// - Parameter merchant: The merchant name.
    /// - Returns: The transaction.
    private func transaction(merchant: String = "Whole Foods") -> Domain.Transaction {
        Domain.Transaction(
            amountCents: 4_210, type: .expense, accountID: UUID(),
            date: .now.addingTimeInterval(-3_600), merchant: merchant
        )
    }

    @Test("A captured receipt is cached immediately and marked as waiting")
    func captureIsImmediate() async {
        let harness = makeHarness()

        harness.coordinator.capture(Data(repeating: 1, count: 1_024), for: transaction())

        let summary = await harness.coordinator.cacheSummary()
        #expect(summary.contains("waiting to upload"))

        let status = await harness.coordinator.status()
        guard case .pendingUploads(let count) = status.state else {
            Issue.record("Expected pending uploads")
            return
        }
        #expect(count == 1)
    }

    @Test("Flushing uploads the receipt and clears the pending state")
    func flushUploads() async {
        let harness = makeHarness()
        let id = harness.coordinator.capture(Data(repeating: 1, count: 1_024), for: transaction())

        await harness.coordinator.flushUploads()

        let stored = await harness.store.files
        #expect(stored[id] != nil)
        let status = await harness.coordinator.status()
        guard case .upToDate = status.state else {
            Issue.record("Expected the status to settle")
            return
        }
    }

    @Test("Clearing the cache skips a receipt that has not uploaded")
    func clearingSkipsPending() async {
        let harness = makeHarness()
        let uploaded = harness.coordinator.capture(
            Data(repeating: 1, count: 1_024), for: transaction(merchant: "Uploaded")
        )
        await harness.coordinator.flushUploads()
        let pending = harness.coordinator.capture(
            Data(repeating: 2, count: 1_024), for: transaction(merchant: "Pending")
        )

        await harness.coordinator.clearCache()

        let summary = await harness.coordinator.cacheSummary()
        #expect(summary.contains("1 waiting to upload"),
                "the pending receipt survives the clear")
        #expect(uploaded != pending)
    }

    @Test("A failed upload is retried on the next flush rather than lost")
    func failedUploadIsRetried() async {
        let harness = makeHarness()
        await harness.store.failNextUpload(CocoaError(.fileWriteUnknown))
        let id = harness.coordinator.capture(
            Data(repeating: 1, count: 1_024), for: transaction()
        )

        await harness.coordinator.flushUploads()
        let afterFailure = await harness.coordinator.status()
        guard case .error = afterFailure.state else {
            Issue.record("Expected the failure to surface")
            return
        }

        await harness.coordinator.flushUploads()
        let stored = await harness.store.files
        #expect(stored[id] != nil, "the retry succeeded")
    }

    @Test("Clearing the cache after upload removes it")
    func clearingRemovesUploaded() async {
        let harness = makeHarness()
        harness.coordinator.capture(Data(repeating: 1, count: 1_024), for: transaction())
        await harness.coordinator.flushUploads()

        await harness.coordinator.clearCache()

        let summary = await harness.coordinator.cacheSummary()
        #expect(summary.contains("Zero") || summary.contains("0 bytes") || summary.hasPrefix("0"))
    }

    @Test("A receipt filename carries its date, merchant and amount")
    func capturedFileNameIsReadable() async {
        let harness = makeHarness()
        let entry = transaction(merchant: "Whole Foods")

        let id = harness.coordinator.capture(Data(repeating: 1, count: 16), for: entry)

        #expect(id.contains("Receipts/"))
        #expect(id.contains("whole-foods"))
        #expect(id.contains("42.10"))
    }

    @Test("Backing up writes an archive into the store")
    func backUpWritesArchive() async throws {
        let harness = makeHarness()

        try await harness.coordinator.backUpNow()

        #expect(harness.backups.writeCount == 1)
        let summary = await harness.coordinator.lastBackupSummary()
        #expect(summary.contains("test-backup.zip"))
    }

    @Test("With no archive written yet, the summary says so")
    func noBackupYet() async {
        let harness = makeHarness()

        let summary = await harness.coordinator.lastBackupSummary()

        #expect(summary == "No backup written yet.")
    }
}

/// Phase 14: a scheduled backup actually fires on foreground (§9.4).
@MainActor
@Suite("Scheduled backups")
struct ScheduledBackupTests {

    /// The pieces under test, wired together.
    private struct Harness {
        /// The store fake.
        let store: FakeReceiptStore
        /// The backup writer fake.
        let backups: FakeBackupWriter
        /// The coordinator under test.
        let coordinator: ReceiptStorageCoordinator
    }

    /// Builds a coordinator with a chosen backup interval.
    /// - Parameter interval: The interval to set.
    /// - Returns: The harness.
    private func makeCoordinator(interval: BackupInterval) -> Harness {
        let accounts = FakeAccountRepository()
        let store = FakeReceiptStore()
        let backups = FakeBackupWriter()
        let settings = AppSettings()
        settings.backupInterval = interval
        return Harness(store: store, backups: backups, coordinator: ReceiptStorageCoordinator(
            store: store,
            transactions: FakeTransactionRepository(accounts: accounts),
            backups: backups,
            settings: settings
        ))
    }

    @Test("With backups off, nothing is written")
    func offWritesNothing() async {
        let harness = makeCoordinator(interval: .off)
        let (backups, coordinator) = (harness.backups, harness.coordinator)

        let wrote = await coordinator.writeScheduledBackupIfDue()

        #expect(wrote == false)
        #expect(backups.writeCount == 0)
    }

    @Test("The first scheduled run writes an archive")
    func firstRunWrites() async {
        let harness = makeCoordinator(interval: .weekly)
        let (backups, coordinator) = (harness.backups, harness.coordinator)

        let wrote = await coordinator.writeScheduledBackupIfDue()

        #expect(wrote)
        #expect(backups.writeCount == 1)
    }

    @Test("A second foreground on the same day writes nothing further")
    func doesNotWriteTwiceInAPeriod() async {
        let harness = makeCoordinator(interval: .weekly)
        let (store, backups, coordinator) =
            (harness.store, harness.backups, harness.coordinator)
        // Stand in for an archive written today, named the way the writer names them.
        _ = try? await store.writeBackup(
            Data(), named: BackupArchive.fileName(for: .now)
        )

        let wrote = await coordinator.writeScheduledBackupIfDue()

        #expect(wrote == false)
        #expect(backups.writeCount == 0)
    }

    @Test("An archive older than the interval comes due again")
    func staleArchiveComesDue() async {
        let harness = makeCoordinator(interval: .weekly)
        let (store, backups, coordinator) =
            (harness.store, harness.backups, harness.coordinator)
        let old = Date.now.addingTimeInterval(-14 * 86_400)
        _ = try? await store.writeBackup(Data(), named: BackupArchive.fileName(for: old))

        let wrote = await coordinator.writeScheduledBackupIfDue()

        #expect(wrote)
        #expect(backups.writeCount == 1)
    }
}
