import Foundation

/// What the caller supplies when logging an expense without opening the app.
///
/// A struct rather than a long parameter list, so the planner stays a two-argument
/// function and the call site reads as a form rather than a positional puzzle.
public struct QuickExpenseInput: Sendable {
    /// Positive magnitude in cents. Zero is allowed — a free item is still a purchase.
    public var amountCents: Int
    /// Which way the money moved. Expense unless the caller says otherwise.
    ///
    /// The sign lives here and nowhere else (§2): ``amountCents`` is always a magnitude.
    public var type: TransactionType
    /// Merchant or payer name.
    public var merchant: String
    /// The category as free text, if the caller named one.
    public var categoryText: String?
    /// The account the entry is recorded against, or `nil` for a parked entry (§15.5).
    ///
    /// Optional because an entry whose account could not be resolved is still written. It
    /// moves no balance until the user assigns it, which is the honest position when the
    /// alternative is guessing which balance to charge.
    public var accountID: UUID?
    /// When the transaction occurred.
    public var date: Date
    /// User labels, before ``QuickExpensePlanner/originTag`` is added.
    public var tags: [String]
    /// Optional place of purchase.
    public var location: String?
    /// Optional free-text note.
    public var memo: String?
    /// Whether to pin this merchant to the resolved category for next time.
    public var remembersCategory: Bool

    /// Creates an input.
    /// - Parameters:
    ///   - amountCents: Positive magnitude in cents.
    ///   - merchant: Merchant or payer name.
    ///   - accountID: The account this entry belongs to, or `nil` to park it.
    ///   - date: When the transaction occurred.
    ///   - type: Which way the money moved. Defaults to an expense.
    public init(
        amountCents: Int,
        merchant: String,
        accountID: UUID?,
        date: Date,
        type: TransactionType = .expense
    ) {
        self.amountCents = amountCents
        self.type = type
        self.merchant = merchant
        self.accountID = accountID
        self.date = date
        self.categoryText = nil
        self.tags = []
        self.location = nil
        self.memo = nil
        self.remembersCategory = true
    }
}

/// What the app already holds, which the planner reads but never changes.
public struct QuickExpenseContext: Sendable {
    /// The categories an expense may be filed under, archived and system ones excluded.
    public var selectableCategories: [Category]
    /// Every merchant pin the user has set.
    public var pins: [MerchantCategoryRule]

    /// Creates a context.
    /// - Parameters:
    ///   - selectableCategories: The selectable expense categories.
    ///   - pins: Every merchant pin.
    public init(selectableCategories: [Category], pins: [MerchantCategoryRule]) {
        self.selectableCategories = selectableCategories
        self.pins = pins
    }
}

/// Everything one quick expense implies, decided before anything is written.
public struct QuickExpensePlan: Sendable {
    /// The transaction to persist.
    public var transaction: Transaction
    /// A category to create first, when the caller named one that does not exist yet.
    public var newCategory: Category?
    /// A pin to write afterwards, when the merchant had none and one was asked for.
    public var newPin: MerchantCategoryRule?

    /// Creates a plan.
    /// - Parameters:
    ///   - transaction: The transaction to persist.
    ///   - newCategory: A category to create first, if any.
    ///   - newPin: A pin to write afterwards, if any.
    public init(
        transaction: Transaction,
        newCategory: Category? = nil,
        newPin: MerchantCategoryRule? = nil
    ) {
        self.transaction = transaction
        self.newCategory = newCategory
        self.newPin = newPin
    }
}

/// Turns a Shortcut's parameters into the records they imply (§4.2, §4.8).
///
/// Pure and synchronous on purpose: every decision the Shortcut makes is testable
/// without a database, a simulator or an intent runtime.
public enum QuickExpensePlanner {

    /// The tag every transaction logged this way carries, so they can be found later.
    public static let originTag = "shortcut"

    /// Decides what one quick expense should write.
    ///
    /// Category resolution runs pin first, then the supplied text, then nothing:
    ///
    /// 1. A ``MerchantCategoryRule`` for this merchant wins outright. The pin is the
    ///    user's standing instruction, so it overrules whatever the Shortcut passed —
    ///    a Shortcut is often built once and run for months, and the pin is the newer
    ///    statement of intent. A pin whose category has since been archived or deleted
    ///    is ignored rather than resurrected.
    /// 2. Otherwise the supplied text, matched against existing categories first and
    ///    only created when nothing matches.
    /// 3. Otherwise `nil`. An uncategorised transaction is a normal state the whole app
    ///    already renders; inventing an "Uncategorised" category would put a row in
    ///    every picker forever to describe an absence.
    ///
    /// - Parameters:
    ///   - input: What the caller supplied.
    ///   - context: What the app already holds.
    /// - Returns: The transaction, and anything that must be created alongside it.
    /// - Throws: ``QuickEntryProblem`` when the amount or the merchant is unusable, or
    ///   ``CategoryNaming/Problem`` when a new category's label is.
    public static func plan(
        _ input: QuickExpenseInput,
        in context: QuickExpenseContext
    ) throws -> QuickExpensePlan {
        let merchant = try validatedMerchant(input.merchant)
        guard input.amountCents <= QuickEntryLimits.maximumCents else {
            throw QuickEntryProblem.amountTooLarge
        }
        let resolution = try resolveCategory(input, in: context)

        var transaction = Transaction(
            amountCents: max(0, input.amountCents),
            type: input.type,
            categoryID: resolution.categoryID,
            accountID: input.accountID,
            date: input.date,
            merchant: merchant,
            location: emptyToNil(input.location),
            memo: emptyToNil(input.memo),
            tags: tags(from: input.tags)
        )
        transaction.signedOverrideCents = nil
        transaction.transferGroupID = nil

        return QuickExpensePlan(
            transaction: transaction,
            newCategory: resolution.newCategory,
            newPin: pin(for: input, resolution: resolution)
        )
    }

    /// The merchant name to store, insisting there is one and that it is a name.
    ///
    /// Refused rather than stored empty. `perform()` used to paper over a bare merchant in
    /// the spoken result by naming the account instead, which made a bad row sound like a
    /// good one — and an empty merchant also yields an empty ``MerchantCategoryIndex`` key,
    /// so the pin the entry asked for silently does nothing.
    ///
    /// - Parameter merchant: The name as supplied.
    /// - Returns: The trimmed name.
    /// - Throws: ``QuickEntryProblem/missingMerchant`` or
    ///   ``QuickEntryProblem/merchantTooLong``.
    private static func validatedMerchant(_ merchant: String) throws -> String {
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QuickEntryProblem.missingMerchant }
        guard trimmed.count <= QuickEntryLimits.maximumMerchantLength else {
            throw QuickEntryProblem.merchantTooLong
        }
        return trimmed
    }

    /// The outcome of category resolution.
    private struct Resolution {
        /// The category the transaction lands in, if any.
        var categoryID: UUID?
        /// A category that must be created first, if any.
        var newCategory: Category?
        /// Whether a pin already existed for this merchant.
        var wasPinned: Bool
    }

    /// Resolves the category, pin first.
    /// - Parameters:
    ///   - input: What the caller supplied.
    ///   - context: What the app already holds.
    /// - Returns: The resolution.
    /// - Throws: ``CategoryNaming/Problem`` when a new label is unusable.
    private static func resolveCategory(
        _ input: QuickExpenseInput,
        in context: QuickExpenseContext
    ) throws -> Resolution {
        if let pinned = pinnedCategoryID(for: input.merchant, in: context) {
            return Resolution(categoryID: pinned, newCategory: nil, wasPinned: true)
        }
        guard let text = emptyToNil(input.categoryText) else {
            return Resolution(categoryID: nil, newCategory: nil, wasPinned: false)
        }
        // The same matcher the receipt scanner uses: exact label first, then a
        // containment match accepted only when exactly one category could be meant.
        if let existing = ReceiptPrefillBuilder.match(text, in: context.selectableCategories) {
            return Resolution(categoryID: existing, newCategory: nil, wasPinned: false)
        }
        let label = try CategoryNaming.validated(text)
        let category = Category(
            label: label,
            context: .expense,
            sortIndex: context.selectableCategories.count
        )
        return Resolution(categoryID: category.id, newCategory: category, wasPinned: false)
    }

    /// The category a pin names, if the pin is still usable.
    /// - Parameters:
    ///   - merchant: The merchant to look up.
    ///   - context: What the app already holds.
    /// - Returns: The pinned category's identifier, or `nil`.
    private static func pinnedCategoryID(
        for merchant: String,
        in context: QuickExpenseContext
    ) -> UUID? {
        let key = MerchantCategoryIndex.key(for: merchant)
        guard !key.isEmpty else { return nil }
        guard let pin = context.pins.first(where: { $0.merchantKey == key }) else { return nil }
        guard !SystemCategoryID.isSystem(pin.categoryID) else { return nil }
        guard context.selectableCategories.contains(where: { $0.id == pin.categoryID }) else {
            return nil
        }
        return pin.categoryID
    }

    /// The pin to write, when one was asked for and none existed.
    /// - Parameters:
    ///   - input: What the caller supplied.
    ///   - resolution: The category resolution.
    /// - Returns: The pin, or `nil`.
    private static func pin(
        for input: QuickExpenseInput,
        resolution: Resolution
    ) -> MerchantCategoryRule? {
        guard input.remembersCategory, !resolution.wasPinned else { return nil }
        guard let categoryID = resolution.categoryID else { return nil }
        return MerchantCategoryRule.make(
            merchant: input.merchant, categoryID: categoryID, updatedAt: input.date
        )
    }

    /// The tags to store, with ``originTag`` appended.
    ///
    /// Case-insensitive, matching the tag field's own rule, and the user's spelling
    /// wins: someone who types "Shortcut" gets their capitalisation back, not a
    /// second tag that differs only in case.
    ///
    /// - Parameter supplied: The tags the caller supplied.
    /// - Returns: The tags to store.
    private static func tags(from supplied: [String]) -> [String] {
        var result: [String] = []
        for tag in supplied {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !result.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { continue }
            result.append(trimmed)
        }
        let hasOrigin = result.contains {
            $0.caseInsensitiveCompare(originTag) == .orderedSame
        }
        if !hasOrigin { result.append(originTag) }
        return result
    }

    /// Blank text as absence.
    /// - Parameter text: The text, if any.
    /// - Returns: The trimmed text, or `nil` when nothing is left.
    private static func emptyToNil(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
