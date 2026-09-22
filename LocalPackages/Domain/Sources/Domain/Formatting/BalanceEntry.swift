import Foundation

/// Turns an unsigned typed balance into signed cents (§4.1).
///
/// Balance fields present a `.decimalPad`, which has no minus key: the user types a
/// magnitude and picks a direction beside it. This is the one place that combines the
/// two, so the rule stays testable and no screen invents its own sign convention.
///
/// A magnitude alone cannot describe every real balance — a card can be *in credit*
/// after an overpayment, and a spending account can be *overdrawn* — so the direction
/// is a genuine choice rather than a lookup from ``AccountKind``. What the kind supplies
/// is the sensible default and the wording.
public enum BalanceEntry {

    /// Which side of zero a typed balance falls on.
    public enum Direction: String, CaseIterable, Identifiable, Sendable {
        /// Money the user has: cash in hand, or a card overpaid into credit.
        case positive
        /// Money the user owes: a card balance, or an overdrawn account.
        case negative

        /// The case's identity, for `ForEach`.
        public var id: String { rawValue }
    }

    /// Combines a typed magnitude with the chosen direction.
    ///
    /// The magnitude's own sign is ignored, so a pasted "-50" under the *positive*
    /// direction reads as `+50` rather than silently contradicting the control.
    ///
    /// - Parameters:
    ///   - magnitude: The typed amount in cents, of either sign.
    ///   - direction: Which side of zero the user chose.
    /// - Returns: The signed amount in cents. Zero is always `0`, never negative zero.
    public static func signedCents(magnitude: Int, direction: Direction) -> Int {
        let size = abs(magnitude)
        return direction == .negative ? -size : size
    }

    /// The direction an existing balance is already on, for seeding the control.
    ///
    /// Zero reads as ``Direction/positive``: an account at zero is not in debt, and
    /// opening an edit screen on a nil balance should not preselect "owed".
    ///
    /// - Parameter cents: The stored signed balance.
    /// - Returns: The matching direction.
    public static func direction(ofCents cents: Int) -> Direction {
        cents < 0 ? .negative : .positive
    }

    /// The direction to preselect when adding a new account.
    ///
    /// A card is opened because money is owed on it; a spending account is opened with
    /// money in it. Either can be changed before saving.
    ///
    /// - Parameter kind: The account's kind.
    /// - Returns: The default direction.
    public static func defaultDirection(for kind: AccountKind) -> Direction {
        kind == .card ? .negative : .positive
    }

    /// The label a direction carries for one kind of account.
    ///
    /// A card's negative balance is "Owed"; a spending account's is "Overdrawn". Using
    /// one word for both would be wrong in one of the two cases.
    ///
    /// - Parameters:
    ///   - direction: The direction to describe.
    ///   - kind: The account's kind.
    /// - Returns: The control's label.
    public static func label(for direction: Direction, kind: AccountKind) -> String {
        switch (kind, direction) {
        case (.card, .negative): return "Owed"
        case (.card, .positive): return "In credit"
        case (.account, .negative): return "Overdrawn"
        case (.account, .positive): return "In hand"
        }
    }
}
