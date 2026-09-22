import Foundation

/// Decides whether a statement line is a charge, a refund or a payment (§4.3).
///
/// **Why a payment must be recognised.** A card statement's `PAYMENT - THANK YOU` credit is
/// the far side of a transfer the user records from the account they paid *from*. There is
/// no honest way to import it on its own: as income it inflates income totals, which §4.3
/// forbids for the transfer legs it mirrors; as a transfer leg it creates the half-transfer
/// ``TransactionRepository`` forbids outright. So it is identified here and skipped.
///
/// A credit that is *not* a payment is a refund, which imports cleanly as income.
public enum StatementRowClassifier {

    /// Words that mark a credit as a payment against the card rather than a refund.
    ///
    /// Matched against the normalised slug, so punctuation and case never matter.
    static let paymentTerms = [
        "payment", "pymt", "pmt", "autopay", "auto-pay", "thank-you",
        "direct-debit", "preauthorized", "preauth", "paiement", "bill-payment"
    ]

    /// Classifies one statement line.
    ///
    /// The sign decides first: a debit is always a charge, whatever it is called, because
    /// a shop named "Payless" must not be read as a card payment. Only a *credit* is then
    /// examined for payment vocabulary.
    ///
    /// - Parameters:
    ///   - descriptor: The descriptor as the statement printed it.
    ///   - isCredit: Whether the line moves money toward the card's balance.
    /// - Returns: What kind of line it is.
    public static func kind(descriptor: String, isCredit: Bool) -> StatementRowKind {
        guard isCredit else { return .charge }
        return mentionsPayment(descriptor) ? .payment : .refund
    }

    /// Whether a descriptor names a card payment.
    ///
    /// Compared on the hyphenated slug with hyphens as boundaries, so `payment` matches
    /// `PAYMENT - THANK YOU` but not `Payless Shoes`.
    ///
    /// - Parameter descriptor: The descriptor to test.
    /// - Returns: `true` when it reads as a payment.
    public static func mentionsPayment(_ descriptor: String) -> Bool {
        let slug = ReceiptNaming.slug(descriptor)
        guard slug != "receipt" else { return false }
        let tokens = Set(slug.split(separator: "-").map(String.init))
        for term in paymentTerms {
            let parts = term.split(separator: "-").map(String.init)
            if parts.count == 1 {
                if tokens.contains(term) { return true }
            } else if slug.contains(term) {
                return true
            }
        }
        return false
    }
}
