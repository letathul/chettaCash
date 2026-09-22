import Foundation
import Domain

/// Which rows the review list is showing.
public enum ImportReviewFilter: String, Sendable, CaseIterable, Identifiable {
    /// Everything the statement held.
    case all
    /// Only the rows ticked to be written.
    case toAdd
    /// Only the rows that look like something the ledger already holds.
    case duplicates
    /// Only the lines no reader could turn into a row.
    case needsAttention
    /// Only the rows that cannot be imported at all.
    case excluded

    /// The filter's identity.
    public var id: String { rawValue }

    /// The chip's label.
    public var title: String {
        switch self {
        case .all: return "All"
        case .toAdd: return "To add"
        case .duplicates: return "Duplicates"
        case .needsAttention: return "Needs a look"
        case .excluded: return "Left out"
        }
    }

    /// Whether a row belongs under this filter.
    /// - Parameter draft: The row to test.
    /// - Returns: `true` when the row should be shown.
    @MainActor
    func matches(_ draft: StatementReviewDraft) -> Bool {
        switch self {
        case .all: return true
        case .toAdd: return draft.isTicked
        case .duplicates: if case .duplicate = draft.status { return true } else { return false }
        case .needsAttention:
            if case .needsAttention = draft.status { return true } else { return false }
        case .excluded: if case .excluded = draft.status { return true } else { return false }
        }
    }
}

/// Reviewing an import before any of it is written (§9.7).
///
/// **The screen is the only write path.** Planning, reading and duplicate adjudication all
/// still happen up front, but they now end in a list rather than in the store — see
/// ``ImportReviewBuilder``. Split from ``StatementImportViewModel`` to keep each file within
/// the 300-line limit.
extension StatementImportViewModel {

    /// Every row of the statement, in review order.
    public var reviewDrafts: [StatementReviewDraft] { drafts }

    /// The rows the current filter shows.
    public var visibleDrafts: [StatementReviewDraft] {
        drafts.filter { filter.matches($0) }
    }

    /// How the rows divide up.
    public var reviewSummary: ImportReviewSummary {
        ImportReviewBuilder.summary(of: drafts.map(\.edited), sourceLines: sourceLineCount)
    }

    /// How many rows would be written if the user approved now.
    public var tickedCount: Int { drafts.count(where: \.isTicked) }

    /// Whether there is anything at all to show.
    public var hasReview: Bool { !drafts.isEmpty }

    /// The label on the button that writes the import.
    public var approveButtonTitle: String {
        tickedCount == 1 ? "Add 1 transaction" : "Add \(tickedCount) transactions"
    }

    /// Lays a finished plan out for review, writing nothing.
    /// - Parameters:
    ///   - planned: The plan to review.
    ///   - verdicts: What the readers concluded about its duplicates.
    func stageForReview(_ planned: ImportPlan, verdicts: [DuplicateVerdict]) {
        plan = planned
        sourceLineCount = planned.rowsProcessed
        rationales = Dictionary(
            verdicts.map { ($0.id, $0.rationale) }, uniquingKeysWith: { first, _ in first }
        )
        // A reader that called the pair an outright match leaves the row unticked all the
        // same: the screen exists so that a judgement is offered, not applied.
        drafts = ImportReviewBuilder.rows(from: planned).map { row in
            StatementReviewDraft(row: row, currencyCode: settings.currencyCode)
        }
    }

    /// Ticks or unticks every row the filter is showing.
    /// - Parameter ticked: Whether to tick them.
    public func setAllVisible(ticked: Bool) {
        for draft in visibleDrafts { draft.setTicked(ticked) }
    }

    /// Flips a row between money out and money in.
    ///
    /// The one correction a mis-read statement needs most, and the reason it is a row action
    /// rather than buried in the editor: a charge filed as income is what sent the user here.
    ///
    /// - Parameter draft: The row to flip.
    public func flipDirection(for draft: StatementReviewDraft) {
        draft.isIncome.toggle()
    }

    /// Marks a row as something the ledger already holds, so it is not written.
    /// - Parameter draft: The row to mark.
    public func markAsDuplicate(_ draft: StatementReviewDraft) {
        draft.setTicked(false)
        draft.replacesExistingID = nil
    }

    /// The entry the ledger already holds that a duplicate row was paired with.
    /// - Parameter draft: The row in question.
    /// - Returns: The existing transaction, or `nil` when the row is not a duplicate.
    public func existingEntry(for draft: StatementReviewDraft) -> Domain.Transaction? {
        guard case .duplicate(let existingID, _) = draft.status else { return nil }
        return plan?.conflicts.first { $0.existing.id == existingID }?.existing
    }

    /// What a reader concluded about a duplicate, when it said anything.
    /// - Parameter draft: The row in question.
    /// - Returns: The rationale, or `nil`.
    public func rationale(for draft: StatementReviewDraft) -> String? {
        plan?.conflicts.first { $0.incoming.id == draft.id }.flatMap { rationales[$0.id] }
    }
}

/// Asking the on-device model about the lines nothing else could read (§9.7).
extension StatementImportViewModel {

    /// The lines the deterministic readers could not turn into rows.
    public var unreadLines: [UnreadLine] { plan?.unread ?? [] }

    /// Whether offering to read them again would do anything.
    public var canRepairUnreadLines: Bool {
        !unreadLines.isEmpty && !phase.isRunning
    }

    /// The label on the button that offers it.
    public var repairButtonTitle: String {
        let count = unreadLines.count
        return "Try reading \(count) \(count == 1 ? "line" : "lines") with AI"
    }

    /// Reads the unread lines again with the on-device model.
    ///
    /// **The answers arrive unticked.** A row a model produced from a line every other reader
    /// failed on is the least certain thing on the screen, so it is offered rather than
    /// applied — the same rule every duplicate on this screen follows.
    ///
    /// - Returns: How many lines it managed to read.
    @discardableResult
    public func repairUnreadLines() async -> Int {
        let lines = unreadLines
        guard !lines.isEmpty else { return 0 }

        let repaired = await importer.repair(lines)
        guard !repaired.isEmpty else {
            errorMessage = "Those lines could not be read. You can type them in by hand."
            return 0
        }

        let byLine = Dictionary(
            repaired.map { ($0.id, $0.row) }, uniquingKeysWith: { first, _ in first }
        )
        let currency = settings.currencyCode
        drafts = drafts.map { draft in
            guard let row = byLine[draft.id] else { return draft }
            return StatementReviewDraft(
                row: ImportReviewRow(
                    id: draft.id,
                    sourceText: draft.sourceText,
                    date: row.date,
                    merchant: row.merchant,
                    amountCents: row.amountCents,
                    isIncome: row.kind == .refund,
                    status: row.kind == .payment
                        ? .excluded(.cardPayment)
                        : .ready,
                    isTicked: false
                ),
                currencyCode: currency
            )
        }
        plan?.unread = lines.filter { byLine[$0.id] == nil }
        return repaired.count
    }
}
