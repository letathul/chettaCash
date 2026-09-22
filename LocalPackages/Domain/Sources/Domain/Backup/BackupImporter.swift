import Foundation

/// Decides what importing an archive would change (§9.4).
///
/// **Import matches on `id`**: existing records are updated and missing ones
/// inserted, which is what makes importing the same archive twice produce no
/// duplicates.
public enum BackupImporter {

    /// Checks an archive can be read by this build.
    /// - Parameter archive: The archive to check.
    /// - Throws: ``BackupImportError/schemaTooNew(found:supported:)`` when the archive
    ///   was written by a newer build.
    public static func validate(_ archive: BackupArchive) throws {
        guard archive.manifest.schemaVersion <= BackupArchive.currentSchemaVersion else {
            throw BackupImportError.schemaTooNew(
                found: archive.manifest.schemaVersion,
                supported: BackupArchive.currentSchemaVersion
            )
        }
    }

    /// Summarises what importing would change, without changing anything.
    /// - Parameters:
    ///   - archive: The archive being imported.
    ///   - existing: What the store currently holds, keyed the same way.
    /// - Returns: The diff to show before committing.
    public static func diff(
        _ archive: BackupArchive,
        against existing: [BackupEntity: [[String: String]]]
    ) -> BackupDiff {
        var diff = BackupDiff()
        for entity in BackupEntity.allCases {
            let incoming = archive.tables[entity] ?? []
            guard !incoming.isEmpty || existing[entity]?.isEmpty == false else { continue }
            let current = Dictionary(
                (existing[entity] ?? []).compactMap { row in row["id"].map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            var change = BackupDiff.EntityChange()
            for row in incoming {
                guard let id = row["id"] else { continue }
                guard let match = current[id] else {
                    change.inserted += 1
                    continue
                }
                if match == row { change.unchanged += 1 } else { change.updated += 1 }
            }
            diff.changes[entity] = change
        }
        return diff
    }

    /// The rows that should be written, keyed by entity.
    ///
    /// Rows that already match exactly are omitted: rewriting them would be work for
    /// no change, and it keeps a re-import of an unchanged archive a true no-op.
    ///
    /// - Parameters:
    ///   - archive: The archive being imported.
    ///   - existing: What the store currently holds.
    /// - Returns: The rows to insert or update.
    public static func rowsToApply(
        _ archive: BackupArchive,
        against existing: [BackupEntity: [[String: String]]]
    ) -> [BackupEntity: [[String: String]]] {
        var result: [BackupEntity: [[String: String]]] = [:]
        for entity in BackupEntity.allCases {
            let incoming = archive.tables[entity] ?? []
            guard !incoming.isEmpty else { continue }
            let current = Dictionary(
                (existing[entity] ?? []).compactMap { row in row["id"].map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )
            let changed = incoming.filter { row in
                guard let id = row["id"] else { return false }
                return current[id] != row
            }
            if !changed.isEmpty { result[entity] = changed }
        }
        return result
    }

    /// A one-line summary of a diff, as §9.4 specifies.
    /// - Parameter diff: The diff to describe.
    /// - Returns: Text such as "412 transactions, 6 accounts — 3 new, 409 unchanged".
    public static func summary(of diff: BackupDiff) -> String {
        let totals = BackupEntity.allCases.compactMap { entity -> String? in
            guard let change = diff.changes[entity], change.total > 0 else { return nil }
            return "\(change.total) \(entity.summaryNoun)"
        }
        let inserted = diff.changes.values.reduce(0) { $0 + $1.inserted }
        let updated = diff.changes.values.reduce(0) { $0 + $1.updated }
        let unchanged = diff.changes.values.reduce(0) { $0 + $1.unchanged }

        guard !totals.isEmpty else { return "Nothing to import." }
        var tail = ["\(inserted) new"]
        if updated > 0 { tail.append("\(updated) updated") }
        tail.append("\(unchanged) unchanged")
        return totals.joined(separator: ", ") + " — " + tail.joined(separator: ", ")
    }
}

/// Display nouns for the entities in an import summary.
extension BackupEntity {
    /// The plural noun used in a diff summary.
    var summaryNoun: String {
        switch self {
        case .accountGroups: return "groups"
        case .accounts: return "accounts"
        case .transactions: return "transactions"
        case .recurringRules: return "recurring rules"
        case .cardStatements: return "statements"
        case .products: return "products"
        case .categories: return "categories"
        case .comparisons: return "comparisons"
        case .merchantRules: return "merchant pins"
        }
    }
}
