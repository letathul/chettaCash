import Foundation
@testable import Domain

/// Shared builders for the category spend insight suites.
enum InsightFixtures {

    /// The reference moment the suites evaluate against: late in September 2026, so
    /// the partial-month guard is satisfied unless a test deliberately moves it.
    static let reference = SeriesFixtures.date(2026, 9, 22)

    /// A date inside the current month.
    /// - Parameter day: The day of September 2026.
    /// - Returns: That instant.
    static func thisMonth(_ day: Int) -> Date { SeriesFixtures.date(2026, 9, day) }

    /// A date inside the prior month.
    /// - Parameter day: The day of August 2026.
    /// - Returns: That instant.
    static func lastMonth(_ day: Int) -> Date { SeriesFixtures.date(2026, 8, day) }

    /// Builds an expense category.
    /// - Parameters:
    ///   - label: Its display text.
    ///   - isArchived: Whether it is hidden from pickers.
    /// - Returns: The category.
    static func category(_ label: String, isArchived: Bool = false) -> Domain.Category {
        Domain.Category(label: label, context: .expense, isBuiltIn: true, isArchived: isArchived)
    }

    /// Builds a categorised expense.
    /// - Parameters:
    ///   - cents: The positive magnitude.
    ///   - category: The category it falls under.
    ///   - when: The date.
    /// - Returns: The transaction.
    static func spend(_ cents: Int, _ category: Domain.Category, when: Date) -> Transaction {
        Transaction(amountCents: cents, type: .expense, categoryID: category.id, date: when)
    }
}
