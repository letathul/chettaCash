import Foundation

/// How far along a statement import is (§9.7).
///
/// An import is not one wait but several, and the on-device reading is by far the longest.
/// A single spinner for all of it gives no sense of whether anything is happening, which on
/// a multi-second wait reads as a hang — the same reasoning ``ReceiptScanPhase`` records,
/// and more acute here because a statement is several pages rather than one photo.
public enum StatementImportPhase: Sendable, Equatable {
    /// No import is running.
    case idle
    /// The file is being opened and its text read.
    case reading
    /// A reader is working out what the rows say. Carries progress through the pages.
    case understanding(page: Int, pageCount: Int)
    /// Rows are being matched against the ledger.
    case matching
    /// Likely duplicates are being judged.
    case adjudicating
    /// The new transactions are being written.
    case writing

    /// The phases a running import passes through, in order.
    public static var working: [StatementImportPhase] {
        [.reading, .understanding(page: 1, pageCount: 1), .matching, .adjudicating, .writing]
    }

    /// Whether an import is in flight.
    public var isRunning: Bool { self != .idle }

    /// What to tell the user is happening.
    public var message: String {
        switch self {
        case .idle: return ""
        case .reading: return "Reading the statement…"
        case .understanding(let page, let total):
            return total > 1
                ? "Working out what it says… (page \(page) of \(total))"
                : "Working out what it says…"
        case .matching: return "Checking against your ledger…"
        case .adjudicating: return "Looking for duplicates…"
        case .writing: return "Saving…"
        }
    }

    /// Which step this is, counting from one, or `nil` when idle.
    public var step: Int? {
        switch self {
        case .idle: return nil
        case .reading: return 1
        case .understanding: return 2
        case .matching: return 3
        case .adjudicating: return 4
        case .writing: return 5
        }
    }

    /// How far through the import this phase is, from `0` to `1`.
    ///
    /// Reported as the *completed* fraction at the start of each step, so the bar moves
    /// when a step begins rather than sitting still through the longest one. The reading
    /// step subdivides by page, because that is where the seconds actually go.
    public var progress: Double {
        guard let step else { return 0 }
        let total = Double(Self.working.count)
        var completed = Double(step - 1)
        if case .understanding(let page, let pages) = self, pages > 0 {
            completed += min(1, Double(page - 1) / Double(pages))
        }
        return completed / total
    }
}
