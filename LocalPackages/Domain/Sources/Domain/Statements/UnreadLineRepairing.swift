import Foundation

/// One line a reader failed on, read again (§9.7).
public struct RepairedLine: Identifiable, Sendable, Equatable {
    /// The ``UnreadLine`` this answers, so the review can put it back where it came from.
    public let id: UUID
    /// What the line turned out to say.
    public var row: StatementRow

    /// Creates a repaired line.
    /// - Parameters:
    ///   - id: The unread line this answers.
    ///   - row: What the line turned out to say.
    public init(id: UUID, row: StatementRow) {
        self.id = id
        self.row = row
    }
}

/// Reads the handful of lines the deterministic parsers could not (§9.7).
///
/// **Only the failures, and only when asked.** Sending every row of a statement through a
/// language model is slow — a card statement runs to eighty lines — and it lets the model
/// rewrite rows the deterministic reader already had right, which is the more expensive
/// mistake. The parsers handle the shape every statement shares; this handles the remainder,
/// on the user's say-so, and its answers arrive unticked for them to confirm.
///
/// Declared in Domain, like ``StatementExtracting``, so the framework-backed implementation
/// lives in Features and a test can substitute a fake without a simulator.
public protocol UnreadLineRepairing: Sendable {
    /// Reads what it can of the lines a parser could not.
    ///
    /// Never throws: a repairer that cannot help returns nothing and the lines stay as they
    /// were, for the user to type in themselves.
    ///
    /// - Parameters:
    ///   - lines: The lines to read again.
    ///   - context: The clock and calendar dates resolve against.
    /// - Returns: What could be read. May cover fewer lines than it was given, or none.
    func repair(
        _ lines: [UnreadLine],
        context: StatementParseContext
    ) async -> [RepairedLine]
}

/// A repairer that answers nothing, for a build with no model available.
public struct NoRepairer: UnreadLineRepairing {

    /// Creates the repairer.
    public init() {}

    /// Answers nothing.
    /// - Parameters:
    ///   - lines: The lines to read again.
    ///   - context: The clock and calendar.
    /// - Returns: An empty array, always.
    public func repair(
        _ lines: [UnreadLine],
        context: StatementParseContext
    ) async -> [RepairedLine] { [] }
}
