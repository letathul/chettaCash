import Foundation
import Observation
import Domain

/// One reviewable row's editable state (§9.7).
///
/// A class rather than a struct in an array, for the reason ``ConflictDraft`` gave before it:
/// each row owns stable bindings, so editing one row cannot re-seed the text fields of
/// another, and a list of eighty rows re-renders only the row that changed.
///
/// **Display strings are stored, not computed.** A row's date and amount are rendered once
/// when they change rather than on every pass through `body`: the review list is the longest
/// list in the app, and formatting inside a body property is what the keyboard rules forbid.
@MainActor
@Observable
public final class StatementReviewDraft: Identifiable {

    /// The row as the builder laid it out, which never changes.
    public let source: ImportReviewRow
    /// The currency the amount is rendered in.
    private let currencyCode: String

    /// Whether the row is ticked for import.
    public var isTicked: Bool
    /// The date the row will be filed under, when it has one.
    public var date: Date? {
        didSet { refreshDisplay() }
    }
    /// The name the transaction will carry, editable in place.
    public var merchant: String
    /// The amount, editable in place as unsigned text.
    public var amountText: String {
        didSet { refreshDisplay() }
    }
    /// Whether the row is money coming in rather than money spent.
    public var isIncome: Bool {
        didSet { refreshDisplay() }
    }
    /// The category the row will be filed under.
    public var categoryID: UUID?
    /// The ledger entry this row should replace, when the user chose to replace one.
    public var replacesExistingID: UUID?
    /// Whether the row's editor is open.
    public var isExpanded = false

    /// The amount as the row shows it.
    public private(set) var amountDisplay = ""
    /// The date as the row shows it.
    public private(set) var dateDisplay = ""

    /// The row's identity, which is the transaction's identity when it is written.
    public nonisolated var id: UUID { source.id }
    /// The statement's own wording, kept verbatim.
    public nonisolated var sourceText: String { source.sourceText }
    /// Why the row is in the state it is.
    public nonisolated var status: ImportReviewStatus { source.status }

    /// The amount the user has typed, in cents, or `nil` when it is not a number.
    public var amountCents: Int? { MoneyInput.magnitudeCents(from: amountText) }

    /// Whether the row holds enough to be written.
    public var canBeTicked: Bool {
        date != nil && (amountCents ?? 0) > 0
            && !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The row with the user's edits applied.
    public var edited: ImportReviewRow {
        var row = source
        row.date = date
        row.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        row.amountCents = amountCents ?? source.amountCents
        row.isIncome = isIncome
        row.categoryID = categoryID
        row.isTicked = isTicked && canBeTicked
        return row
    }

    /// Creates a draft.
    /// - Parameters:
    ///   - row: The row as the builder laid it out.
    ///   - currencyCode: The currency the amount is rendered in.
    public init(row: ImportReviewRow, currencyCode: String) {
        self.source = row
        self.currencyCode = currencyCode
        self.isTicked = row.isTicked
        self.date = row.date
        self.merchant = row.merchant
        self.amountText = row.amountCents > 0
            ? MoneyInput.magnitudeText(fromCents: row.amountCents)
            : ""
        self.isIncome = row.isIncome
        self.categoryID = row.categoryID
        refreshDisplay()
    }

    /// Ticks the row, if it can be.
    ///
    /// Refused rather than quietly ignored elsewhere: a row with no date or no amount cannot
    /// become a transaction, and letting it look ticked would promise an import that never
    /// happens.
    ///
    /// - Parameter ticked: Whether to tick it.
    /// - Returns: `true` when the row ended up as asked.
    @discardableResult
    public func setTicked(_ ticked: Bool) -> Bool {
        guard ticked else {
            isTicked = false
            return true
        }
        guard canBeTicked else { return false }
        isTicked = true
        return true
    }

    /// Re-renders the stored display strings.
    private func refreshDisplay() {
        let cents = amountCents ?? 0
        let rendered = CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
        amountDisplay = cents > 0 ? (isIncome ? "+\(rendered)" : rendered) : "—"
        dateDisplay = date.map { Self.dateFormat.string(from: $0) } ?? "No date"
    }

    /// The format the collapsed row prints a date in.
    ///
    /// Held once rather than built per row: a `DateFormatter` is expensive to create, and a
    /// statement produces dozens of rows at a time.
    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
