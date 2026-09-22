import Foundation
import SwiftData
import Testing
import Domain
@testable import Data

/// Phase 13 acceptance criterion: a backup exported and re-imported produces zero
/// duplicates (§9.4). Exercised through a real `.zip` and a real SwiftData store.
@Suite("Backup export and import")
struct BackupServiceTests {

    /// A populated store and the service over it.
    private struct Harness {
        /// The in-memory container.
        let container: ModelContainer
        /// The service under test.
        let service: BackupService
        /// The account repository.
        let accounts: SwiftDataAccountRepository
        /// The transaction repository.
        let transactions: SwiftDataTransactionRepository
    }

    /// Builds a service over a fresh in-memory store.
    /// - Returns: The harness.
    private func makeHarness() throws -> Harness {
        let container = try ModelContainerFactory.make(inMemory: true)
        let accounts = SwiftDataAccountRepository(modelContainer: container)
        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        return Harness(
            container: container,
            service: BackupService(repositories: BackupRepositories(
                accounts: accounts,
                transactions: transactions,
                categories: SwiftDataCategoryRepository(modelContainer: container),
                recurringRules: SwiftDataRecurringRuleRepository(modelContainer: container),
                statements: SwiftDataCardStatementRepository(modelContainer: container),
                products: SwiftDataProductRepository(modelContainer: container),
                comparisons: SwiftDataComparisonRepository(modelContainer: container),
                merchantRules: SwiftDataMerchantCategoryRuleRepository(
                    modelContainer: container
                )
            )),
            accounts: accounts,
            transactions: transactions
        )
    }

    /// Seeds a store with a group, two accounts and two transactions.
    /// - Parameter harness: The harness to seed.
    /// - Returns: The seeded account.
    @discardableResult
    private func seed(_ harness: Harness) async throws -> Domain.Account {
        let group = Domain.AccountGroup(name: "Everyday")
        try await harness.accounts.save(group)
        let chequing = Domain.Account(
            name: "TD Chequing", openingBalanceCents: 100_000, groupID: group.id
        )
        let card = Domain.Account(
            name: "TD Visa", kind: .card, openingBalanceCents: -20_000, groupID: group.id
        )
        try await harness.accounts.save(chequing)
        try await harness.accounts.save(card)
        try await harness.transactions.save(Domain.Transaction(
            amountCents: 8_432, type: .expense, accountID: chequing.id,
            date: .now.addingTimeInterval(-86_400), merchant: "Whole Foods, Market",
            tags: ["weekly", "food, drink"]
        ))
        try await harness.transactions.save(Domain.Transaction(
            amountCents: 320_000, type: .income, accountID: chequing.id,
            date: .now.addingTimeInterval(-172_800), merchant: "Salary"
        ))
        return chequing
    }

    @Test("An archive round-trips through a real zip file")
    func zipRoundTrips() throws {
        let harness = try makeHarness()
        let archive = BackupArchive.make(
            tables: [.accounts: [["id": UUID().uuidString, "name": "Test, Account"]]],
            exportedAt: .now
        )

        let data = try harness.service.encode(archive)
        let restored = try harness.service.decode(data)

        #expect(restored.manifest.schemaVersion == archive.manifest.schemaVersion)
        #expect(restored.tables[.accounts]?.first?["name"] == "Test, Account")
    }

    @Test("The encoded archive is a real zip, readable entry by entry")
    func encodedArchiveIsAZip() async throws {
        let harness = try makeHarness()
        try await seed(harness)
        let archive = try await harness.service.makeArchive()

        let data = try harness.service.encode(archive)
        let files = ZipArchive.files(in: data)

        #expect(files[BackupArchive.manifestFileName] != nil)
        #expect(files["accounts.csv"] != nil)
        #expect(files["transactions.csv"] != nil)
        #expect(data.starts(with: [0x50, 0x4B, 0x03, 0x04]), "the PK local-header signature")
    }

    @Test("Exporting and re-importing into the same store produces zero duplicates")
    func reimportProducesNoDuplicates() async throws {
        let harness = try makeHarness()
        try await seed(harness)
        let before = try await harness.accounts.accounts(includeClosed: true)
        let beforeTransactions = try await harness.transactions.transactions(
            accountID: nil, in: nil
        )
        let data = try harness.service.encode(try await harness.service.makeArchive())

        let diff = try await harness.service.apply(harness.service.decode(data))

        let after = try await harness.accounts.accounts(includeClosed: true)
        let afterTransactions = try await harness.transactions.transactions(
            accountID: nil, in: nil
        )
        #expect(after.count == before.count)
        #expect(afterTransactions.count == beforeTransactions.count)
        #expect(diff.isNoOp, "nothing changed, so nothing was written")
    }

    @Test("Importing twice in a row is still a no-op the second time")
    func doubleImportIsStable() async throws {
        let harness = try makeHarness()
        try await seed(harness)
        let data = try harness.service.encode(try await harness.service.makeArchive())

        _ = try await harness.service.apply(harness.service.decode(data))
        let second = try await harness.service.apply(harness.service.decode(data))

        #expect(second.isNoOp)
        let accounts = try await harness.accounts.accounts(includeClosed: true)
        #expect(accounts.count == 2)
    }

    @Test("Importing into an empty store restores everything")
    func restoreIntoEmptyStore() async throws {
        let source = try makeHarness()
        try await seed(source)
        let data = try source.service.encode(try await source.service.makeArchive())

        let destination = try makeHarness()
        let diff = try await destination.service.apply(destination.service.decode(data))

        let accounts = try await destination.accounts.accounts(includeClosed: true)
        let transactions = try await destination.transactions.transactions(
            accountID: nil, in: nil
        )
        #expect(accounts.count == 2)
        #expect(transactions.count == 2)
        #expect(diff.changes[.accounts]?.inserted == 2)
        #expect(accounts.contains { $0.name == "TD Chequing" })
    }

    @Test("Restored balances are rebuilt rather than carried in the archive")
    func balancesAreRebuilt() async throws {
        let source = try makeHarness()
        let chequing = try await seed(source)
        let data = try source.service.encode(try await source.service.makeArchive())

        let destination = try makeHarness()
        try await destination.service.apply(destination.service.decode(data))

        let restored = try await destination.accounts.account(id: chequing.id)
        #expect(restored?.cachedBalanceCents == 100_000 - 8_432 + 320_000)
    }

    @Test("A field containing a comma survives the whole pipeline")
    func commasSurviveTheArchive() async throws {
        let source = try makeHarness()
        try await seed(source)
        let data = try source.service.encode(try await source.service.makeArchive())

        let destination = try makeHarness()
        try await destination.service.apply(destination.service.decode(data))

        let transactions = try await destination.transactions.transactions(
            accountID: nil, in: nil
        )
        let groceries = transactions.first { $0.merchant.contains("Whole Foods") }
        #expect(groceries?.merchant == "Whole Foods, Market")
        #expect(groceries?.tags == ["weekly", "food, drink"])
    }

    @Test("An archive from a newer build is refused before anything is written")
    func newerArchiveIsRefused() async throws {
        let harness = try makeHarness()
        let archive = BackupArchive(
            manifest: BackupManifest(
                schemaVersion: BackupArchive.currentSchemaVersion + 1,
                exportedAt: .now,
                rowCounts: [:]
            ),
            tables: [.accounts: [Domain.Account(name: "Future").backupRow()]]
        )

        await #expect(throws: BackupImportError.self) {
            try await harness.service.apply(archive)
        }
        let accounts = try await harness.accounts.accounts(includeClosed: true)
        #expect(accounts.isEmpty, "the refusal happens before any write")
    }

    @Test("An archive with no manifest is refused")
    func missingManifestIsRefused() throws {
        let harness = try makeHarness()
        let data = ZipArchive.archive(files: ["accounts.csv": Data("id\n".utf8)])

        #expect(throws: BackupImportError.missingManifest) {
            try harness.service.decode(data)
        }
    }
}
