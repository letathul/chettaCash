import Foundation

/// Which column of a bank's CSV holds which field (§9.7).
///
/// Banks agree on nothing. One export names the date column `Transaction Date`, another
/// `Trans. Date`, another simply `Date`; one prints a single signed `Amount`, another a
/// `Debit`/`Credit` pair. So the shape is discovered per file rather than assumed, and
/// this is what a discovery produces.
///
/// Column *names* rather than indices, because ``CSVCodec/decode(_:delimiter:)`` already
/// keys each row by its header — carrying indices as well would be a second way to say the
/// same thing, and the two could disagree.
public struct CSVStatementColumns: Sendable, Equatable {

    /// How the file expresses an amount.
    public enum AmountLayout: Sendable, Equatable {
        /// One column carrying a signed figure, whose sign convention must be inferred.
        /// See ``CSVSignConvention``.
        case single(String)
        /// A pair of columns, at most one of which is filled on any row. Unambiguous:
        /// a figure in the debit column is money leaving, whatever sign it carries.
        case debitCredit(debit: String, credit: String)
    }

    /// The column naming the day the purchase was made, when the file has one.
    public var transactionDate: String?
    /// The column naming the day the bank posted it, when the file has one.
    public var postingDate: String?
    /// The column holding the merchant descriptor.
    public var descriptor: String
    /// How the file expresses an amount.
    public var amount: AmountLayout
    /// A column printing `Dr`/`Cr` (or `Debit`/`Credit`) beside an unsigned amount.
    ///
    /// **Some exports carry the direction as a word, not a sign.** Every figure in the amount
    /// column is then positive, so ``CSVSignConvention`` has nothing to infer from and falls
    /// back to the commoner convention — which is right for half of those files and inverts
    /// the other half wholesale. When the file names the direction outright, that wins.
    public var directionIndicator: String?
    /// Which sign means a charge, when something other than inference decided it.
    ///
    /// Set by a reader that could tell from the header's own wording, or by the user. `nil`
    /// leaves ``CSVSignConvention/infer(from:)`` to work it out from the figures.
    public var signConvention: CSVSignConvention?

    /// The column the row's date is read from.
    ///
    /// **The transaction date wins whenever there is one.** It is the day the user will
    /// remember and the day they would have typed by hand, so it is what a duplicate must
    /// be matched against; the posting date is the bank's bookkeeping artefact and lags it
    /// by up to several days. When a file prints only a posting date, that is the only
    /// date there is and it stands in.
    public var dateColumn: String? { transactionDate ?? postingDate }

    /// Whether enough was found to read the file at all.
    ///
    /// A descriptor is not required — a file with dates and amounts but no readable
    /// description still yields rows the user can identify by figure and day.
    public var isUsable: Bool { dateColumn != nil }

    /// Creates a column map.
    /// - Parameters:
    ///   - transactionDate: The column naming the day the purchase was made.
    ///   - postingDate: The column naming the day the bank posted it.
    ///   - descriptor: The column holding the merchant descriptor.
    ///   - amount: How the file expresses an amount.
    ///   - directionIndicator: A column printing `Dr`/`Cr` beside an unsigned amount.
    ///   - signConvention: Which sign means a charge, when something already decided it.
    public init(
        transactionDate: String? = nil,
        postingDate: String? = nil,
        descriptor: String = "",
        amount: AmountLayout = .single(""),
        directionIndicator: String? = nil,
        signConvention: CSVSignConvention? = nil
    ) {
        self.transactionDate = transactionDate
        self.postingDate = postingDate
        self.descriptor = descriptor
        self.amount = amount
        self.directionIndicator = directionIndicator
        self.signConvention = signConvention
    }
}
