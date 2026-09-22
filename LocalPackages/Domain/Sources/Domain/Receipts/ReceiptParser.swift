import Foundation

/// One line of text recognised on a receipt, with where it sat on the page.
public struct RecognizedLine: Equatable, Sendable {
    /// The recognised text.
    public let text: String
    /// How far down the image the line sat, from `0` at the top to `1` at the bottom.
    public let topFraction: Double

    /// Creates a line.
    /// - Parameters:
    ///   - text: The recognised text.
    ///   - topFraction: How far down the image it sat.
    public init(text: String, topFraction: Double) {
        self.text = text
        self.topFraction = topFraction
    }
}

/// What a receipt scan managed to extract (§9.7).
///
/// **Every field is a pre-fill, not a commitment.** The form shows them as ordinary
/// editable fields with a "from receipt" marker, and a failed scan simply leaves the
/// form empty rather than blocking.
public struct ReceiptScanResult: Equatable, Sendable {
    /// The total, if one was found.
    public var amountCents: Int?
    /// The merchant, if one was found.
    public var merchant: String?
    /// The date, carrying the printed time when one was found.
    public var date: Date?
    /// The shop's address or branch, if one was printed.
    public var location: String?
    /// What the reader called this purchase's category.
    ///
    /// Plain text, not an identifier: it is whatever the reader said, and may name no
    /// category this user actually has. ``ReceiptPrefillBuilder`` resolves it against the
    /// real list, or discards it.
    public var categoryLabel: String?
    /// The card details from the payment line, if any were printed.
    public var tender: ReceiptTender?
    /// Which reader produced these fields.
    public var source: ReceiptScanSource = .textHeuristics

    /// Whether nothing at all could be read.
    public var isEmpty: Bool {
        amountCents == nil && merchant == nil && date == nil && location == nil
            && categoryLabel == nil && (tender?.isEmpty ?? true)
    }

    /// Creates a result.
    /// - Parameters:
    ///   - amountCents: The total.
    ///   - merchant: The merchant.
    ///   - date: The date, with the printed time when there was one.
    ///   - location: The shop's address or branch.
    ///   - categoryLabel: What the reader called the category.
    ///   - tender: The card details from the payment line.
    ///   - source: Which reader produced the fields.
    public init(
        amountCents: Int? = nil,
        merchant: String? = nil,
        date: Date? = nil,
        location: String? = nil,
        categoryLabel: String? = nil,
        tender: ReceiptTender? = nil,
        source: ReceiptScanSource = .textHeuristics
    ) {
        self.amountCents = amountCents
        self.merchant = merchant
        self.date = date
        self.location = location
        self.categoryLabel = categoryLabel
        self.tender = tender
        self.source = source
    }

    /// Fills in whatever this result is missing from another reader's attempt.
    ///
    /// The model is better at the merchant and the date; the heuristics are reliable
    /// on a plainly printed total. Neither has to win outright — a field this result
    /// left `nil` is taken from `other`, and ``source`` stays as this result's, since
    /// it is the one that led.
    ///
    /// - Parameter other: The other reader's result.
    /// - Returns: The combined result.
    public func completed(with other: ReceiptScanResult) -> ReceiptScanResult {
        ReceiptScanResult(
            amountCents: amountCents ?? other.amountCents,
            merchant: merchant ?? other.merchant,
            date: date ?? other.date,
            location: location ?? other.location,
            categoryLabel: categoryLabel ?? other.categoryLabel,
            tender: (tender?.isEmpty == false) ? tender : other.tender,
            source: isEmpty ? other.source : source
        )
    }
}

/// Extracts what a receipt says from its recognised text (§9.7).
///
/// The amount, merchant, date and time, the shop's address, and the card's details.
/// There is deliberately **no line-item extraction**: ``Product`` carries no price and a
/// transaction has no items collection, so there is nowhere for line items to go (§7.8).
public enum ReceiptParser {

    /// Words that mark the line carrying the total.
    ///
    /// "Subtotal" is excluded deliberately — matching it would pick the pre-tax
    /// figure on most receipts.
    static let totalKeywords = ["total", "amount due", "balance due", "grand total"]

    /// Words that disqualify a line from being the total.
    static let excludedKeywords = ["subtotal", "sub total", "change", "tip", "tax"]

    /// How far down the image a line can sit and still be taken as the merchant.
    static let merchantTopThreshold = 0.25

    /// Parses recognised lines into a pre-fill.
    /// - Parameters:
    ///   - lines: The recognised lines, in any order.
    ///   - now: The moment used to reject implausible dates.
    /// - Returns: What could be extracted.
    public static func parse(_ lines: [RecognizedLine], now: Date = .now) -> ReceiptScanResult {
        ReceiptScanResult(
            amountCents: total(in: lines),
            merchant: merchant(in: lines),
            date: date(in: lines, now: now),
            location: location(in: lines),
            tender: tender(in: lines)
        )
    }

    /// Reads the card off the payment line, or `nil` when nothing was printed.
    ///
    /// An empty tender is reported as no tender at all, so a caller need only check for
    /// `nil` rather than for `nil` *or* empty.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The card details, if any were printed.
    static func tender(in lines: [RecognizedLine]) -> ReceiptTender? {
        let found = TenderParser.parse(lines)
        return found.isEmpty ? nil : found
    }

    /// Finds the receipt's total.
    ///
    /// Prefers the largest currency-formatted value on a line mentioning a total
    /// keyword; falls back to the largest value anywhere when no keyword appears.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The total in cents, if one was found.
    static func total(in lines: [RecognizedLine]) -> Int? {
        let keyworded = lines.filter { line in
            let lowered = line.text.lowercased()
            guard !excludedKeywords.contains(where: lowered.contains) else { return false }
            return totalKeywords.contains(where: lowered.contains)
        }
        if let best = largestAmount(in: keyworded) { return best }
        let usable = lines.filter { line in
            !excludedKeywords.contains(where: line.text.lowercased().contains)
        }
        return largestAmount(in: usable)
    }

    /// The largest currency-formatted value across some lines.
    /// - Parameter lines: The lines to search.
    /// - Returns: The largest value in cents, if any.
    private static func largestAmount(in lines: [RecognizedLine]) -> Int? {
        lines.flatMap { amounts(in: $0.text) }.max()
    }

    /// Every currency-formatted value on a line.
    ///
    /// Requires two decimal places, which is what separates `12.99` from a quantity
    /// like `2` or a phone number.
    ///
    /// - Parameter text: The line's text.
    /// - Returns: The values in cents.
    static func amounts(in text: String) -> [Int] {
        // Boundaries are checked by inspecting the neighbouring characters rather
        // than with look-around: Swift's regex literals do not support lookbehind.
        let pattern = /(\d{1,3}(?:,\d{3})*|\d+)\.(\d{2})/
        return text.matches(of: pattern).compactMap { match in
            guard hasCleanBoundaries(match.range, in: text) else { return nil }
            let whole = String(match.output.1).replacingOccurrences(of: ",", with: "")
            guard let units = Int(whole), let fraction = Int(match.output.2) else { return nil }
            return units * 100 + fraction
        }
    }

    /// Whether a matched amount is not part of a longer number.
    ///
    /// Rejects the `56.78` inside `1234.5678` and the `.99` inside a version string.
    ///
    /// - Parameters:
    ///   - range: The match's range.
    ///   - text: The line it was found in.
    /// - Returns: `true` when the match stands alone.
    private static func hasCleanBoundaries(
        _ range: Range<String.Index>,
        in text: String
    ) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isNumber || before == "." { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isNumber { return false }
        }
        return true
    }

    /// Finds the merchant name.
    ///
    /// Taken from the topmost text block, which on nearly every receipt is the shop's
    /// name. Lines that are mostly digits or punctuation are skipped.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The merchant, if one was found.
    static func merchant(in lines: [RecognizedLine]) -> String? {
        lines
            .filter { $0.topFraction <= merchantTopThreshold }
            .sorted { $0.topFraction < $1.topFraction }
            .first { isPlausibleMerchant($0.text) }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Whether a line reads like a shop name rather than an address or a number.
    /// - Parameter text: The line's text.
    /// - Returns: `true` when it is plausible.
    private static func isPlausibleMerchant(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        let letters = trimmed.filter(\.isLetter).count
        return letters >= 3 && Double(letters) / Double(trimmed.count) > 0.5
    }

    /// Finds the receipt's date, carrying the printed time when there is one.
    ///
    /// Uses `NSDataDetector`, which handles the many formats receipts print, and
    /// rejects anything in the future or implausibly old.
    ///
    /// The time is then set explicitly rather than left to the detector. A receipt that
    /// prints its date and time on separate lines gives the detector only the date, and
    /// a date-only match lands at midnight — an hour either side of which the purchase
    /// reads as the wrong day once a time zone is applied. A printed time is used when
    /// one is found anywhere on the page; otherwise the day is pinned to midday, which
    /// is what ``ReceiptModelValues`` does for the same reason (finding B9).
    ///
    /// - Parameters:
    ///   - lines: The recognised lines.
    ///   - now: The moment used to bound plausibility.
    ///   - calendar: The calendar that places the time.
    /// - Returns: The date, if one was found.
    static func date(
        in lines: [RecognizedLine],
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let text = lines.map(\.text).joined(separator: "\n")
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let earliest = now.addingTimeInterval(-10 * 365 * 86_400)
        let latest = now.addingTimeInterval(86_400)
        guard let found = detector.matches(in: text, range: range)
            .compactMap(\.date)
            .first(where: { $0 >= earliest && $0 <= latest })
        else { return nil }

        let placed = applying(
            time(in: lines) ?? (hour: 12, minute: 0), to: found, calendar: calendar
        )
        // Placing a time can push a receipt from yesterday's midnight into tomorrow.
        return placed <= latest ? placed : found
    }
}
