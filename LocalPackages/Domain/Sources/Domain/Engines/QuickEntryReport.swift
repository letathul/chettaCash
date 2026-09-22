import Foundation

/// What one quick entry did, beyond writing the obvious (§15.7).
///
/// A background intent is the one place in the app where a side effect has no screen to
/// appear on. Anything the run decided that the user did not say — an account created, an
/// entry parked, a merchant pinned, a date that has not arrived — has to be spoken or it
/// never happened as far as they know.
public struct QuickEntryReport: Sendable, Equatable {
    /// Whether an entry identical to this one was already stored, so nothing new was written.
    public var wasAlreadyLogged: Bool
    /// The name of an account this entry created, if it created one.
    public var createdAccountName: String?
    /// Why the entry was parked with no account, if it was.
    public var parkedReason: QuickExpenseAccountDoubt?
    /// Whether the entry's date has arrived, and so whether it moved a balance (§4.2).
    public var isPosted: Bool
    /// The label of a merchant pin this entry created, if it created one.
    public var pinnedCategoryLabel: String?

    /// Creates a report.
    /// - Parameters:
    ///   - wasAlreadyLogged: Whether this entry was recognised as a repeat.
    ///   - createdAccountName: The name of an account created, if any.
    ///   - parkedReason: Why the entry was parked, if it was.
    ///   - isPosted: Whether the entry's date has arrived.
    ///   - pinnedCategoryLabel: The label of a pin created, if any.
    public init(
        wasAlreadyLogged: Bool = false,
        createdAccountName: String? = nil,
        parkedReason: QuickExpenseAccountDoubt? = nil,
        isPosted: Bool = true,
        pinnedCategoryLabel: String? = nil
    ) {
        self.wasAlreadyLogged = wasAlreadyLogged
        self.createdAccountName = createdAccountName
        self.parkedReason = parkedReason
        self.isPosted = isPosted
        self.pinnedCategoryLabel = pinnedCategoryLabel
    }
}

/// One thing the spoken result has to say, in the order it should be said.
public enum QuickEntryClause: Sendable, Equatable {
    /// The entry was written. Always said, and always first.
    case logged
    /// The entry repeated one already stored, so nothing new was written.
    case alreadyLogged
    /// An account was created to hold it, with this name.
    case createdAccount(String)
    /// No account could be settled on, for this reason, so the entry is waiting in Today.
    case parked(QuickExpenseAccountDoubt)
    /// The entry's date has not arrived, so no balance moved yet.
    case notYetPosted
    /// This merchant will file itself under this category from now on.
    case pinned(String)
}

/// Deciding what a quick entry has to say for itself (§15.7).
///
/// Pure and synchronous, so the rules about *what gets mentioned* are tested without an
/// intent runtime. The App layer only turns each clause into words.
public enum QuickEntryReporter {

    /// The clauses to speak, in order.
    ///
    /// ``QuickEntryClause/logged`` and ``QuickEntryClause/alreadyLogged`` are exclusive, and
    /// so are ``QuickEntryClause/createdAccount(_:)`` and ``QuickEntryClause/parked(_:)`` —
    /// an entry cannot both have an account made for it and have none. A repeat says nothing
    /// further: the account, the pin and the date were all settled the first time, and
    /// repeating them would describe work this run did not do.
    ///
    /// - Parameter report: What the run did.
    /// - Returns: The clauses, always at least one.
    public static func clauses(for report: QuickEntryReport) -> [QuickEntryClause] {
        guard !report.wasAlreadyLogged else { return [.alreadyLogged] }

        var clauses: [QuickEntryClause] = [.logged]
        if let reason = report.parkedReason {
            clauses.append(.parked(reason))
        } else if let name = report.createdAccountName {
            clauses.append(.createdAccount(name))
        }
        if !report.isPosted { clauses.append(.notYetPosted) }
        if let label = report.pinnedCategoryLabel { clauses.append(.pinned(label)) }
        return clauses
    }
}
