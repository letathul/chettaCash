import Foundation
import Domain

/// Turning the model's answers into Domain values.
///
/// Split from ``FoundationModelsStatementExtractor`` to keep each file within the
/// 300-line limit.
extension FoundationModelsStatementExtractor {

    /// The session's instructions.
    ///
    /// The model is told to report and not to interpret, and explicitly allowed to leave a
    /// field empty. A row it invents is money in the ledger that was never spent, which is
    /// far worse than a row it misses — the deterministic reader catches those.
    static var instructions: String {
        """
        You read credit-card statements. You are given the text of one page of a \
        statement, exactly as it was read, including any errors.

        List every transaction line on the page and nothing else. Do not include \
        subtotals, balances brought forward, credit limits, interest rate tables, or \
        summary figures. Report only what the page says: leave a field empty rather than \
        guessing at it, and never invent a line that is not printed.
        """
    }

    /// Converts one of the model's rows into a statement row.
    /// - Parameters:
    ///   - extracted: What the model returned for the line.
    ///   - context: The clock and calendar.
    /// - Returns: The row, or `nil` when it lacks a date or a usable amount.
    static func row(
        from extracted: ExtractedRow,
        context: StatementParseContext
    ) -> StatementRow? {
        guard let date = ReceiptModelValues.date(
            from: extracted.date, now: context.now, calendar: context.calendar
        ) else { return nil }
        guard let cents = ReceiptModelValues.cents(from: extracted.amount), cents > 0 else {
            return nil
        }
        guard let descriptor = cleaned(extracted.descriptor) else { return nil }

        let merchant = cleaned(extracted.merchant)
        return StatementRow(
            date: date,
            rawDescriptor: descriptor,
            amountCents: cents,
            kind: kind(from: extracted.kind, descriptor: descriptor),
            // A tidied name only survives if it is actually different and not obviously
            // wrong: a "cleanup" that dropped the shop entirely would file the purchase
            // under a name the user cannot recognise.
            cleanedMerchant: merchant.flatMap { $0 == descriptor ? nil : $0 }
        )
    }

    /// Reads the model's `kind` word, falling back to the deterministic classifier.
    ///
    /// The classifier has the final say on payments. Whether a credit is a payment decides
    /// whether a row is written at all (§4.3), so it is not left to a word the model chose.
    ///
    /// - Parameters:
    ///   - text: The model's answer.
    ///   - descriptor: The line's descriptor.
    /// - Returns: What kind of line it is.
    static func kind(from text: String?, descriptor: String) -> StatementRowKind {
        let stated = cleaned(text).map { $0.lowercased() }
            .flatMap { StatementRowKind(rawValue: $0) }
        guard let stated else {
            return StatementRowClassifier.kind(descriptor: descriptor, isCredit: false)
        }
        guard stated != .charge else { return .charge }
        // The model said this is money coming back; the classifier decides which kind.
        return StatementRowClassifier.kind(descriptor: descriptor, isCredit: true)
    }

    /// Keeps only the digits of a card number the model returned.
    /// - Parameter text: The model's answer.
    /// - Returns: Four digits, or `nil` when the answer is not four digits.
    static func digits(_ text: String?) -> String? {
        guard let text else { return nil }
        let digits = text.filter(\.isNumber)
        return digits.count == 4 ? String(digits) : nil
    }

    /// Trims a model answer, treating a blank one as no answer at all.
    /// - Parameter text: The model's answer, if it gave one.
    /// - Returns: The trimmed text, or `nil` when it is empty.
    static func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

/// The deterministic reader, used when the model is unavailable or missed a page.
///
/// A thin adapter over ``StatementTextParser``, mirroring ``HeuristicReceiptExtractor``.
struct HeuristicStatementExtractor: StatementExtracting {

    /// Reads every row the text yields.
    /// - Parameters:
    ///   - statement: The recognised text.
    ///   - context: The clock and calendar.
    /// - Returns: What could be read.
    func extract(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) async -> StatementDocument {
        let reading = StatementTextParser.reading(from: statement, context: context)
        return StatementDocument(
            tender: TenderParser.parse(statement.lines),
            rows: reading.rows,
            source: .textHeuristics,
            unread: reading.unread,
            sourceLineCount: reading.lineCount
        )
    }
}
