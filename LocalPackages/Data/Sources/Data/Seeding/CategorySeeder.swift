import Foundation
import SwiftData
import Domain

/// Inserts the built-in categories on first launch (§4.8).
///
/// The seed lists are deliberately short — the user builds the rest through the
/// inline "+ Custom" chip. Every picker is built from whatever categories actually
/// exist, never from a hardcoded list, which is what stops the two lists diverging.
public enum CategorySeeder {

    /// One category to insert on first launch.
    private struct Seed {
        /// Display text.
        let label: String
        /// Which picker it belongs to.
        let context: CategoryContext
        /// Manual ordering position within its context.
        let sortIndex: Int
        /// Fixed identifier, for the system categories that must never appear in a picker.
        var fixedID: UUID?

        /// The case-insensitive identity used to de-duplicate against existing rows.
        var identity: String { "\(context.rawValue)|\(label.lowercased())" }
    }

    /// The expense categories seeded on first launch.
    static let expenseLabels = ["Groceries", "Food & drink", "Transport", "Shopping", "Bills", "Other"]
    /// The income categories seeded on first launch.
    static let incomeLabels = ["Salary", "Other"]
    /// The product categories seeded on first launch.
    static let productLabels = ["Subscription", "Electronics", "Home", "Other"]

    /// Inserts any missing built-in categories.
    ///
    /// Idempotent: running it twice leaves exactly one of each category, so it is
    /// safe to call on every launch.
    ///
    /// - Parameter context: The context to insert into. Saved before returning.
    /// - Throws: A persistence error if the fetch or save fails.
    public static func seedIfNeeded(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<CategoryRecord>())
        var seenIdentities = Set(existing.map { "\($0.context.rawValue)|\($0.label.lowercased())" })
        let seenIDs = Set(existing.map(\.id))

        for seed in allSeeds() {
            if let fixedID = seed.fixedID {
                guard !seenIDs.contains(fixedID) else { continue }
            } else {
                guard !seenIdentities.contains(seed.identity) else { continue }
            }
            context.insert(
                CategoryRecord(
                    id: seed.fixedID ?? UUID(),
                    label: seed.label,
                    context: seed.context,
                    isBuiltIn: true,
                    sortIndex: seed.sortIndex
                )
            )
            seenIdentities.insert(seed.identity)
        }

        if context.hasChanges { try context.save() }
    }

    /// Builds every category the app seeds, in insertion order.
    ///
    /// The final two are the system categories from §4.8. They carry fixed
    /// identifiers so pickers exclude them by identity rather than by matching
    /// display text, and they are never shown in any picker.
    ///
    /// - Returns: The seeds to insert.
    private static func allSeeds() -> [Seed] {
        var seeds = expenseLabels.enumerated().map {
            Seed(label: $0.element, context: .expense, sortIndex: $0.offset)
        }
        seeds += incomeLabels.enumerated().map {
            Seed(label: $0.element, context: .income, sortIndex: $0.offset)
        }
        seeds += productLabels.enumerated().map {
            Seed(label: $0.element, context: .product, sortIndex: $0.offset)
        }
        seeds += [
            Seed(label: "Transfer", context: .expense, sortIndex: 100,
                 fixedID: SystemCategoryID.transfer),
            Seed(label: "Balance adjustment", context: .expense, sortIndex: 101,
                 fixedID: SystemCategoryID.balanceAdjustment)
        ]
        return seeds
    }
}
