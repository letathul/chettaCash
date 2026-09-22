import Foundation

/// Reads an amount cell into an exact signed `Decimal` (§9.7, §2).
///
/// **Why `Decimal` here and `Int` cents everywhere else.** §2 forbids floating point for
/// money and stores cents, which this app never departs from. But a bank cell is *text* in
/// a dozen dialects — `$1,234.56`, `(42.10)`, `42.10 CR`, `1.234,56`, `−42.10` — and the
/// sign is expressed four different ways. `Decimal` is the exact base-ten intermediate that
/// lets the sign be settled separately from the magnitude; it is converted to cents the
/// moment a ``StatementRow`` is built and never travels further.
///
/// The magnitude itself is read by ``MoneyInput/decimal(from:)`` rather than parsed again
/// here, so the app has exactly one rule for what a separator means.
public enum CSVAmountReader {

    /// Suffixes a bank appends to mark direction, lowercased.
    ///
    /// `CR` is a credit and `DR` a debit, which some exports print instead of a sign.
    static let creditSuffixes = ["cr", "c"]
    /// Suffixes marking a debit.
    static let debitSuffixes = ["dr", "d"]

    /// Reads one amount cell.
    ///
    /// Negative is recognised from a leading `-`, a Unicode minus, wrapping parentheses, or
    /// a trailing `DR`. Positive from a leading `+` or a trailing `CR`. A bare figure is
    /// positive, and what that *means* is decided by ``CSVSignConvention``, not here.
    ///
    /// - Parameter text: The cell, exactly as the file printed it.
    /// - Returns: The signed amount, or `nil` when the cell holds no figure.
    public static func signedAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let (body, isNegative) = stripSign(trimmed)
        guard let magnitude = MoneyInput.decimal(from: body) else { return nil }
        return isNegative ? -magnitude : magnitude
    }

    /// Separates the direction markers from the figure.
    /// - Parameter text: The trimmed cell.
    /// - Returns: The figure's text and whether it is negative.
    static func stripSign(_ text: String) -> (body: String, isNegative: Bool) {
        var body = text
        var isNegative = false

        // Parentheses are accountancy's minus sign and wrap everything else, so they come
        // off first: "($42.10)" must not be read as a positive figure with stray brackets.
        if body.hasPrefix("("), body.hasSuffix(")") {
            body = String(body.dropFirst().dropLast())
            isNegative = true
        }
        body = body.trimmingCharacters(in: .whitespaces)

        if let suffix = matchedSuffix(in: body) {
            body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if debitSuffixes.contains(suffix) { isNegative = true }
        }
        if body.hasPrefix("-") || body.hasPrefix("\u{2212}") {
            body = String(body.dropFirst())
            // A figure marked negative twice — "(-42.10)" — is still simply negative.
            isNegative = true
        } else if body.hasPrefix("+") {
            body = String(body.dropFirst())
        }
        return (body, isNegative)
    }

    /// The direction suffix a cell ends with, lowercased.
    ///
    /// Only accepted when a letter follows the digits, so a currency code such as the `usd`
    /// in `"42.10 USD"` is left alone rather than read as a debit marker.
    ///
    /// - Parameter body: The cell with any parentheses already removed.
    /// - Returns: The suffix, or `nil` when the cell ends in a digit.
    static func matchedSuffix(in body: String) -> String? {
        let lowered = body.lowercased()
        for suffix in creditSuffixes + debitSuffixes where lowered.hasSuffix(suffix) {
            let head = lowered.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            // The remainder must still look like a figure; "CREDIT" ends in "t", and
            // "DEC" would otherwise read as a credit.
            guard head.contains(where: \.isNumber), !head.hasSuffix(where: \.isLetter) else {
                continue
            }
            return suffix
        }
        return nil
    }
}

/// Testing a string's last character.
private extension String {

    /// Whether the last character satisfies a predicate.
    /// - Parameter predicate: The test to apply.
    /// - Returns: `true` when there is a last character and it passes.
    func hasSuffix(where predicate: (Character) -> Bool) -> Bool {
        guard let last else { return false }
        return predicate(last)
    }
}
