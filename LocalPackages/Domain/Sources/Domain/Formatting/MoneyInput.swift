import Foundation

/// Parses typed money into cents (§2: `Int` cents everywhere, never `Double`).
public enum MoneyInput {

    /// The most digits accepted, which keeps the result inside `Int` on any device.
    private static let maximumDigits = 15

    /// Parses a typed amount into cents.
    ///
    /// Accepts grouped input such as `"1,234.56"` and a leading minus. Because the
    /// app's currency code is a display label rather than a locale, the last
    /// separator is treated as a decimal point only when one or two digits follow
    /// it; otherwise every separator is treated as grouping. So `"1,234"` is
    /// `123_400` cents and `"1,23"` is `123` cents.
    ///
    /// - Parameter input: The raw text from a money field.
    /// - Returns: The amount in cents, or `nil` when the text holds no digits or is
    ///   too long to represent.
    public static func cents(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isNegative = trimmed.hasPrefix("-") || trimmed.hasPrefix("\u{2212}")
        let body = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard body.contains(where: \.isNumber) else { return nil }

        let (wholeText, fractionText) = split(body)
        let digits = wholeText.filter(\.isNumber)
        guard digits.count <= maximumDigits else { return nil }

        let whole = Int(digits) ?? 0
        let fraction = Int(fractionText.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let magnitude = whole * 100 + fraction
        return isNegative ? -magnitude : magnitude
    }

    /// Converts an exact decimal amount into cents.
    ///
    /// App Intents hands a currency parameter over as a `Decimal`, which is exact for
    /// decimal fractions — so `12.10` really is twelve and ten hundredths here, with
    /// none of the representation error that makes `Double` unusable for money (§2).
    /// Half-up rounding at the cent, because a third decimal place in a typed amount
    /// is a slip rather than a denomination.
    ///
    /// - Parameter decimal: The amount, in whole currency units.
    /// - Returns: The amount in cents, or `nil` when negative or too large for `Int`.
    public static func cents(from decimal: Decimal) -> Int? {
        guard decimal >= 0 else { return nil }
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        guard number.compare(NSDecimalNumber(value: Int.max)) != .orderedDescending else {
            return nil
        }
        return number.intValue
    }

    /// Converts a typed decimal amount into cents.
    ///
    /// App Intents hands a plain number parameter over as a `Double`, which is the
    /// only place in the app a `Double` may carry money — and it stops here. The value
    /// is widened to `Decimal` first so the rounding is done in base ten, on the
    /// number the `Double` actually holds.
    ///
    /// That last part matters for a third decimal place: `1.005` typed into a `Double`
    /// is really 1.00499…, so it yields 100 rather than 101. That is faithful to the
    /// input rather than a rounding bug, and a half-cent is not a denomination anyone
    /// meant to spend.
    ///
    /// - Parameter value: The amount, in whole currency units.
    /// - Returns: The amount in cents, or `nil` when negative, infinite, or too large
    ///   for `Int`.
    public static func cents(fromAmount value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return cents(from: Decimal(value))
    }

    /// Renders cents back into an editable string, without a currency symbol.
    ///
    /// Used to seed a money field when editing an existing record.
    ///
    /// - Parameter cents: The amount in cents.
    /// - Returns: A plain decimal string such as `"1234.56"`.
    public static func editableText(fromCents cents: Int) -> String {
        let magnitude = abs(cents)
        let text = String(format: "%d.%02d", magnitude / 100, magnitude % 100)
        return cents < 0 ? "-" + text : text
    }

    /// Parses a typed amount as an unsigned magnitude.
    ///
    /// Money fields present a `.decimalPad`, which has no minus key, so the user types
    /// "what it is" and the sign is decided by context — the transaction's mode, or the
    /// account's ``BalanceEntry/Direction``. Any sign that does reach this (from a
    /// hardware keyboard, or text pasted in) is discarded rather than honoured, so the
    /// typed figure can never contradict the direction the user chose.
    ///
    /// - Parameter input: The raw text from a money field.
    /// - Returns: The magnitude in cents, never negative, or `nil` when the text holds
    ///   no digits or is too long to represent.
    public static func magnitudeCents(from input: String) -> Int? {
        cents(from: input).map(abs)
    }

    /// Renders cents into an editable magnitude, without a sign or a currency symbol.
    ///
    /// Seeds a money field when editing an existing record. The sign is dropped because
    /// the field cannot express one; it is carried by the direction control beside it.
    ///
    /// - Parameter cents: The amount in cents, of either sign.
    /// - Returns: A plain unsigned decimal string such as `"1234.56"`.
    public static func magnitudeText(fromCents cents: Int) -> String {
        editableText(fromCents: abs(cents))
    }

    /// Splits typed digits into whole and fractional parts.
    /// - Parameter body: The input reduced to digits and separators.
    /// - Returns: The whole-number text and the fractional text, which may be empty.
    private static func split(_ body: String) -> (whole: String, fraction: String) {
        guard let separatorIndex = body.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return (body, "")
        }
        let after = body[body.index(after: separatorIndex)...]
        guard (1...2).contains(after.count), after.allSatisfy(\.isNumber) else {
            return (body, "")
        }
        return (String(body[..<separatorIndex]), String(after))
    }

    /// Parses a typed amount into an exact decimal magnitude.
    ///
    /// The counterpart to ``cents(from:)`` for a caller that needs the figure *before* it
    /// becomes cents — a statement column whose sign is decided by a separate convention,
    /// say. It applies the same last-separator rule, so `"1,234"` reads as one thousand two
    /// hundred and thirty-four and `"1.234,56"` as that number with fifty-six hundredths.
    ///
    /// The fraction is added as `fraction / 100` rather than folded into a cents integer,
    /// which would overflow on a fifteen-digit figure. `Decimal` is base ten, so dividing
    /// by a power of ten is exact rather than merely close.
    ///
    /// - Parameter input: The raw text from an amount column.
    /// - Returns: The magnitude, never negative, or `nil` when the text holds no digits or
    ///   is too long to represent.
    public static func decimal(from input: String) -> Decimal? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let body = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard body.contains(where: \.isNumber) else { return nil }

        let (wholeText, fractionText) = split(body)
        let digits = wholeText.filter(\.isNumber)
        guard digits.count <= maximumDigits else { return nil }

        // Both fall back to zero exactly as `cents(from:)` does: an empty whole part is
        // ".50", and an empty fraction is a round figure.
        let whole = Int(digits) ?? 0
        let fraction = Int(fractionText.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        return Decimal(whole) + Decimal(fraction) / 100
    }
}
