import Foundation
@testable import Features
import Domain

/// A ``StatementTextReading`` that returns whatever a test hands it.
///
/// Kept in its own file rather than added to `FakeServices.swift`, which is already close
/// to the 300-line limit.
struct FakeStatementReader: StatementTextReading {
    /// What to return.
    var statement: RecognizedStatement
    /// When set, the read throws it instead.
    var failure: StatementImportError?

    /// Creates a reader.
    /// - Parameters:
    ///   - statement: What to return.
    ///   - failure: An error to throw instead.
    init(statement: RecognizedStatement = RecognizedStatement(pages: []),
         failure: StatementImportError? = nil) {
        self.statement = statement
        self.failure = failure
    }

    func read(_ source: StatementFileSource) async throws -> RecognizedStatement {
        if let failure { throw failure }
        return statement
    }
}

/// A ``StatementExtracting`` that returns a fixed document.
struct FakeStatementExtractor: StatementExtracting {
    /// What to return.
    var document: StatementDocument

    /// Creates an extractor.
    /// - Parameter document: What to return.
    init(document: StatementDocument = StatementDocument()) {
        self.document = document
    }

    func extract(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) async -> StatementDocument {
        document
    }
}

/// A ``DuplicateAdjudicating`` that answers only the conflicts a test tells it to.
///
/// Answering a subset is the point: it is how a test proves the importer fills the gaps
/// from the fallback rather than leaving a wizard step with nothing to say.
struct FakeDuplicateAdjudicator: DuplicateAdjudicating {
    /// How many conflicts to answer, counting from the first. `nil` answers all.
    var answerLimit: Int?
    /// What to answer.
    var judgement: DuplicateJudgement
    /// Which source to claim.
    var source: ReceiptScanSource

    /// Creates an adjudicator.
    /// - Parameters:
    ///   - answerLimit: How many conflicts to answer. `nil` answers all.
    ///   - judgement: What to answer.
    ///   - source: Which source to claim.
    init(
        answerLimit: Int? = nil,
        judgement: DuplicateJudgement = .sameTransaction,
        source: ReceiptScanSource = .onDeviceModel
    ) {
        self.answerLimit = answerLimit
        self.judgement = judgement
        self.source = source
    }

    func adjudicate(
        _ conflicts: [DuplicateConflict],
        context: DuplicateAdjudicationContext
    ) async -> [DuplicateVerdict] {
        conflicts.prefix(answerLimit ?? conflicts.count).map { conflict in
            DuplicateVerdict(
                id: conflict.id,
                judgement: judgement,
                rationale: "Because the fake said so.",
                source: source
            )
        }
    }
}

/// A ``CSVHeaderMapping`` that returns a fixed map, or declines.
///
/// Declining is the point: it is how a test proves the importer falls through to the
/// deterministic matcher rather than giving up on the file.
struct FakeCSVHeaderMapper: CSVHeaderMapping {
    /// What to return, or `nil` to decline.
    var columns: CSVStatementColumns?
    /// Set when the mapper was asked, so a test can prove the order it was asked in.
    let wasAsked = Box()

    /// A reference box, so a `Sendable` value type can record that it ran.
    final class Box: @unchecked Sendable {
        /// Whether the mapper was asked.
        private(set) var value = false
        /// Records that the mapper was asked.
        func mark() { value = true }
    }

    /// Creates a mapper.
    /// - Parameter columns: What to return, or `nil` to decline.
    init(columns: CSVStatementColumns? = nil) {
        self.columns = columns
    }

    func map(headers: [String], sampleRows: [[String: String]]) async -> CSVStatementColumns? {
        wasAsked.mark()
        return columns
    }
}

/// A repairer that answers with rows a test chose (§9.7).
///
/// Keyed by the unread line's text rather than its identifier, because a test writes the text
/// and the identifier is generated.
struct FakeRowRepairer: UnreadLineRepairing {
    /// What to answer for each line, by the line's text.
    var answers: [String: StatementRow] = [:]

    /// Reads what the test told it to.
    /// - Parameters:
    ///   - lines: The lines to read again.
    ///   - context: The clock and calendar.
    /// - Returns: The answers for the lines it was given.
    func repair(
        _ lines: [UnreadLine],
        context: StatementParseContext
    ) async -> [RepairedLine] {
        lines.compactMap { line in
            answers[line.text].map { RepairedLine(id: line.id, row: $0) }
        }
    }
}
