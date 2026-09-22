import Foundation

/// Turns a bank's CSV into the same ``StatementDocument`` a PDF produces (§9.7).
///
/// **Nothing downstream knows the file was a CSV.** The planner, the fingerprint, the
/// conflict wizard and the summary all take a `StatementDocument`, so a reader that produces
/// one inherits the entire pipeline — including the rules that a card payment is never
/// imported and that a duplicate is never written twice.
///
/// Pure and synchronous, like ``StatementImportPlanner``: every decision here is testable
/// without a database, a simulator or a language model.
public enum CSVStatementParser {

    /// Reads a CSV into a document.
    ///
    /// - Parameters:
    ///   - csv: The file's text.
    ///   - columns: Which column is which, from a ``CSVHeaderMapping``.
    ///   - context: The clock and calendar.
    /// - Returns: What the file said. Empty when no row could be read.
    public static func document(
        csv: String,
        columns: CSVStatementColumns,
        context: StatementParseContext = StatementParseContext()
    ) -> StatementDocument {
        let table = CSVCodec.table(csv, delimiter: CSVCodec.inferDelimiter(csv))
        return document(table: table, columns: columns, context: context)
    }

    /// Reads an already-decoded table into a document.
    ///
    /// Split out so a caller that has decoded the file once — to show a mapper its sample
    /// rows, say — does not parse the same text a second time.
    ///
    /// - Parameters:
    ///   - table: The decoded file.
    ///   - columns: Which column is which.
    ///   - context: The clock and calendar.
    /// - Returns: What the file said.
    public static func document(
        table: CSVTable,
        columns: CSVStatementColumns,
        context: StatementParseContext = StatementParseContext()
    ) -> StatementDocument {
        guard let dateColumn = columns.dateColumn else {
            return StatementDocument(sourceLineCount: table.rows.count)
        }

        // The date order and the sign convention are both properties of the whole file: one
        // line can say neither whether 03/09 is March or September, nor whether a positive
        // figure is a purchase. See ``StatementDateOrder`` and ``CSVSignConvention``.
        var context = context
        context.dateOrder = StatementDateOrderReader.infer(
            from: table.rows.map { $0[dateColumn] ?? "" }
        )
        let readings = table.rows.map { row in
            (descriptor: descriptor(in: row, columns: columns),
             amount: amount(in: row, columns: columns))
        }
        let convention = convention(for: readings, columns: columns)

        var rows: [StatementRow] = []
        var unread: [UnreadLine] = []
        for (index, reading) in readings.enumerated() {
            let row = index < table.rows.count ? table.rows[index] : [:]
            switch outcome(
                cell(in: row, reading: reading, columns: columns, context: context),
                columns: columns,
                convention: convention
            ) {
            case .read(let row):
                rows.append(row)
            case .unread(let problem):
                unread.append(
                    unreadLine(at: index, in: table, columns: columns, problem: problem)
                )
            case .ignored:
                continue
            }
        }
        return StatementDocument(
            rows: rows,
            source: .textHeuristics,
            unread: unread,
            sourceLineCount: table.rows.count
        )
    }

    /// Which sign marks a charge in this file.
    ///
    /// A convention something already settled — read off the header by a mapper, or set by the
    /// user — beats one inferred from the figures, which is a guess by comparison.
    ///
    /// - Parameters:
    ///   - readings: Each row's descriptor and figure.
    ///   - columns: Which column is which.
    /// - Returns: The convention to read the file under.
    static func convention(
        for readings: [(descriptor: String, amount: Decimal?)],
        columns: CSVStatementColumns
    ) -> CSVSignConvention {
        columns.signConvention ?? CSVSignConvention.infer(
            from: readings.compactMap { reading in
                reading.amount.map { (descriptor: reading.descriptor, amount: $0) }
            }
        )
    }

    /// Gathers what one row of the file holds.
    /// - Parameters:
    ///   - row: The decoded row, keyed by column name.
    ///   - reading: The descriptor and figure already read off the row.
    ///   - columns: Which column is which.
    ///   - context: The clock, calendar and date order.
    /// - Returns: The row's cell.
    static func cell(
        in row: [String: String],
        reading: (descriptor: String, amount: Decimal?),
        columns: CSVStatementColumns,
        context: StatementParseContext
    ) -> RowCell {
        RowCell(
            descriptor: reading.descriptor,
            amount: reading.amount,
            date: columns.dateColumn.flatMap {
                StatementTextParser.date(from: row[$0] ?? "", context: context)
            },
            isCreditByIndicator: columns.directionIndicator.flatMap {
                CSVSignConvention.isCredit(indicator: row[$0] ?? "")
            }
        )
    }

    /// What one row of the file came to.
    enum RowOutcome: Equatable {
        /// The row was read.
        case read(StatementRow)
        /// The row looked like a transaction but could not be read.
        case unread(UnreadProblem)
        /// The row was never a transaction — a blank line, or a trailing total.
        case ignored
    }

    /// What one row of the file held, before it is judged.
    struct RowCell: Equatable {
        /// The descriptor as printed.
        var descriptor: String
        /// The figure read, if any.
        var amount: Decimal?
        /// The date read, if any.
        var date: Date?
        /// What a direction column said, when the file has one.
        var isCreditByIndicator: Bool?
    }

    /// Works out what one row comes to.
    ///
    /// A row missing both a date and an amount is ignored rather than reported: those are the
    /// blank lines and summary totals every export carries, and reporting them would bury the
    /// rows that genuinely need a person. A row carrying one of the two is a transaction this
    /// parser could not read, and used to vanish without trace.
    ///
    /// - Parameters:
    ///   - cell: What the row held.
    ///   - columns: Which column is which.
    ///   - convention: Which sign means a charge in a single-column file.
    /// - Returns: What the row came to.
    static func outcome(
        _ cell: RowCell,
        columns: CSVStatementColumns,
        convention: CSVSignConvention
    ) -> RowOutcome {
        guard let amount = cell.amount else {
            return cell.date == nil ? .ignored : .unread(.noAmount)
        }
        guard let date = cell.date else { return .unread(.noDate) }

        // A column that names the direction outright settles it: there is nothing for a sign
        // convention to be better at than the file saying "Dr".
        let credit = cell.isCreditByIndicator
            ?? isCredit(amount, columns: columns, convention: convention)
        guard let row = statementRow(
            date: date, descriptor: cell.descriptor, amount: amount, isCredit: credit
        ) else { return .unread(.zeroAmount) }
        return .read(row)
    }

    /// Describes one unreadable row in the file's own words.
    ///
    /// The whole row is rendered, not just the columns the map picked out: when the map is
    /// what went wrong, the columns it chose are exactly the ones that will not explain it.
    ///
    /// - Parameters:
    ///   - index: Which data row it is, counting from zero.
    ///   - table: The decoded file.
    ///   - columns: Which column is which.
    ///   - problem: What stopped it becoming a row.
    /// - Returns: The unread line.
    static func unreadLine(
        at index: Int,
        in table: CSVTable,
        columns: CSVStatementColumns,
        problem: UnreadProblem
    ) -> UnreadLine {
        let row = index < table.rows.count ? table.rows[index] : [:]
        let text = table.headers
            .compactMap { header -> String? in
                let value = (row[header] ?? "").trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
            .joined(separator: "  ")
        return UnreadLine(
            // Counting from the file's first line, which is its header.
            text: text, lineNumber: index + 2, problem: problem
        )
    }

    /// Builds one row from a reading.
    /// - Parameters:
    ///   - date: The row's date.
    ///   - descriptor: The descriptor as printed.
    ///   - amount: The signed figure.
    ///   - isCredit: Whether the figure moves money toward the card's balance.
    /// - Returns: The row, or `nil` when the figure rounds to nothing.
    static func statementRow(
        date: Date,
        descriptor: String,
        amount: Decimal,
        isCredit: Bool
    ) -> StatementRow? {
        // The single place a Decimal becomes the Int cents §2 requires. It is unsigned from
        // here on: direction is carried by `kind`, exactly as it is for a PDF row.
        guard let cents = MoneyInput.cents(from: abs(amount)), cents > 0 else { return nil }
        return StatementRow(
            date: date,
            rawDescriptor: descriptor,
            amountCents: cents,
            kind: StatementRowClassifier.kind(descriptor: descriptor, isCredit: isCredit)
        )
    }

    /// Whether a row's figure moves money toward the card's balance.
    ///
    /// A split debit/credit pair answers this outright — the figure's own sign is irrelevant,
    /// because which column it sits in already said which way the money went.
    ///
    /// - Parameters:
    ///   - amount: The signed figure, already resolved for the layout.
    ///   - columns: Which column is which.
    ///   - convention: Which sign means a charge in a single-column file.
    /// - Returns: `true` when the row is a credit.
    static func isCredit(
        _ amount: Decimal,
        columns: CSVStatementColumns,
        convention: CSVSignConvention
    ) -> Bool {
        switch columns.amount {
        case .single: return convention.isCredit(amount)
        case .debitCredit: return amount > 0
        }
    }

    /// The descriptor a row carries.
    /// - Parameters:
    ///   - row: The decoded row.
    ///   - columns: Which column is which.
    /// - Returns: The descriptor, trimmed, or an empty string when the file has no such column.
    static func descriptor(in row: [String: String], columns: CSVStatementColumns) -> String {
        (row[columns.descriptor] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The signed figure a row carries.
    ///
    /// For a split pair the debit column is negated, so the rest of the parser sees one
    /// signed number whichever layout the file used: negative is money out.
    ///
    /// - Parameters:
    ///   - row: The decoded row.
    ///   - columns: Which column is which.
    /// - Returns: The figure, or `nil` when the row holds none.
    static func amount(in row: [String: String], columns: CSVStatementColumns) -> Decimal? {
        switch columns.amount {
        case .single(let column):
            return CSVAmountReader.signedAmount(row[column] ?? "")
        case .debitCredit(let debit, let credit):
            // A file that fills both columns on one row is malformed; the debit is taken,
            // because a charge wrongly imported as a refund is the costlier misreading.
            if let out = CSVAmountReader.signedAmount(row[debit] ?? ""), out != 0 {
                return -abs(out)
            }
            guard let incoming = CSVAmountReader.signedAmount(row[credit] ?? ""), incoming != 0
            else { return nil }
            return abs(incoming)
        }
    }
}
