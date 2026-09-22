import Foundation

/// A field a scan managed to fill (§9.7).
///
/// Reported back so the form can name what it changed. Seven fields arriving at once is
/// enough that a user skims rather than reads, and a pre-fill they did not notice is one
/// they never checked.
public enum ReceiptField: String, CaseIterable, Sendable {
    /// The total.
    case amount
    /// The shop's name.
    case merchant
    /// The day of purchase.
    case date
    /// The time of day, when the receipt printed one.
    case time
    /// The shop's address or branch.
    case location
    /// The category, resolved to one this user actually has.
    case category
    /// The account, matched from the card on the payment line.
    case account

    /// The name to show on the review row.
    public var displayName: String {
        switch self {
        case .amount: return "Amount"
        case .merchant: return "Merchant"
        case .date: return "Date"
        case .time: return "Time"
        case .location: return "Location"
        case .category: return "Category"
        case .account: return "Account"
        }
    }
}

/// A scan resolved against this user's accounts, categories and history (§9.7).
///
/// ``ReceiptScanResult`` says what the *receipt* says; this says what the *form* should
/// show. The two are separate because the receipt's words are not the user's data: a
/// receipt naming "GROCERY" means nothing until it is matched to a category that exists,
/// and a card's digits mean nothing until they match an account.
public struct ReceiptPrefill: Equatable, Sendable {
    /// What the receipt said.
    public var scan: ReceiptScanResult
    /// The resolved category, or `nil` when none could be matched.
    public var categoryID: UUID?
    /// The matched account, or `nil` when the card was unknown or ambiguous.
    public var accountID: UUID?
    /// Tags this user habitually puts on this merchant.
    ///
    /// **Suggestions, not values.** Nothing here reaches the form until it is tapped.
    public var suggestedTags: [String]
    /// Which fields this prefill actually fills.
    public var filled: Set<ReceiptField>

    /// Whether the scan produced nothing to show.
    public var isEmpty: Bool { filled.isEmpty && suggestedTags.isEmpty }

    /// Creates a prefill.
    /// - Parameters:
    ///   - scan: What the receipt said.
    ///   - categoryID: The resolved category.
    ///   - accountID: The matched account.
    ///   - suggestedTags: Tags to offer.
    ///   - filled: Which fields are filled.
    public init(
        scan: ReceiptScanResult = ReceiptScanResult(),
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        suggestedTags: [String] = [],
        filled: Set<ReceiptField> = []
    ) {
        self.scan = scan
        self.categoryID = categoryID
        self.accountID = accountID
        self.suggestedTags = suggestedTags
        self.filled = filled
    }
}

/// The user's own data a scan is resolved against (§9.7).
///
/// Gathered into one value rather than passed as four arguments: they are read together,
/// they come from the same view model, and a caller that has one always has the rest.
public struct ReceiptResolutionContext: Sendable {
    /// The user's accounts, for card matching.
    public var accounts: [Account]
    /// The user's categories, for resolving a reader's label.
    public var categories: [Category]
    /// Past transactions, for the merchant's usual category and tags.
    public var history: [Transaction]
    /// Which category picker the form is showing.
    public var categoryContext: CategoryContext

    /// Creates a resolution context.
    /// - Parameters:
    ///   - accounts: The user's accounts.
    ///   - categories: The user's categories.
    ///   - history: Past transactions.
    ///   - categoryContext: Which picker the form is showing.
    public init(
        accounts: [Account] = [],
        categories: [Category] = [],
        history: [Transaction] = [],
        categoryContext: CategoryContext = .expense
    ) {
        self.accounts = accounts
        self.categories = categories
        self.history = history
        self.categoryContext = categoryContext
    }

    /// The categories this form's picker actually offers.
    ///
    /// Archived and system categories are excluded, so a scan can never select something
    /// the user could not have selected themselves.
    var selectableCategories: [Category] {
        categories.filter {
            $0.context == categoryContext && !$0.isArchived && !SystemCategoryID.isSystem($0.id)
        }
    }
}

/// Resolves a scan against the user's own data (§9.7).
///
/// Pure and synchronous, so the whole of the interesting behaviour — which category wins,
/// when an account may be auto-selected, what counts as filled — is testable in the fast
/// Domain loop without a camera, a model, or a simulator.
public enum ReceiptPrefillBuilder {

    /// Builds the form's pre-fill from a scan.
    ///
    /// - Parameters:
    ///   - scan: What the receipt said.
    ///   - context: The user's accounts, categories and history.
    /// - Returns: The pre-fill.
    public static func prefill(
        from scan: ReceiptScanResult,
        resolvedAgainst context: ReceiptResolutionContext
    ) -> ReceiptPrefill {
        let selectable = context.selectableCategories
        let accounts = context.accounts
        let history = context.history
        let categoryID = category(for: scan, in: selectable, history: history)
        let accountID = AccountMatcher.match(scan.tender ?? ReceiptTender(), in: accounts)
        let tags = scan.merchant.map { MerchantCategoryIndex.tags(for: $0, in: history) } ?? []

        var filled: Set<ReceiptField> = []
        if scan.amountCents != nil { filled.insert(.amount) }
        if scan.merchant != nil { filled.insert(.merchant) }
        if let date = scan.date {
            filled.insert(.date)
            if carriesTime(date) { filled.insert(.time) }
        }
        if scan.location != nil { filled.insert(.location) }
        if categoryID != nil { filled.insert(.category) }
        if accountID != nil { filled.insert(.account) }

        return ReceiptPrefill(
            scan: scan,
            categoryID: categoryID,
            accountID: accountID,
            suggestedTags: tags,
            filled: filled
        )
    }

    /// Resolves the category, preferring what this user has done before.
    ///
    /// History first, because the right category for a shop is the user's own past
    /// decision, not a reader's opinion — and because it costs nothing and cannot
    /// hallucinate. The reader's label is only consulted for a merchant never seen, and
    /// even then it must name a category that already exists: a scan never creates one.
    ///
    /// - Parameters:
    ///   - scan: What the receipt said.
    ///   - selectable: The categories this form's picker offers.
    ///   - history: Past transactions.
    /// - Returns: The category's identifier, or `nil` for the user to pick.
    static func category(
        for scan: ReceiptScanResult,
        in selectable: [Category],
        history: [Transaction]
    ) -> UUID? {
        if let merchant = scan.merchant,
           let remembered = MerchantCategoryIndex.categoryID(for: merchant, in: history),
           selectable.contains(where: { $0.id == remembered }) {
            return remembered
        }
        return match(scan.categoryLabel, in: selectable)
    }

    /// Matches a reader's words to one of the user's categories.
    ///
    /// Exact first, then containment in either direction, so "Food" reaches
    /// "Food & drink" and "Groceries & household" reaches "Groceries". Containment is
    /// only accepted when exactly one category matches — two candidates mean the reader
    /// was not specific enough to act on.
    ///
    /// - Parameters:
    ///   - label: What the reader called the category.
    ///   - selectable: The categories this form's picker offers.
    /// - Returns: The category's identifier, or `nil`.
    static func match(_ label: String?, in selectable: [Category]) -> UUID? {
        guard let label else { return nil }
        let wanted = normalized(label)
        guard !wanted.isEmpty else { return nil }

        if let exact = selectable.first(where: { normalized($0.label) == wanted }) {
            return exact.id
        }
        let partial = selectable.filter {
            let candidate = normalized($0.label)
            return candidate.contains(wanted) || wanted.contains(candidate)
        }
        return partial.count == 1 ? partial.first?.id : nil
    }

    /// Folds a label for comparison, so case and accents cannot separate two spellings.
    /// - Parameter label: The label to fold.
    /// - Returns: The folded label.
    static func normalized(_ label: String) -> String {
        label
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a date carries a real printed time rather than the midday fallback.
    ///
    /// Midday is what both readers use when a receipt gave no time, so it is the one
    /// value that must not be reported as a time the scan found.
    ///
    /// - Parameters:
    ///   - date: The scanned date.
    ///   - calendar: The calendar that reads the components.
    /// - Returns: `true` when a time was printed.
    static func carriesTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return !(parts.hour == 12 && parts.minute == 0)
    }
}
