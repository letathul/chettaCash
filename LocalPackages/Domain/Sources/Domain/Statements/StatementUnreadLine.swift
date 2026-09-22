import Foundation

/// What stopped a line from becoming a row.
///
/// Only ever raised for a line that *looked* like a transaction — one that carried a date or
/// an amount but not both. A line with neither is page furniture (a heading, an interest-rate
/// table, a marketing paragraph) and is passed over in silence, because reporting those would
/// bury the handful of lines that genuinely need a person.
public enum UnreadProblem: String, Sendable, Equatable, CaseIterable {
    /// An amount was found but no date could be read beside it.
    case noDate
    /// A date was found but no amount could be read beside it.
    case noAmount
    /// Both were read, but the amount came to nothing.
    case zeroAmount
    /// Both were read, but the line named no merchant at all.
    case noDescriptor

    /// What to tell the user about this line.
    public var explanation: String {
        switch self {
        case .noDate: return "No date could be read on this line."
        case .noAmount: return "No amount could be read on this line."
        case .zeroAmount: return "The amount on this line came to zero."
        case .noDescriptor: return "This line named no merchant."
        }
    }
}

/// A line the reader could not turn into a row, kept so it can be shown rather than lost.
///
/// **The alternative was silence.** Every reader here used to `continue` past a line it could
/// not parse, so a statement whose layout defeated the parser reported a smaller row count and
/// nothing else — the rows did not fail to import, they failed to exist. Surfacing the line
/// verbatim lets the review screen offer it back to the user, who can read their own statement.
public struct UnreadLine: Identifiable, Hashable, Sendable {
    /// Stable identifier for this line within the import.
    public let id: UUID
    /// The line exactly as the statement printed it.
    public var text: String
    /// Which page it came from, counting from one, or `nil` for a delimited export.
    public var page: Int?
    /// Which line or row of its source it was, counting from one.
    public var lineNumber: Int
    /// What stopped it becoming a row.
    public var problem: UnreadProblem

    /// Creates an unread line.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - text: The line exactly as printed.
    ///   - page: Which page it came from, or `nil` for a delimited export.
    ///   - lineNumber: Which line of its source it was.
    ///   - problem: What stopped it becoming a row.
    public init(
        id: UUID = UUID(),
        text: String,
        page: Int? = nil,
        lineNumber: Int,
        problem: UnreadProblem
    ) {
        self.id = id
        self.text = text
        self.page = page
        self.lineNumber = lineNumber
        self.problem = problem
    }
}
