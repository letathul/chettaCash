import Foundation

/// The card details printed on a receipt's payment line (§9.7).
///
/// Read off the receipt, not chosen by the user. ``AccountMatcher`` turns this into an
/// account, and only when it is unambiguous.
public struct ReceiptTender: Equatable, Sendable {
    /// The last four digits of the card, if they were printed.
    public var last4: String?
    /// The payment network, if it was named.
    public var network: CardNetwork?

    /// Whether the payment line said nothing usable.
    public var isEmpty: Bool { last4 == nil && network == nil }

    /// Creates a tender.
    /// - Parameters:
    ///   - last4: The last four digits of the card.
    ///   - network: The payment network.
    public init(last4: String? = nil, network: CardNetwork? = nil) {
        self.last4 = last4
        self.network = network
    }
}

/// Reads the card network and last four digits off a receipt (§9.7).
///
/// Deliberately kept out of the language model's shape. A masked card number is a crisp
/// pattern that a regex reads exactly, where a model can only paraphrase it — and every
/// field dropped from the generable shape is generation time saved.
///
/// The accuracy here is mostly in what it *refuses*. A receipt is dense with four-digit
/// numbers that are not card digits: authorisation codes, store numbers, terminal IDs,
/// times and years. Taking one of those would silently post money to the wrong account,
/// so an unmasked figure is only read when its line says it is a card.
public enum TenderParser {

    /// Words that name a network, longest spelling first so `master card` wins over `mc`.
    static let networkKeywords: [(String, CardNetwork)] = [
        ("american express", .amex),
        ("mastercard", .mastercard),
        ("master card", .mastercard),
        ("unionpay", .unionpay),
        ("union pay", .unionpay),
        ("discover", .discover),
        ("interac", .interac),
        ("visa", .visa),
        ("amex", .amex)
    ]

    /// Words marking a line as being about the card rather than the purchase.
    static let cardKeywords = [
        "card", "tender", "debit", "credit", "acct", "account", "payment", "paid", "chip"
    ]

    /// Words marking a number as an identifier that merely looks like card digits.
    ///
    /// A masked number overrules these: `AUTH ****1234` is still the card.
    static let identifierKeywords = [
        "auth", "ref", "trace", "invoice", "order", "trans", "seq", "store",
        "terminal", "term", "batch", "merchant", "mid", "tid", "receipt", "check", "reg"
    ]

    /// Reads the payment line.
    /// - Parameter lines: The recognised lines, in any order.
    /// - Returns: What the payment line said, empty when it said nothing usable.
    public static func parse(_ lines: [RecognizedLine]) -> ReceiptTender {
        ReceiptTender(last4: last4(in: lines), network: network(in: lines))
    }

    /// Finds the card network.
    ///
    /// Searched across the whole receipt rather than one line: the network is often
    /// printed in the footer, well away from the digits.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The network, if one was named.
    static func network(in lines: [RecognizedLine]) -> CardNetwork? {
        for line in lines {
            let lowered = line.text.lowercased()
            if let match = networkKeywords.first(where: { lowered.contains($0.0) }) {
                return match.1
            }
        }
        return nil
    }

    /// Finds the card's last four digits.
    ///
    /// Tried in descending order of confidence, and the first that hits wins: a masked
    /// number anywhere, then a worded one, then a bare group on a line that names a card.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The digits, if they were printed.
    static func last4(in lines: [RecognizedLine]) -> String? {
        if let masked = lines.lazy.compactMap({ maskedDigits(in: $0.text) }).first {
            return masked
        }
        if let worded = lines.lazy.compactMap({ wordedDigits(in: $0.text) }).first {
            return worded
        }
        return lines.lazy.compactMap { bareDigits(in: $0.text) }.first
    }

    /// The digits following a run of masking characters, such as `**** 4821`.
    ///
    /// Masking is proof on its own, so a line that also says `AUTH` is still accepted.
    ///
    /// - Parameter text: The line's text.
    /// - Returns: The digits, if the line carries a masked number.
    static func maskedDigits(in text: String) -> String? {
        let pattern = /[*xX#•·\u{2022}]{2,}[\s-]*(\d{4})/
        guard let match = text.matches(of: pattern).last else { return nil }
        return String(match.output.1)
    }

    /// The digits following a phrase naming them, such as `ending in 4821`.
    /// - Parameter text: The line's text.
    /// - Returns: The digits, if the line words them.
    static func wordedDigits(in text: String) -> String? {
        let pattern = /(?:ending(?:\s+in)?|ends\s+(?:in|with)|last\s*4)\D{0,6}(\d{4})/
            .ignoresCase()
        guard let match = text.matches(of: pattern).last else { return nil }
        return String(match.output.1)
    }

    /// A bare four-digit group on a line that identifies itself as being about a card.
    ///
    /// The weakest of the three, so it carries the most refusals: the line must name a
    /// card or a network, must not name an identifier, and the digits must stand alone
    /// rather than sit inside a longer number or an amount.
    ///
    /// - Parameter text: The line's text.
    /// - Returns: The digits, if the line plausibly carries them.
    static func bareDigits(in text: String) -> String? {
        let lowered = text.lowercased()
        let namesCard = cardKeywords.contains(where: lowered.contains)
            || networkKeywords.contains { lowered.contains($0.0) }
        guard namesCard, !identifierKeywords.contains(where: lowered.contains) else { return nil }

        let money = Set(ReceiptParser.amounts(in: text))
        return text.matches(of: /\d{4}/)
            .filter { standsAlone($0.range, in: text) }
            .map { String($0.output) }
            .last { digits in
                // `19.99` on a card line must not be read as the digits `1999`.
                guard let value = Int(digits) else { return false }
                return !money.contains(value) && !money.contains(value * 100)
            }
    }

    /// Whether a four-digit run is a number of its own rather than part of a longer one.
    ///
    /// Mirrors ``ReceiptParser`` — Swift's regex literals have no lookbehind, so the
    /// neighbouring characters are inspected directly.
    ///
    /// - Parameters:
    ///   - range: The match's range.
    ///   - text: The line it was found in.
    /// - Returns: `true` when the run stands alone.
    static func standsAlone(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isNumber || before == "." || before == "," { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isNumber || after == "." || after == "," { return false }
        }
        return true
    }
}
