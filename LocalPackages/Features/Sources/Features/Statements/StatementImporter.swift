import Foundation
import Domain

/// Runs a statement file through reading, extraction and adjudication (§9.7).
///
/// The only statement-reading type the UI touches. The order mirrors ``ReceiptScanner``:
/// the file is read, the on-device model interprets it, and the deterministic parser fills
/// whatever the model left out — or replaces it entirely when the model could not run.
///
/// Reading can fail loudly, because a statement the user picked and cannot be opened is
/// something they need told. Everything after that degrades quietly instead.
@MainActor
@Observable
final class StatementImporter {

    /// How far along the current import is, for the progress row.
    private(set) var phase: StatementImportPhase = .idle

    /// Opens the file and gets its text.
    private let reader: any StatementTextReading
    /// The preferred row reader.
    private let primary: any StatementExtracting
    /// The reader that covers what the preferred one cannot.
    private let fallback: any StatementExtracting
    /// The preferred duplicate judge.
    private let adjudicator: any DuplicateAdjudicating
    /// The judge that covers whatever the preferred one did not answer.
    private let backupAdjudicator: any DuplicateAdjudicating
    /// The preferred reader of a delimited export's header.
    private let csvMapper: any CSVHeaderMapping
    /// The header reader that covers what the preferred one cannot.
    private let fallbackCSVMapper: any CSVHeaderMapping
    /// Reads the lines the deterministic parsers could not.
    private let repairer: any UnreadLineRepairing

    /// Creates an importer.
    ///
    /// Every dependency is defaulted, so adding the delimited-export path changed no caller.
    ///
    /// - Parameters:
    ///   - reader: Opens the file and gets its text.
    ///   - primary: The preferred row reader.
    ///   - fallback: The reader that covers what the preferred one cannot.
    ///   - adjudicator: The preferred duplicate judge.
    ///   - backupAdjudicator: The judge covering whatever the preferred one left.
    ///   - csvMapper: The preferred reader of a delimited export's header.
    ///   - fallbackCSVMapper: The header reader covering what the preferred one cannot.
    ///   - repairer: Reads the lines the deterministic parsers could not.
    nonisolated init(
        reader: any StatementTextReading = StatementFileReader(),
        primary: any StatementExtracting = FoundationModelsStatementExtractor(),
        fallback: any StatementExtracting = HeuristicStatementExtractor(),
        adjudicator: any DuplicateAdjudicating = FoundationModelsDuplicateAdjudicator(),
        backupAdjudicator: any DuplicateAdjudicating = HeuristicDuplicateAdjudicator(),
        csvMapper: any CSVHeaderMapping = FoundationModelsCSVHeaderMapper(),
        fallbackCSVMapper: any CSVHeaderMapping = HeuristicCSVHeaderMapper(),
        repairer: any UnreadLineRepairing = FoundationModelsRowRepairer()
    ) {
        self.reader = reader
        self.primary = primary
        self.fallback = fallback
        self.adjudicator = adjudicator
        self.backupAdjudicator = backupAdjudicator
        self.csvMapper = csvMapper
        self.fallbackCSVMapper = fallbackCSVMapper
        self.repairer = repairer
    }

    /// Reads again the lines every deterministic parser failed on.
    ///
    /// Separate from ``read(_:context:)`` and never called on its own: the user asks for it
    /// from the review screen, having seen which lines are in question. See
    /// ``UnreadLineRepairing`` for why this is not simply part of reading.
    ///
    /// - Parameters:
    ///   - lines: The lines to read again.
    ///   - context: The clock and calendar.
    /// - Returns: What could be read. May be empty.
    func repair(
        _ lines: [UnreadLine],
        context: StatementParseContext = StatementParseContext()
    ) async -> [RepairedLine] {
        guard !lines.isEmpty else { return [] }
        phase = .understanding(page: 1, pageCount: 1)
        defer { phase = .idle }
        return await repairer.repair(lines, context: context)
    }

    /// Reads a statement file into rows.
    /// - Parameters:
    ///   - source: What the user picked.
    ///   - context: The clock and calendar.
    /// - Returns: What the statement said.
    /// - Throws: ``StatementImportError`` when the file cannot be read at all.
    func read(
        _ source: StatementFileSource,
        context: StatementParseContext = StatementParseContext()
    ) async throws -> StatementDocument {
        phase = .reading
        defer { phase = .idle }

        // A delimited export carries its structure in a header row, so none of the reading
        // below applies: there is no page to rasterise, no text to recognise, and no prose
        // for a row parser to pick a date out of.
        if case .csv(let csv) = source {
            return try await readDelimited(csv, context: context)
        }

        let text = try await reader.read(source)
        guard !text.isEmpty else { throw StatementImportError.noTextFound }

        phase = .understanding(page: 1, pageCount: text.pages.count)
        let led = await primary.extract(from: text, context: context)
        let backup = await fallback.extract(from: text, context: context)
        var document = led.rows.isEmpty ? backup : led.completed(with: backup)

        // The card's digits are read off the text directly rather than merged from the
        // model, for the reason `TenderParser` gives: a masked number is an exact pattern,
        // so there is nothing for a model to be better at.
        let tender = TenderParser.parse(text.lines)
        if document.tender.last4 == nil { document.tender.last4 = tender.last4 }
        if document.tender.network == nil { document.tender.network = tender.network }
        return document
    }

    /// Reads a delimited export into a document.
    ///
    /// The header is mapped by the on-device model first and by the deterministic matcher
    /// after — the same order, and the same reason, as the two row readers above: the model
    /// reads wording no alias list anticipated, and the matcher guarantees an answer.
    ///
    /// - Parameters:
    ///   - csv: The file's text.
    ///   - context: The clock and calendar.
    /// - Returns: What the export said.
    /// - Throws: ``StatementImportError/noColumnsFound`` when neither mapper could read the
    ///   header, which is the one CSV failure worth telling the user about.
    private func readDelimited(
        _ csv: String,
        context: StatementParseContext
    ) async throws -> StatementDocument {
        let table = CSVCodec.table(csv, delimiter: CSVCodec.inferDelimiter(csv))
        // At least one *named* column: a file of blank lines parses to a header row of
        // empty strings, which is not a header row and must not be reported as one whose
        // columns merely could not be identified.
        guard table.headers.contains(where: { !$0.isEmpty }) else {
            throw StatementImportError.unreadableCSV
        }

        phase = .understanding(page: 1, pageCount: 1)
        // Written out rather than coalesced: `??` takes an autoclosure, which cannot await.
        var columns = await csvMapper.map(headers: table.headers, sampleRows: table.rows)
        if columns == nil {
            columns = await fallbackCSVMapper.map(headers: table.headers, sampleRows: table.rows)
        }
        guard let columns else { throw StatementImportError.noColumnsFound }

        return CSVStatementParser.document(table: table, columns: columns, context: context)
    }

    /// Judges every conflict, falling back for any the preferred judge did not answer.
    ///
    /// The returned array always covers every conflict, so the wizard never has a step with
    /// nothing to say.
    ///
    /// - Parameters:
    ///   - conflicts: The pairs to judge.
    ///   - context: What the judges need beyond the pairs.
    /// - Returns: One verdict per conflict, in the conflicts' own order.
    func adjudicate(
        _ conflicts: [DuplicateConflict],
        context: DuplicateAdjudicationContext = DuplicateAdjudicationContext()
    ) async -> [DuplicateVerdict] {
        guard !conflicts.isEmpty else { return [] }
        phase = .adjudicating
        defer { phase = .idle }

        let led = await adjudicator.adjudicate(conflicts, context: context)
        var byConflict = Dictionary(led.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let unanswered = conflicts.filter { byConflict[$0.id] == nil }
        if !unanswered.isEmpty {
            for verdict in await backupAdjudicator.adjudicate(unanswered, context: context) {
                byConflict[verdict.id] = verdict
            }
        }
        return conflicts.compactMap { byConflict[$0.id] }
    }

    /// Reports progress from outside, so a caller driving the pipeline can narrate it.
    /// - Parameter phase: The phase to show.
    func report(_ phase: StatementImportPhase) { self.phase = phase }
}
