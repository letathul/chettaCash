import Foundation
import FoundationModels
import Domain

/// Works out which column of a bank's CSV is which, with Apple's on-device model (§9.7).
///
/// **Why a model rather than a longer alias list.** A header is short, unstandardised
/// natural language — `Trans. Date`, `Booking text`, `Paid out`, `Importo` — and a list of
/// aliases only ever covers the banks someone has already seen. The model is shown the
/// header *and the first few rows*, so it can settle what an alias table cannot: which of
/// two date-looking columns holds dates and which holds a reference number.
///
/// Nothing leaves the device, and nothing is committed: the map only decides which column is
/// read, and every row still reaches the ledger through the planner, which the user confirms.
///
/// The deterministic ``HeuristicCSVHeaderMapper`` covers whatever this cannot — in the
/// Simulator, on an older device, or when the model declines — and it is what makes the
/// feature safe rather than merely clever.
struct FoundationModelsCSVHeaderMapper: CSVHeaderMapping {

    /// The shape the model is asked to fill in.
    ///
    /// Every field is a header name copied from the row it was shown, never an index: a
    /// miscounted index is undetectable, whereas a name that is not in the header can be
    /// checked and thrown away. See ``verified(_:against:)``.
    @Generable
    struct MappedColumns {
        /// The column naming the day the purchase was made.
        @Guide(description: """
            The exact column heading for the date the purchase was actually made, \
            copied character for character from the header row. \
            Leave empty if the file has only one date column and it is a posting date.
            """)
        var transactionDateColumn: String?
        /// The column naming the day the bank posted it.
        @Guide(description: """
            The exact column heading for the date the bank posted or settled the \
            transaction, copied character for character. Leave empty if there is none.
            """)
        var postingDateColumn: String?
        /// The column holding the merchant descriptor.
        @Guide(description: """
            The exact column heading holding the merchant name or transaction description, \
            copied character for character. Leave empty if there is none.
            """)
        var descriptorColumn: String?
        /// The column holding a single signed amount.
        @Guide(description: """
            The exact column heading holding one signed amount for every row. \
            Leave empty if this file instead splits money out and money in across two columns.
            """)
        var amountColumn: String?
        /// The column holding money leaving the account.
        @Guide(description: """
            The exact column heading holding only money leaving the account — a debit, \
            withdrawal or charge. Leave empty unless the file splits the two directions.
            """)
        var debitColumn: String?
        /// The column holding money coming in.
        @Guide(description: """
            The exact column heading holding only money coming in — a credit, deposit, \
            refund or payment. Leave empty unless the file splits the two directions.
            """)
        var creditColumn: String?
        /// The column naming each row's direction in words.
        @Guide(description: """
            The exact column heading whose cells say which way the money went in words or \
            letters rather than by a sign — Dr, Cr, DEBIT, CREDIT. \
            Leave empty unless such a column exists.
            """)
        var directionColumn: String?
        /// Which sign marks a purchase in a single-amount file.
        @Guide(description: """
            In a file with one signed amount column, which sign marks a purchase. \
            Answer with exactly one of: negative, positive. \
            Look at the sample rows: a payment to the card is the opposite of a purchase. \
            Leave empty if you cannot tell.
            """)
        var chargeSign: String?
    }

    /// How many data rows the model is shown beneath the header.
    ///
    /// Five: enough to tell a date column from a reference number, few enough that a
    /// statement's worth of rows never reaches the prompt.
    static let sampleRowLimit = 5

    /// The model to ask. Injectable so a test can force the unavailable path.
    let model: SystemLanguageModel

    /// Creates the mapper.
    /// - Parameter model: The model to ask.
    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Whether the model reports itself ready.
    ///
    /// Necessary but not sufficient, exactly as for ``FoundationModelsStatementExtractor``:
    /// a model reporting `.available` still throws when asked to generate in the Simulator,
    /// where the generative assets are absent. This gate only avoids pointless work.
    var isAvailable: Bool { model.availability == .available }

    /// Asks the model which column is which.
    /// - Parameters:
    ///   - headers: The header row, exactly as the file printed it.
    ///   - sampleRows: The first few data rows.
    /// - Returns: The map, or `nil` when the model could not help or answered unusably.
    func map(headers: [String], sampleRows: [[String: String]]) async -> CSVStatementColumns? {
        guard isAvailable, !headers.isEmpty else { return nil }
        do {
            let session = LanguageModelSession(model: model) { Self.instructions }
            let response = try await session.respond(
                to: Self.question(headers: headers, sampleRows: sampleRows),
                generating: MappedColumns.self
            )
            return Self.columns(from: response.content, headers: headers)
        } catch {
            // The model declining, the session being interrupted, and the Simulator's
            // missing assets all mean one thing: let the heuristic mapper answer.
            return nil
        }
    }

    /// Folds a model answer into a column map, discarding anything it invented.
    ///
    /// **Every name is checked against the real header.** A model that returns a plausible
    /// column the file does not have would otherwise send the parser looking for a key that
    /// is never present, and every row would read as unreadable — a silent, total failure.
    /// A map that does not survive the check is refused outright so the deterministic mapper
    /// gets its turn, rather than being half-used.
    ///
    /// - Parameters:
    ///   - answer: What the model returned.
    ///   - headers: The header row, exactly as the file printed it.
    /// - Returns: The map, or `nil` when too little survived verification.
    static func columns(from answer: MappedColumns, headers: [String]) -> CSVStatementColumns? {
        let known = Set(headers)
        var map = CSVStatementColumns()
        map.transactionDate = verified(answer.transactionDateColumn, against: known)
        map.postingDate = verified(answer.postingDateColumn, against: known)
        map.descriptor = verified(answer.descriptorColumn, against: known) ?? ""

        map.directionIndicator = verified(answer.directionColumn, against: known)
        map.signConvention = convention(from: answer.chargeSign)

        let debit = verified(answer.debitColumn, against: known)
        let credit = verified(answer.creditColumn, against: known)
        if let debit, let credit {
            map.amount = .debitCredit(debit: debit, credit: credit)
        } else if let single = verified(answer.amountColumn, against: known) ?? debit ?? credit {
            map.amount = .single(single)
        } else {
            return nil
        }
        return map.isUsable ? map : nil
    }

    /// Reads the model's answer about which sign is a charge.
    ///
    /// Anything but the two words asked for is discarded rather than guessed at, which leaves
    /// ``CSVSignConvention/infer(from:)`` to work it out from the figures as before.
    ///
    /// - Parameter text: The model's answer.
    /// - Returns: The convention, or `nil` when the model did not answer usably.
    static func convention(from text: String?) -> CSVSignConvention? {
        switch text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "negative": return .negativeIsCharge
        case "positive": return .positiveIsCharge
        default: return nil
        }
    }

    /// A column name the header actually contains.
    /// - Parameters:
    ///   - name: What the model returned.
    ///   - known: The headers the file really has.
    /// - Returns: The name, or `nil` when it is empty or was invented.
    static func verified(_ name: String?, against known: Set<String>) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, known.contains(trimmed) else { return nil }
        return trimmed
    }

    /// What the model is told before it is shown anything.
    static let instructions = """
        You are reading the header of a bank or credit-card transaction export. \
        Identify which column holds which field. Copy column headings exactly as they \
        appear, character for character, including capitalisation and punctuation. \
        Never invent a heading that is not in the list you are given, and leave a field \
        empty rather than guessing at it. A file uses either one signed amount column or \
        a separate pair for money out and money in — never both.

        You are also shown the first few rows of data. Use them to tell which sign marks a \
        purchase, and to spot a column that names each row's direction in words.
        """

    /// The prompt: the header, then a few rows so values can settle what names cannot.
    /// - Parameters:
    ///   - headers: The header row.
    ///   - sampleRows: The first few data rows.
    /// - Returns: The prompt.
    static func question(headers: [String], sampleRows: [[String: String]]) -> String {
        let sample = sampleRows.prefix(sampleRowLimit).map { row in
            headers.map { "\($0)=\(row[$0] ?? "")" }.joined(separator: " | ")
        }
        return """
            Column headings: \(headers.joined(separator: " | "))

            First rows:
            \(sample.joined(separator: "\n"))
            """
    }
}
