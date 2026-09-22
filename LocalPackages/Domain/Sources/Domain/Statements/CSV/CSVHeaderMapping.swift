import Foundation

/// Works out which column of a bank's CSV is which (§9.7).
///
/// Declared in Domain, like ``StatementExtracting``, so the model-backed implementation can
/// live in Features and a test can substitute a fake without a simulator.
public protocol CSVHeaderMapping: Sendable {

    /// Maps a header row onto the fields the importer needs.
    ///
    /// Never throws: a mapper that cannot help returns `nil` and the caller falls through to
    /// the next one. The same contract ``StatementExtracting/extract(from:context:)`` keeps,
    /// and for the same reason — one reader failing must cost only that reading.
    ///
    /// - Parameters:
    ///   - headers: The header row, exactly as the file printed it.
    ///   - sampleRows: The first few data rows, so a mapper can look at values rather than
    ///     names alone — which is how a date column is told from a reference number.
    /// - Returns: The map, or `nil` when nothing usable could be worked out.
    func map(headers: [String], sampleRows: [[String: String]]) async -> CSVStatementColumns?
}

/// Maps a header row by matching its wording against known aliases.
///
/// The fallback that makes CSV import work everywhere: deterministic, instant, and testable
/// without a simulator — the same role ``HeuristicDuplicateAdjudicator`` plays for duplicates.
public struct HeuristicCSVHeaderMapper: CSVHeaderMapping {

    /// Creates the mapper.
    public init() {}

    /// Maps a header row by alias.
    /// - Parameters:
    ///   - headers: The header row, exactly as the file printed it.
    ///   - sampleRows: The first few data rows. Unused: the aliases decide.
    /// - Returns: The map, or `nil` when no date column could be identified.
    public func map(
        headers: [String],
        sampleRows: [[String: String]]
    ) async -> CSVStatementColumns? {
        let columns = CSVHeaderMatcher.columns(for: headers)
        return columns.isUsable ? columns : nil
    }
}
