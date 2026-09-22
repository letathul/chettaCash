import Foundation
import Domain

/// Exports and imports backup archives (§9.4).
///
/// The archive is re-importable rather than a flat transaction dump: one CSV per
/// entity, each row carrying its own `id` and its foreign-key `id`s, plus a manifest
/// recording the schema version and export date.
public struct BackupService: Sendable {
    /// Supplies and receives accounts and groups.
    private let accounts: any AccountRepository
    /// Supplies and receives transactions.
    private let transactions: any TransactionRepository
    /// Supplies and receives categories.
    private let categories: any CategoryRepository
    /// Supplies and receives recurring rules.
    private let recurringRules: any RecurringRuleRepository
    /// Supplies and receives card statements.
    private let statements: any CardStatementRepository
    /// Supplies and receives products.
    private let products: any ProductRepository
    /// Supplies and receives saved comparisons.
    private let comparisons: any ComparisonRepository
    /// Supplies and receives merchant-to-category pins.
    private let merchantRules: any MerchantCategoryRuleRepository

    /// Creates the service.
    /// - Parameter repositories: Every repository the archive draws from.
    public init(repositories: BackupRepositories) {
        self.accounts = repositories.accounts
        self.transactions = repositories.transactions
        self.categories = repositories.categories
        self.recurringRules = repositories.recurringRules
        self.statements = repositories.statements
        self.products = repositories.products
        self.comparisons = repositories.comparisons
        self.merchantRules = repositories.merchantRules
    }

    /// Reads every entity into backup tables.
    /// - Returns: Each entity's rows.
    /// - Throws: A persistence error if a fetch fails.
    public func currentTables() async throws -> [BackupEntity: [[String: String]]] {
        [
            .accountGroups: try await accounts.groups().map { $0.backupRow() },
            .accounts: try await accounts.accounts(includeClosed: true).map { $0.backupRow() },
            .transactions: try await transactions.transactions(accountID: nil, in: nil)
                .map { $0.backupRow() },
            .recurringRules: try await recurringRules.rules(activeOnly: false)
                .map { $0.backupRow() },
            .cardStatements: try await statements.statements(accountID: nil)
                .map { $0.backupRow() },
            .products: try await products.products().map { $0.backupRow() },
            .categories: try await categories.allCategories().map { $0.backupRow() },
            .comparisons: try await comparisons.comparisons().map { $0.backupRow() },
            .merchantRules: try await merchantRules.rules().map { $0.backupRow() }
        ]
    }

    /// Builds an archive from the current store.
    /// - Parameter exportedAt: When the archive is being written.
    /// - Returns: The archive.
    /// - Throws: A persistence error if a fetch fails.
    public func makeArchive(exportedAt: Date = .now) async throws -> BackupArchive {
        BackupArchive.make(tables: try await currentTables(), exportedAt: exportedAt)
    }

    /// Encodes an archive as ZIP bytes.
    /// - Parameter archive: The archive to encode.
    /// - Returns: The `.zip` bytes.
    /// - Throws: An encoding error if the manifest cannot be written.
    public func encode(_ archive: BackupArchive) throws -> Data {
        var files: [String: Data] = [:]
        for entity in BackupEntity.allCases {
            let rows = archive.tables[entity] ?? []
            let text = CSVCodec.encode(rows: rows, columns: entity.backupColumns)
            files[entity.fileName] = Data(text.utf8)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        files[BackupArchive.manifestFileName] = try encoder.encode(archive.manifest)
        return ZipArchive.archive(files: files)
    }

    /// Decodes ZIP bytes into an archive.
    /// - Parameter data: The `.zip` bytes.
    /// - Returns: The archive.
    /// - Throws: ``BackupImportError`` when the manifest is missing or unreadable.
    public func decode(_ data: Data) throws -> BackupArchive {
        let files = ZipArchive.files(in: data)
        guard let manifestData = files[BackupArchive.manifestFileName] else {
            throw BackupImportError.missingManifest
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData) else {
            throw BackupImportError.malformedManifest
        }
        var tables: [BackupEntity: [[String: String]]] = [:]
        for entity in BackupEntity.allCases {
            guard let contents = files[entity.fileName],
                  let text = String(data: contents, encoding: .utf8) else { continue }
            tables[entity] = CSVCodec.decode(text)
        }
        return BackupArchive(manifest: manifest, tables: tables)
    }

}

/// The repositories a backup draws from and writes back to.
public struct BackupRepositories: Sendable {
    /// Accounts and groups.
    public let accounts: any AccountRepository
    /// Ledger transactions.
    public let transactions: any TransactionRepository
    /// Categories.
    public let categories: any CategoryRepository
    /// Recurring rules.
    public let recurringRules: any RecurringRuleRepository
    /// Card statements.
    public let statements: any CardStatementRepository
    /// Products.
    public let products: any ProductRepository
    /// Saved comparisons.
    public let comparisons: any ComparisonRepository
    /// Merchant-to-category pins.
    public let merchantRules: any MerchantCategoryRuleRepository

    /// Creates the bundle.
    /// - Parameters:
    ///   - accounts: Accounts and groups.
    ///   - transactions: Ledger transactions.
    ///   - categories: Categories.
    ///   - recurringRules: Recurring rules.
    ///   - statements: Card statements.
    ///   - products: Products.
    ///   - comparisons: Saved comparisons.
    ///   - merchantRules: Merchant-to-category pins.
    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        categories: any CategoryRepository,
        recurringRules: any RecurringRuleRepository,
        statements: any CardStatementRepository,
        products: any ProductRepository,
        comparisons: any ComparisonRepository,
        merchantRules: any MerchantCategoryRuleRepository
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.categories = categories
        self.recurringRules = recurringRules
        self.statements = statements
        self.products = products
        self.comparisons = comparisons
        self.merchantRules = merchantRules
    }
}

/// Applying an archive to the store (§9.4).
extension BackupService {

    /// Summarises what importing an archive would change, without changing anything.
    /// - Parameter archive: The archive being imported.
    /// - Returns: The diff to show before committing.
    /// - Throws: ``BackupImportError/schemaTooNew(found:supported:)`` for a newer
    ///   archive, or a persistence error if a fetch fails.
    public func preview(_ archive: BackupArchive) async throws -> BackupDiff {
        try BackupImporter.validate(archive)
        return BackupImporter.diff(archive, against: try await currentTables())
    }

    /// Applies an archive to the store.
    ///
    /// Matches on `id`: existing records are updated and missing ones inserted, so
    /// importing the same archive twice produces no duplicates. Rows that already
    /// match exactly are skipped entirely.
    ///
    /// - Parameter archive: The archive to apply.
    /// - Returns: The diff describing what changed.
    /// - Throws: ``BackupImportError`` for an unreadable archive, or a persistence
    ///   error if a write fails.
    @discardableResult
    public func apply(_ archive: BackupArchive) async throws -> BackupDiff {
        try BackupImporter.validate(archive)
        let existing = try await currentTables()
        let diff = BackupImporter.diff(archive, against: existing)
        let toApply = BackupImporter.rowsToApply(archive, against: existing)

        try await write(toApply)

        // Balances are a denormalised cache, not data, so they are rebuilt rather
        // than carried in the archive (§4.1).
        try await accounts.recalculateAllBalances()
        return diff
    }

    /// Writes the rows an import decided on.
    ///
    /// Ordered so a row's references already exist when it is written.
    ///
    /// - Parameter rows: The rows to insert or update, keyed by entity.
    /// - Throws: A persistence error if a write fails.
    private func write(_ rows: [BackupEntity: [[String: String]]]) async throws {
        for row in rows[.accountGroups] ?? [] {
            if let value = Domain.AccountGroup.fromBackupRow(row) { try await accounts.save(value) }
        }
        for row in rows[.categories] ?? [] {
            if let value = Domain.Category.fromBackupRow(row) { try await categories.save(value) }
        }
        for row in rows[.accounts] ?? [] {
            if let value = Domain.Account.fromBackupRow(row) { try await accounts.save(value) }
        }
        try await writeLedger(rows)
        // Last: a product points at its purchase, and the repository refuses to write
        // one whose transaction is not already in the store (§7.8).
        for row in rows[.products] ?? [] {
            if let value = Domain.Product.fromBackupRow(row) { try await products.save(value) }
        }
    }

    /// Writes the ledger-side rows of an import.
    /// - Parameter rows: The rows to insert or update, keyed by entity.
    /// - Throws: A persistence error if a write fails.
    private func writeLedger(_ rows: [BackupEntity: [[String: String]]]) async throws {
        for row in rows[.recurringRules] ?? [] {
            if let value = Domain.RecurringRule.fromBackupRow(row) {
                try await recurringRules.save(value)
            }
        }
        for row in rows[.transactions] ?? [] {
            if let value = Domain.Transaction.fromBackupRow(row) {
                try await transactions.save(value)
            }
        }
        for row in rows[.cardStatements] ?? [] {
            if let value = Domain.CardStatement.fromBackupRow(row) {
                try await statements.save(value)
            }
        }
        try await writeSupporting(rows)
    }

    /// Writes the rows that hang off nothing else: comparisons and merchant pins.
    ///
    /// Split from ``writeLedger(_:)`` only to keep each within the complexity cap.
    ///
    /// - Parameter rows: The rows to insert or update, keyed by entity.
    /// - Throws: A persistence error if a write fails.
    private func writeSupporting(_ rows: [BackupEntity: [[String: String]]]) async throws {
        for row in rows[.comparisons] ?? [] {
            if let value = Domain.Comparison.fromBackupRow(row) {
                try await comparisons.save(value)
            }
        }
        for row in rows[.merchantRules] ?? [] {
            if let value = Domain.MerchantCategoryRule.fromBackupRow(row) {
                try await merchantRules.save(value)
            }
        }
    }
}
