import Foundation

/// The entities a backup archive carries, one CSV each (§9.4).
public enum BackupEntity: String, CaseIterable, Sendable {
    /// Account groups.
    case accountGroups
    /// Accounts.
    case accounts
    /// Ledger transactions.
    case transactions
    /// Recurring rules.
    case recurringRules
    /// Card statements.
    case cardStatements
    /// Products.
    case products
    /// Categories.
    case categories
    /// Saved price comparisons.
    case comparisons
    /// Merchant-to-category pins.
    case merchantRules

    /// The file name this entity's table is written to.
    public var fileName: String { "\(rawValue).csv" }
}

/// The archive's `manifest.json` (§9.4).
public struct BackupManifest: Codable, Equatable, Sendable {
    /// The schema version this archive was written against.
    public let schemaVersion: Int
    /// When the archive was written.
    public let exportedAt: Date
    /// How many rows each entity carried, for a quick sanity check.
    public let rowCounts: [String: Int]

    /// Creates a manifest.
    /// - Parameters:
    ///   - schemaVersion: The schema version.
    ///   - exportedAt: When the archive was written.
    ///   - rowCounts: How many rows each entity carried.
    public init(schemaVersion: Int, exportedAt: Date, rowCounts: [String: Int]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.rowCounts = rowCounts
    }
}

/// A whole backup, in memory (§9.4).
///
/// Receipts are deliberately **not** included: they already live in the Receipts
/// folder, and duplicating a couple of hundred megabytes into every weekly archive
/// would be wasteful (§9.4).
public struct BackupArchive: Equatable, Sendable {
    /// The archive's manifest.
    public var manifest: BackupManifest
    /// Each entity's rows, keyed by column name.
    public var tables: [BackupEntity: [[String: String]]]

    /// The schema version this build of the app writes and can read.
    public static let currentSchemaVersion = 3

    /// The name of the manifest inside the archive.
    public static let manifestFileName = "manifest.json"

    /// Creates an archive.
    /// - Parameters:
    ///   - manifest: The archive's manifest.
    ///   - tables: Each entity's rows.
    public init(manifest: BackupManifest, tables: [BackupEntity: [[String: String]]]) {
        self.manifest = manifest
        self.tables = tables
    }

    /// Builds an archive from tables, deriving the manifest.
    /// - Parameters:
    ///   - tables: Each entity's rows.
    ///   - exportedAt: When the archive is being written.
    /// - Returns: The archive.
    public static func make(
        tables: [BackupEntity: [[String: String]]],
        exportedAt: Date = .now
    ) -> BackupArchive {
        let counts = Dictionary(
            uniqueKeysWithValues: tables.map { ($0.key.rawValue, $0.value.count) }
        )
        return BackupArchive(
            manifest: BackupManifest(
                schemaVersion: currentSchemaVersion,
                exportedAt: exportedAt,
                rowCounts: counts
            ),
            tables: tables
        )
    }

    /// The file name an archive exported on a date should carry (§9.3).
    /// - Parameters:
    ///   - date: The export date.
    ///   - calendar: The calendar to format in.
    /// - Returns: A name such as `chetta-cash-backup-2026-09-12.zip`.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "chetta-cash-backup-%04d-%02d-%02d.zip",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }
}

/// Why an archive could not be imported.
public enum BackupImportError: Error, Equatable, Sendable {
    /// The archive was written by a newer build than this one understands.
    ///
    /// Refused rather than guessed at: a newer schema may carry columns this build
    /// would silently drop (§9.4).
    case schemaTooNew(found: Int, supported: Int)
    /// The archive is missing its manifest.
    case missingManifest
    /// The archive's manifest could not be read.
    case malformedManifest
}

/// What importing an archive would change, shown before committing (§9.4).
public struct BackupDiff: Equatable, Sendable {
    /// Per-entity counts.
    public struct EntityChange: Equatable, Sendable {
        /// Rows that would be inserted.
        public var inserted: Int
        /// Rows that already exist and differ.
        public var updated: Int
        /// Rows that already exist and match.
        public var unchanged: Int

        /// How many rows the archive holds for this entity.
        public var total: Int { inserted + updated + unchanged }

        /// Creates a change summary.
        /// - Parameters:
        ///   - inserted: Rows that would be inserted.
        ///   - updated: Rows that would be updated.
        ///   - unchanged: Rows that already match.
        public init(inserted: Int = 0, updated: Int = 0, unchanged: Int = 0) {
            self.inserted = inserted
            self.updated = updated
            self.unchanged = unchanged
        }
    }

    /// The change summary per entity.
    public var changes: [BackupEntity: EntityChange]

    /// Whether importing would change nothing at all.
    public var isNoOp: Bool {
        changes.values.allSatisfy { $0.inserted == 0 && $0.updated == 0 }
    }

    /// Creates a diff.
    /// - Parameter changes: The change summary per entity.
    public init(changes: [BackupEntity: EntityChange] = [:]) {
        self.changes = changes
    }
}
