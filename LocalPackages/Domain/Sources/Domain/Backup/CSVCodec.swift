import Foundation

/// Reads and writes the CSV tables inside a backup archive (§9.4).
///
/// Quoting follows RFC 4180: a field containing a comma, a quote or a newline is
/// wrapped in quotes, and embedded quotes are doubled. Without that, a merchant
/// called `Smith, Jones & Co` would silently split into two columns on import.
public enum CSVCodec {

    /// Encodes rows into a CSV document.
    /// - Parameters:
    ///   - rows: The rows, each keyed by column name.
    ///   - columns: The column order, which becomes the header row.
    /// - Returns: The CSV text.
    public static func encode(rows: [[String: String]], columns: [String]) -> String {
        var lines = [columns.map(escape).joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { escape(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Decodes a CSV document into rows keyed by column name.
    /// - Parameters:
    ///   - text: The CSV text, including its header row.
    ///   - delimiter: What separates fields. Defaults to a comma, which is what the backup
    ///     archive writes; a bank export should pass ``inferDelimiter(_:)``.
    /// - Returns: The rows, in file order. Empty when the document has no header.
    public static func decode(_ text: String, delimiter: Character = ",") -> [[String: String]] {
        table(text, delimiter: delimiter).rows
    }

    /// Decodes a CSV document, keeping the header row.
    ///
    /// The header is needed as an *ordered list* to work out which column is which, which
    /// ``decode(_:delimiter:)`` throws away by keying each row. Both go through the one
    /// parser so the two readings can never disagree about where a quoted field ended.
    ///
    /// - Parameters:
    ///   - text: The CSV text, including its header row.
    ///   - delimiter: What separates fields.
    /// - Returns: The header row and the data rows. Empty when the document has no header.
    public static func table(_ text: String, delimiter: Character = ",") -> CSVTable {
        var records = parse(stripBOM(text), delimiter: delimiter)
        guard !records.isEmpty else { return CSVTable() }
        let columns = records.removeFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        let rows = records
            .filter { !($0.count == 1 && $0[0].isEmpty) }
            .map { record in
                var row: [String: String] = [:]
                for (index, column) in columns.enumerated() where index < record.count {
                    row[column] = record[index]
                }
                return row
            }
        return CSVTable(headers: columns, rows: rows)
    }

    /// The delimiters a bank export might use, in preference order.
    static let candidateDelimiters: [Character] = [",", ";", "\t", "|"]

    /// Works out what separates a document's fields.
    ///
    /// **Field-count consistency rather than a raw tally.** Counting occurrences would pick
    /// the comma out of `"Smith, Jones";"42,10"` — the file is semicolon-separated and the
    /// commas sit *inside* fields. Parsing with each candidate and asking which one yields a
    /// header and body that agree on width is the question that actually matters, and it
    /// costs a parse of a few lines.
    ///
    /// - Parameter text: The CSV text.
    /// - Returns: The delimiter, defaulting to a comma when nothing is better.
    public static func inferDelimiter(_ text: String) -> Character {
        let sample = stripBOM(text).split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(sampleLines).joined(separator: "\n")
        guard !sample.isEmpty else { return "," }

        var best: (delimiter: Character, fields: Int) = (",", 0)
        for delimiter in candidateDelimiters {
            let records = parse(sample, delimiter: delimiter)
            guard let header = records.first, header.count > 1 else { continue }
            // Every row must have the header's width, or this delimiter is splitting
            // somewhere the file did not intend.
            guard records.dropFirst().allSatisfy({ $0.count == header.count || $0 == [""] })
            else { continue }
            if header.count > best.fields { best = (delimiter, header.count) }
        }
        return best.fields > 0 ? best.delimiter : ","
    }

    /// How many lines the delimiter inference looks at.
    static let sampleLines = 5

    /// Removes a byte-order mark, which would otherwise become part of the first header.
    ///
    /// A BOM on `"Date"` makes the header `"\u{FEFF}Date"`, which matches no alias and
    /// silently costs the file its date column.
    ///
    /// - Parameter text: The document text.
    /// - Returns: The text without a leading byte-order mark.
    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// Wraps a field in quotes when it needs them.
    /// - Parameter field: The raw field value.
    /// - Returns: The escaped field.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n")
            || field.contains("\r") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The parser's running state.
    private struct ParseState {
        /// Completed records.
        var records: [[String]] = []
        /// Fields of the record being built.
        var fields: [String] = []
        /// The field being built.
        var field = ""
        /// Whether the cursor is inside a quoted field.
        var isQuoted = false

        /// Ends the current field.
        mutating func endField() {
            fields.append(field)
            field = ""
        }

        /// Ends the current record.
        mutating func endRecord() {
            endField()
            records.append(fields)
            fields = []
        }
    }

    /// Splits a CSV document into records of fields, honouring quoting.
    /// - Parameters:
    ///   - text: The CSV text.
    ///   - delimiter: What separates fields.
    /// - Returns: The records.
    private static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        let characters = Array(text)
        var state = ParseState()
        var index = 0

        while index < characters.count {
            if state.isQuoted {
                index = consumeQuoted(characters, at: index, into: &state)
            } else {
                consumeUnquoted(characters[index], delimiter: delimiter, into: &state)
                index += 1
            }
        }
        if !state.field.isEmpty || !state.fields.isEmpty { state.endRecord() }
        return state.records
    }

    /// Consumes one character inside a quoted field.
    /// - Parameters:
    ///   - characters: The whole document.
    ///   - index: Where the cursor is.
    ///   - state: The running state.
    /// - Returns: Where the cursor moves to.
    private static func consumeQuoted(
        _ characters: [Character],
        at index: Int,
        into state: inout ParseState
    ) -> Int {
        let character = characters[index]
        guard character == "\"" else {
            state.field.append(character)
            return index + 1
        }
        // A doubled quote inside a quoted field is a literal quote.
        if index + 1 < characters.count, characters[index + 1] == "\"" {
            state.field.append("\"")
            return index + 2
        }
        state.isQuoted = false
        return index + 1
    }

    /// Consumes one character outside a quoted field.
    /// - Parameters:
    ///   - character: The character to consume.
    ///   - delimiter: What separates fields.
    ///   - state: The running state.
    private static func consumeUnquoted(
        _ character: Character,
        delimiter: Character,
        into state: inout ParseState
    ) {
        switch character {
        case "\"": state.isQuoted = true
        case delimiter: state.endField()
        case "\n": state.endRecord()
        case "\r": break
        default: state.field.append(character)
        }
    }
}

/// A decoded CSV document, header included.
public struct CSVTable: Sendable, Equatable {
    /// The header row, in file order.
    public var headers: [String]
    /// The data rows, each keyed by column name.
    public var rows: [[String: String]]

    /// Whether the document held nothing to read.
    public var isEmpty: Bool { headers.isEmpty || rows.isEmpty }

    /// Creates a table.
    /// - Parameters:
    ///   - headers: The header row.
    ///   - rows: The data rows.
    public init(headers: [String] = [], rows: [[String: String]] = []) {
        self.headers = headers
        self.rows = rows
    }
}
