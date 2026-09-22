import Foundation

/// Reads statement rows straight off the text, with no model involved (§9.7).
///
/// The counterpart to the on-device reader, and what makes an import possible at all on a
/// device where the model is unavailable or declines. Deliberately conservative: a line it
/// cannot read confidently produces nothing, because a row invented from a misread line is
/// money in the ledger that was never spent.
///
/// The shape it looks for is the one every statement shares — a date at the start, an
/// amount at the end, and the descriptor in between.
public enum StatementTextParser {

    /// How many years either side of now a statement date may fall.
    ///
    /// Two, which covers a statement filed late without admitting a line whose "date" is
    /// really an account number.
    static let plausibleYears = 2

    /// Reads every row it can off a statement's lines.
    /// - Parameters:
    ///   - statement: The recognised text.
    ///   - context: The clock and calendar dates are resolved against.
    /// - Returns: The rows, in the order they appeared.
    public static func rows(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) -> [StatementRow] {
        reading(from: statement, context: context).rows
    }

    /// What one pass over a statement's lines produced.
    public struct Reading: Sendable, Equatable {
        /// The rows that could be read.
        public var rows: [StatementRow]
        /// The lines that looked like transactions but could not be read.
        public var unread: [UnreadLine]
        /// How many lines were looked at.
        public var lineCount: Int

        /// Creates a reading.
        /// - Parameters:
        ///   - rows: The rows that could be read.
        ///   - unread: The lines that could not be.
        ///   - lineCount: How many lines were looked at.
        public init(rows: [StatementRow] = [], unread: [UnreadLine] = [], lineCount: Int = 0) {
            self.rows = rows
            self.unread = unread
            self.lineCount = lineCount
        }
    }

    /// Reads every row it can, and reports the lines it could not read.
    ///
    /// **A half-read line is reported; an unrelated one is not.** A line carrying a date or
    /// an amount but not both is a transaction the parser failed on, and the user needs to see
    /// it. A line carrying neither is page furniture — a heading, an interest-rate table, a
    /// paragraph of marketing — and reporting those would bury the few that matter.
    ///
    /// - Parameters:
    ///   - statement: The recognised text.
    ///   - context: The clock and calendar dates are resolved against.
    /// - Returns: The rows, the unread lines, and how many lines were looked at.
    public static func reading(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) -> Reading {
        var reading = Reading(lineCount: statement.lines.count)
        var pageByLine: [Int] = []
        for (index, page) in statement.pages.enumerated() {
            pageByLine.append(contentsOf: repeatElement(index + 1, count: page.lines.count))
        }

        for (index, line) in statement.lines.enumerated() {
            if let row = row(from: line.text, context: context) {
                reading.rows.append(row)
            } else if let problem = problem(in: line.text, context: context) {
                reading.unread.append(
                    UnreadLine(
                        text: line.text.trimmingCharacters(in: .whitespaces),
                        page: index < pageByLine.count ? pageByLine[index] : nil,
                        lineNumber: index + 1,
                        problem: problem
                    )
                )
            }
        }
        return reading
    }

    /// Why a line that looked like a transaction did not become one.
    /// - Parameters:
    ///   - text: The line's text.
    ///   - context: The clock and calendar dates are resolved against.
    /// - Returns: The problem, or `nil` when the line was never a transaction to begin with.
    static func problem(in text: String, context: StatementParseContext) -> UnreadProblem? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard let (_, afterDate) = leadingDate(in: trimmed, context: context) else {
            // No date. Only worth reporting when the line nonetheless ends in an amount,
            // which is what a wrapped descriptor or a stranded amount column looks like.
            return trailingAmount(in: trimmed).map { _ in .noDate }
        }
        guard let amount = trailingAmount(in: afterDate) else { return .noAmount }
        guard amount.cents > 0 else { return .zeroAmount }

        let cleaned = amount.descriptor.trimmingCharacters(
            in: .whitespaces.union(CharacterSet(charactersIn: "-\u{2013}\u{2014}\u{00B7}|"))
        )
        return cleaned.isEmpty ? .noDescriptor : nil
    }

    /// Reads one line.
    /// - Parameters:
    ///   - text: The line's text.
    ///   - context: The clock and calendar dates are resolved against.
    /// - Returns: The row, or `nil` when the line is not a transaction.
    static func row(from text: String, context: StatementParseContext) -> StatementRow? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let (date, afterDate) = leadingDate(in: trimmed, context: context),
              let amount = trailingAmount(in: afterDate),
              amount.cents > 0 else { return nil }

        let cleanedDescriptor = amount.descriptor.trimmingCharacters(
            in: .whitespaces.union(CharacterSet(charactersIn: "-–—·|"))
        )
        guard !cleanedDescriptor.isEmpty else { return nil }

        return StatementRow(
            date: date,
            rawDescriptor: cleanedDescriptor,
            amountCents: amount.cents,
            kind: StatementRowClassifier.kind(
                descriptor: cleanedDescriptor, isCredit: amount.isCredit
            )
        )
    }

    /// Reads a date off the start of a line.
    ///
    /// Accepts the forms statements actually print — `2026-03-09`, `03/09/2026`, `03/09`,
    /// `Mar 9` — and resolves a year-less date to the plausible one nearest `now`, so a
    /// December statement read in January does not land a year ahead.
    ///
    /// - Parameters:
    ///   - text: The line.
    ///   - context: The clock and calendar.
    /// - Returns: The date and the rest of the line, or `nil` when the line has no date.
    static func leadingDate(
        in text: String,
        context: StatementParseContext
    ) -> (date: Date, rest: String)? {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return nil }

        // A month name takes two words ("Mar 9"); every numeric form takes one.
        for wordCount in [2, 1] where words.count > wordCount {
            let candidate = words.prefix(wordCount).joined(separator: " ")
            if let date = date(from: candidate, context: context) {
                return (date, words.dropFirst(wordCount).joined(separator: " "))
            }
        }
        return nil
    }

    /// An amount read off the end of a line, with what preceded it.
    struct TrailingAmount {
        /// The magnitude in cents, always positive.
        let cents: Int
        /// Whether the line moves money toward the card's balance.
        let isCredit: Bool
        /// Everything before the amount.
        let descriptor: String
    }

    /// Reads an amount off the end of a line.
    ///
    /// A trailing `CR`, a trailing `-`, or a parenthesised figure marks a credit — the
    /// three ways statements print money coming back.
    ///
    /// - Parameter text: The line, after its date.
    /// - Returns: The amount and the descriptor before it, or `nil` when there is none.
    static func trailingAmount(in text: String) -> TrailingAmount? {
        var working = text.trimmingCharacters(in: .whitespaces)
        var isCredit = false

        for marker in ["CR", "cr", "Cr"] where working.hasSuffix(marker) {
            isCredit = true
            working = String(working.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        let words = working.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard var last = words.last else { return nil }

        if last.hasPrefix("(") && last.hasSuffix(")") {
            isCredit = true
            last = String(last.dropFirst().dropLast())
        }
        if last.hasSuffix("-") {
            isCredit = true
            last = String(last.dropLast())
        }
        if last.hasPrefix("-") {
            isCredit = true
            last = String(last.dropFirst())
        }

        // Reuses the receipt reader's money parser, which already refuses a bare integer
        // and a number too long to be a price — the account numbers and phone numbers a
        // statement is full of.
        guard let cents = ReceiptModelValues.cents(from: last) else { return nil }
        return TrailingAmount(
            cents: cents, isCredit: isCredit, descriptor: words.dropLast().joined(separator: " ")
        )
    }
}
