import Foundation
import FoundationModels
import Domain

/// Reads the lines the deterministic parsers could not, with Apple's on-device model (§9.7).
///
/// **The narrowest useful use of a model in this pipeline.** ``StatementTextParser`` looks for
/// the shape every statement shares — a date at the start, an amount at the end — and reports
/// whatever does not fit as an ``UnreadLine`` rather than dropping it. Those leftovers are
/// exactly the lines worth a model's time: a wrapped descriptor, a date written in a form no
/// alias covers, an amount printed beside a running balance.
///
/// Sending *every* row instead would cost seconds per statement and let the model rewrite rows
/// the parser already had right — a worse trade, since a row invented from a misread line is
/// money in the ledger that was never spent.
///
/// Nothing leaves the device, and nothing is committed: a repaired line arrives on the review
/// screen unticked, like everything else.
struct FoundationModelsRowRepairer: UnreadLineRepairing {

    /// One line, read again.
    @Generable
    struct ReadLine {
        /// Which line of the batch this answers, counting from one.
        @Guide(description: "The number printed before the line you are describing.")
        var number: Int?
        /// The date the line carries.
        @Guide(description: """
            The transaction date in yyyy-MM-dd form, for example 2026-03-09. \
            Leave empty if this line carries no date.
            """)
        var date: String?
        /// The merchant descriptor.
        @Guide(description: """
            The merchant descriptor exactly as the line printed it, unchanged. \
            Leave empty if the line names no merchant.
            """)
        var descriptor: String?
        /// The amount the line carries.
        @Guide(description: """
            The amount as digits with two decimal places and no sign, for example 42.10. \
            Leave empty if the line carries no amount.
            """)
        var amount: String?
        /// Whether the line is money coming back.
        @Guide(description: """
            One of exactly these words: charge, refund, payment. \
            Use payment only for a payment made to the card account itself.
            """)
        var kind: String?
    }

    /// One batch's answer.
    @Generable
    struct ReadBatch {
        /// Every line the model could read.
        @Guide(description: "One entry per numbered line you can read. Omit any you cannot.")
        var lines: [ReadLine]
    }

    /// How many lines go in one prompt.
    ///
    /// Ten: enough that a statement's leftovers usually fit in one or two rounds, few enough
    /// that a batch the model mangles costs little and that the numbering stays reliable.
    static let batchSize = 10

    /// The most lines that will be sent at all.
    ///
    /// A statement whose every line is unread is one the reader failed on wholesale, and
    /// feeding all of it to the model a batch at a time would take minutes to produce answers
    /// the user must check anyway. Better to show them the file could not be read.
    static let lineLimit = 60

    /// The model to ask. Injectable so a test can force the unavailable path.
    let model: SystemLanguageModel

    /// Creates the repairer.
    /// - Parameter model: The model to ask.
    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Whether the model reports itself ready.
    ///
    /// Necessary but not sufficient, as everywhere else here: a model reporting `.available`
    /// still throws when asked to generate in the Simulator, where the generative assets are
    /// absent. This gate only avoids pointless work.
    var isAvailable: Bool { model.availability == .available }

    /// Reads what it can of the lines a parser could not.
    /// - Parameters:
    ///   - lines: The lines to read again.
    ///   - context: The clock and calendar dates resolve against.
    /// - Returns: What could be read.
    func repair(
        _ lines: [UnreadLine],
        context: StatementParseContext
    ) async -> [RepairedLine] {
        guard isAvailable, !lines.isEmpty else { return [] }

        var repaired: [RepairedLine] = []
        for batch in Array(lines.prefix(Self.lineLimit)).chunked(into: Self.batchSize) {
            repaired.append(contentsOf: await read(batch, context: context))
        }
        return repaired
    }

    /// Asks the model about one batch.
    /// - Parameters:
    ///   - batch: The lines in this batch.
    ///   - context: The clock and calendar.
    /// - Returns: What could be read of the batch.
    private func read(
        _ batch: [UnreadLine],
        context: StatementParseContext
    ) async -> [RepairedLine] {
        do {
            let session = LanguageModelSession(model: model) { Self.instructions }
            let response = try await session.respond(
                to: Self.question(batch), generating: ReadBatch.self
            )
            return rows(from: response.content, batch: batch, context: context)
        } catch {
            // The model declining, the session being interrupted and the Simulator's missing
            // assets all mean one thing: leave these lines for the user to type in.
            return []
        }
    }

    /// Turns a batch's answer into rows, discarding anything unusable.
    /// - Parameters:
    ///   - answer: What the model returned.
    ///   - batch: The lines it was shown.
    ///   - context: The clock and calendar.
    /// - Returns: The rows that survived checking.
    func rows(
        from answer: ReadBatch,
        batch: [UnreadLine],
        context: StatementParseContext
    ) -> [RepairedLine] {
        answer.lines.compactMap { line in
            // The number is checked against the batch rather than trusted: a model that
            // miscounts would otherwise attach one line's figures to another line's identity,
            // and the review would show the user a row they cannot trace to their statement.
            guard let number = line.number, number >= 1, number <= batch.count else { return nil }
            guard let row = Self.row(from: line, context: context) else { return nil }
            return RepairedLine(id: batch[number - 1].id, row: row)
        }
    }

    /// Converts one answered line into a statement row.
    /// - Parameters:
    ///   - line: What the model returned for the line.
    ///   - context: The clock and calendar.
    /// - Returns: The row, or `nil` when it lacks a date or a usable amount.
    static func row(from line: ReadLine, context: StatementParseContext) -> StatementRow? {
        guard let date = ReceiptModelValues.date(
            from: line.date, now: context.now, calendar: context.calendar
        ) else { return nil }
        guard let cents = ReceiptModelValues.cents(from: line.amount), cents > 0 else {
            return nil
        }
        let descriptor = line.descriptor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !descriptor.isEmpty else { return nil }

        return StatementRow(
            date: date,
            rawDescriptor: descriptor,
            amountCents: cents,
            // The classifier has the final say on payments, exactly as it does for a page the
            // model read: whether a credit is a payment decides whether a row may be written
            // at all (§4.3), so it is not left to a word the model chose.
            kind: FoundationModelsStatementExtractor.kind(
                from: line.kind, descriptor: descriptor
            )
        )
    }

    /// What the model is told before it is shown anything.
    static let instructions = """
        You are reading individual lines from a bank or credit-card statement that an \
        automatic reader could not interpret. Each line is numbered.

        For each line you can read, report its number, its date, its merchant descriptor and \
        its amount. Report only what the line says: leave a field empty rather than guessing \
        at it, never invent a line, and omit any numbered line you cannot read. A line may be \
        a fragment carrying only an amount or only a date — omit those.
        """

    /// The prompt: the lines, numbered.
    /// - Parameter batch: The lines in this batch.
    /// - Returns: The prompt.
    static func question(_ batch: [UnreadLine]) -> String {
        batch.enumerated()
            .map { index, line in "\(index + 1). \(line.text)" }
            .joined(separator: "\n")
    }
}

/// Splitting a collection into fixed-size batches.
extension Array {

    /// Breaks the array into chunks of at most `size`.
    /// - Parameter size: The most elements a chunk may hold.
    /// - Returns: The chunks, in order.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
