import Foundation

/// Which sign a single-amount CSV uses for a charge (§9.7).
///
/// **There is no standard.** American Express exports a purchase as `42.10` and a payment
/// as `-500.00`; Chase exports the same purchase as `-42.10`. Reading the convention wrong
/// turns every charge into a refund, doubles the card's balance in the opposite direction,
/// and files the lot as income — so it is inferred per file rather than assumed, and the
/// inference is evidence-led.
///
/// A split ``CSVStatementColumns/AmountLayout/debitCredit(debit:credit:)`` pair never needs
/// this: which column the figure sits in already says which way the money went.
public enum CSVSignConvention: Sendable, Equatable {
    /// A negative figure is a charge, and a positive one a credit. Chase and most banks.
    case negativeIsCharge
    /// A positive figure is a charge, and a negative one a credit. American Express.
    case positiveIsCharge

    /// Whether a signed figure under this convention moves money toward the card's balance.
    ///
    /// The answer ``StatementRowClassifier/kind(descriptor:isCredit:)`` asks for: a credit
    /// is either a refund or a card payment, and that classifier tells the two apart.
    ///
    /// - Parameter amount: The signed figure from the amount column.
    /// - Returns: `true` when the figure is a credit.
    public func isCredit(_ amount: Decimal) -> Bool {
        switch self {
        case .negativeIsCharge: return amount > 0
        case .positiveIsCharge: return amount < 0
        }
    }

    /// Works out which convention a file uses.
    ///
    /// **Payments decide it when there are any.** A line reading `PAYMENT - THANK YOU` is a
    /// credit by definition, so whichever sign those lines carry is the credit sign — that
    /// is a fact about the file rather than an assumption about the bank.
    ///
    /// Failing that, the majority sign is the charge sign: a card statement is
    /// overwhelmingly purchases, and a month with more refunds than charges would be a
    /// remarkable month. Failing even that — an empty file — the commoner convention stands.
    ///
    /// The words an export prints to mark a row's direction, lowercased.
    ///
    /// Read as whole tokens, so the `dr` in "Dr Pepper" is not a debit marker.
    static let debitWords: Set<String> = ["dr", "debit", "d", "withdrawal", "w", "out"]
    /// The words marking money coming in.
    static let creditWords: Set<String> = ["cr", "credit", "c", "deposit", "in"]

    /// Reads a direction column's cell.
    ///
    /// - Parameter text: The cell, exactly as the file printed it.
    /// - Returns: `true` for a credit, `false` for a debit, `nil` when the cell says neither.
    public static func isCredit(indicator text: String) -> Bool? {
        let token = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter }
        guard !token.isEmpty else { return nil }
        if creditWords.contains(token) { return true }
        if debitWords.contains(token) { return false }
        return nil
    }

    /// - Parameter entries: Each row's descriptor and signed figure, in file order.
    /// - Returns: The convention to read the file under.
    public static func infer(from entries: [(descriptor: String, amount: Decimal)]) -> Self {
        let figures = entries.filter { $0.amount != 0 }
        guard !figures.isEmpty else { return .negativeIsCharge }

        let payments = figures.filter { StatementRowClassifier.mentionsPayment($0.descriptor) }
        if let payment = payments.first {
            // Payments are credits, so the sign they carry is the credit sign — and the
            // charge sign is the other one.
            return payment.amount > 0 ? .negativeIsCharge : .positiveIsCharge
        }

        let negatives = figures.count { $0.amount < 0 }
        return negatives * 2 >= figures.count ? .negativeIsCharge : .positiveIsCharge
    }
}
