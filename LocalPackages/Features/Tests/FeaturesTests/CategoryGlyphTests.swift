import Foundation
import Testing
import UIKit
import Domain
@testable import Features

/// The category avatar's SF Symbols (§8.2).
///
/// An SF Symbol that does not exist fails **silently** — `Image(systemName:)` simply
/// draws nothing, so a typo survives code review, compiles, and ships as a blank
/// circle. These tests resolve every name the app can produce against the real
/// catalogue, which is the only thing that catches it.
@Suite("Category glyphs")
struct CategoryGlyphTests {

    /// The labels the app seeds, which are the ones with a designated symbol.
    private static let seededLabels = [
        "Groceries", "Food & drink", "Transport", "Shopping", "Bills", "Other",
        "Entertainment", "Subscription"
    ]

    @Test("Every seeded category resolves to a real symbol", arguments: seededLabels)
    func seededLabelsResolve(label: String) {
        let name = CategoryGlyph.name(categoryLabel: label, type: .expense, isTransfer: false)

        #expect(UIImage(systemName: name) != nil, "\(label) drew nothing for \(name)")
    }

    @Test("A user-created category falls back to a real symbol")
    func userCategoryFallsBack() {
        let name = CategoryGlyph.name(
            categoryLabel: "Llama insurance", type: .expense, isTransfer: false
        )

        #expect(UIImage(systemName: name) != nil)
    }

    @Test("Every transaction type resolves to a real symbol", arguments: TransactionType.allCases)
    func everyTypeResolves(type: TransactionType) {
        let named = CategoryGlyph.name(categoryLabel: nil, type: type, isTransfer: false)
        let transfer = CategoryGlyph.name(categoryLabel: nil, type: type, isTransfer: true)

        #expect(UIImage(systemName: named) != nil)
        #expect(UIImage(systemName: transfer) != nil)
    }

    @Test("A transfer keeps its own glyph whatever category it carries")
    func transfersUseTheTransferGlyph() {
        let name = CategoryGlyph.name(
            categoryLabel: "Groceries", type: .expense, isTransfer: true
        )

        #expect(name == "arrow.left.arrow.right")
    }
}
