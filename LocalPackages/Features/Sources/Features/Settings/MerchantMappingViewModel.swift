import Foundation
import Observation
import Domain

/// Drives the merchant-to-category mapping screen (§4.8).
///
/// Two lists, and the difference between them is the point. **Pins** are standing
/// instructions the user wrote, and they beat everything when a Shortcut logs an
/// expense. **Suggestions** are what ``MerchantCategoryIndex`` has quietly inferred
/// from history — offered here so the inference can be promoted to an instruction with
/// one tap, rather than left to be outvoted by the next mis-tap.
@MainActor
@Observable
public final class MerchantMappingViewModel {
    /// Reads and writes the pins.
    private let ruleRepository: any MerchantCategoryRuleRepository
    /// Supplies the categories a pin may point at.
    private let categoryRepository: any CategoryRepository
    /// Supplies the history suggestions are inferred from.
    private let transactionRepository: any TransactionRepository

    /// Every pin, most recently updated first.
    public private(set) var rules: [Domain.MerchantCategoryRule] = []
    /// The categories a pin may point at.
    public private(set) var categories: [Domain.Category] = []
    /// Merchants history has an opinion about but no pin covers yet.
    public private(set) var suggestions: [Suggestion] = []
    /// Whether the first load is still running.
    public private(set) var isLoading = true
    /// A load or save failure to surface above the content (§7.0).
    public internal(set) var errorMessage: String?

    /// Past transactions, kept so a suggestion can be recomputed after a pin is written.
    private var history: [Domain.Transaction] = []

    /// A merchant the user's own history already categorises consistently.
    public struct Suggestion: Identifiable, Hashable, Sendable {
        /// The merchant name as it was last typed.
        public let merchant: String
        /// The category history points at.
        public let categoryID: UUID
        /// Identity, for `ForEach`.
        public var id: String { merchant }
    }

    /// Creates the view model.
    /// - Parameters:
    ///   - ruleRepository: Reads and writes the pins.
    ///   - categoryRepository: Supplies selectable categories.
    ///   - transactionRepository: Supplies the history behind suggestions.
    public init(
        ruleRepository: any MerchantCategoryRuleRepository,
        categoryRepository: any CategoryRepository,
        transactionRepository: any TransactionRepository
    ) {
        self.ruleRepository = ruleRepository
        self.categoryRepository = categoryRepository
        self.transactionRepository = transactionRepository
    }

    /// The category a pin points at.
    /// - Parameter id: The category's identifier.
    /// - Returns: The category, or `nil` when it has since been archived.
    public func category(id: UUID?) -> Domain.Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    /// Loads pins, categories and suggestions.
    public func load() async {
        do {
            async let storedRules = ruleRepository.rules()
            async let storedCategories = categoryRepository.selectableCategories(context: .expense)
            async let storedHistory = transactionRepository.transactions(
                accountID: nil, in: nil
            )
            rules = try await storedRules
            categories = try await storedCategories
            history = try await storedHistory
            rebuildSuggestions()
            errorMessage = nil
        } catch {
            errorMessage = "Could not load your merchant mappings."
        }
        isLoading = false
    }

    /// Pins a merchant to a category.
    ///
    /// The repository upserts on the normalised key, so re-pinning a shop replaces
    /// what is there rather than leaving a second pin that could never win.
    ///
    /// - Parameters:
    ///   - merchant: The merchant name as typed.
    ///   - categoryID: The category to file it under.
    /// - Returns: `true` when the pin was written.
    @discardableResult
    public func pin(merchant: String, categoryID: UUID) async -> Bool {
        guard let rule = Domain.MerchantCategoryRule.make(
            merchant: merchant, categoryID: categoryID
        ) else {
            errorMessage = "Enter a merchant name to map."
            return false
        }
        do {
            try await ruleRepository.save(rule)
            await load()
            return errorMessage == nil
        } catch {
            errorMessage = "Could not save that mapping."
            return false
        }
    }

    /// Removes a pin, leaving every transaction it ever categorised alone.
    /// - Parameter id: The pin's identifier.
    public func remove(id: UUID) async {
        do {
            try await ruleRepository.delete(id: id)
            await load()
        } catch {
            errorMessage = "Could not remove that mapping."
        }
    }

    /// Creates a category and returns it, de-duplicating case-insensitively.
    ///
    /// Mirrors the Ledger's own inline create, so a category made here and one made
    /// from the transaction sheet cannot end up as two rows differing only in case.
    ///
    /// - Parameter label: The label to create.
    /// - Returns: The category's identifier, or `nil` when it could not be saved.
    @discardableResult
    public func addCategory(label: String) async -> UUID? {
        if let existing = categories.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return existing.id
        }
        do {
            let validated = try CategoryNaming.validated(label)
            let category = Domain.Category(
                label: validated, context: .expense, sortIndex: categories.count
            )
            try await categoryRepository.save(category)
            await load()
            return category.id
        } catch let problem as CategoryNaming.Problem {
            errorMessage = Self.message(for: problem)
            return nil
        } catch {
            errorMessage = "Could not save that category."
            return nil
        }
    }

    /// The message shown when a category label is refused.
    /// - Parameter problem: Why it was refused.
    /// - Returns: The message.
    static func message(for problem: CategoryNaming.Problem) -> String {
        switch problem {
        case .empty:
            return "Enter a category name."
        case .tooLong:
            return "Keep a category name to \(CategoryNaming.maxLength) characters or fewer."
        case .containsEmoji:
            return "Category names cannot contain emoji."
        }
    }

    /// Recomputes what history suggests for merchants with no pin.
    private func rebuildSuggestions() {
        let pinned = Set(rules.map(\.merchantKey))
        let live = Set(categories.map(\.id))
        var seen: Set<String> = []
        var result: [Suggestion] = []
        // Newest first, so the merchant name shown is the most recent spelling.
        for transaction in history.sorted(by: { $0.date > $1.date }) {
            let key = MerchantCategoryIndex.key(for: transaction.merchant)
            guard !key.isEmpty, !pinned.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            guard let categoryID = MerchantCategoryIndex.categoryID(
                for: transaction.merchant, in: history
            ), live.contains(categoryID) else { continue }
            result.append(
                Suggestion(merchant: transaction.merchant, categoryID: categoryID)
            )
        }
        suggestions = result
    }
}
