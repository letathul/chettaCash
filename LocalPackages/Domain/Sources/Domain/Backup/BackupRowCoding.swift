import Foundation

/// Converts a domain value to and from a CSV row (§9.4).
///
/// Every row carries its own `id` and its foreign-key `id`s, which is what makes the
/// archive re-importable rather than a flat dump.
public protocol BackupRowConvertible {
    /// The column order this entity's table uses.
    static var backupColumns: [String] { get }
    /// Converts this value into a CSV row.
    /// - Returns: The row, keyed by column name.
    func backupRow() -> [String: String]
    /// Rebuilds a value from a CSV row.
    /// - Parameter row: The row, keyed by column name.
    /// - Returns: The value, or `nil` when the row is unusable.
    static func fromBackupRow(_ row: [String: String]) -> Self?
}

/// Field encoding shared by every backup row.
///
/// Dates use ISO 8601 and money stays in integer cents, so a round trip is exact.
public enum BackupField {

    /// The date format used throughout an archive.
    ///
    /// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the older class
    /// is not `Sendable`, so a shared instance cannot be a static under strict
    /// concurrency, and building one per call would be wasteful.
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Encodes a date.
    /// - Parameter date: The date, if any.
    /// - Returns: An ISO 8601 string, or empty.
    public static func string(_ date: Date?) -> String {
        date.map { dateStyle.format($0) } ?? ""
    }

    /// Decodes a date.
    /// - Parameter text: The stored text.
    /// - Returns: The date, or `nil` when absent or unparseable.
    public static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return try? dateStyle.parse(text)
    }

    /// Encodes an integer.
    /// - Parameter value: The value, if any.
    /// - Returns: Its decimal text, or empty.
    public static func string(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    /// Decodes an integer.
    /// - Parameter text: The stored text.
    /// - Returns: The value, or `nil` when absent or unparseable.
    public static func int(_ text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        return Int(text)
    }

    /// Encodes a double.
    /// - Parameter value: The value, if any.
    /// - Returns: Its decimal text, or empty.
    public static func string(_ value: Double?) -> String {
        value.map { String($0) } ?? ""
    }

    /// Decodes a double.
    /// - Parameter text: The stored text.
    /// - Returns: The value, or `nil` when absent or unparseable.
    public static func double(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        return Double(text)
    }

    /// Encodes an identifier.
    /// - Parameter id: The identifier, if any.
    /// - Returns: Its string form, or empty.
    public static func string(_ id: UUID?) -> String {
        id?.uuidString ?? ""
    }

    /// Decodes an identifier.
    /// - Parameter text: The stored text.
    /// - Returns: The identifier, or `nil` when absent or unparseable.
    public static func uuid(_ text: String?) -> UUID? {
        guard let text, !text.isEmpty else { return nil }
        return UUID(uuidString: text)
    }

    /// Encodes a boolean.
    /// - Parameter value: The value.
    /// - Returns: `"true"` or `"false"`.
    public static func string(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Decodes a boolean.
    /// - Parameters:
    ///   - text: The stored text.
    ///   - fallback: What to use when the text is absent.
    /// - Returns: The value.
    public static func bool(_ text: String?, default fallback: Bool = false) -> Bool {
        guard let text, !text.isEmpty else { return fallback }
        return text == "true"
    }

    /// Encodes a tag list.
    ///
    /// Tags are joined with a unit separator rather than a comma, so a tag containing
    /// a comma cannot split into two on import.
    ///
    /// - Parameter tags: The tags.
    /// - Returns: The joined text.
    public static func string(_ tags: [String]) -> String {
        tags.joined(separator: "\u{1F}")
    }

    /// Decodes a tag list.
    /// - Parameter text: The stored text.
    /// - Returns: The tags.
    public static func tags(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text.components(separatedBy: "\u{1F}")
    }
}
