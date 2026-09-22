import Foundation

/// The address and time heuristics (§9.7).
///
/// Split from ``ReceiptParser`` to keep each file within the 300-line limit.
extension ReceiptParser {

    /// How far down the image a line can sit and still be taken as the address.
    ///
    /// Twice the merchant threshold: the address is printed directly beneath the shop's
    /// name, above the items.
    static var locationTopThreshold: Double { merchantTopThreshold * 2 }

    /// How many address lines are joined together.
    static let locationLineLimit = 2

    /// Finds the shop's address or branch.
    ///
    /// Taken from the lines under the merchant, which is where nearly every receipt
    /// prints it. Phone numbers, websites and the merchant line itself are skipped.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The address, if one was found.
    static func location(in lines: [RecognizedLine]) -> String? {
        let merchantText = merchant(in: lines)
        let candidates = lines
            .filter { $0.topFraction <= locationTopThreshold }
            .sorted { $0.topFraction < $1.topFraction }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0 != merchantText && isPlausibleLocation($0) }
            .prefix(locationLineLimit)

        return candidates.isEmpty ? nil : candidates.joined(separator: ", ")
    }

    /// Whether a line reads like a postal address rather than a phone number or a total.
    ///
    /// An address is the one thing near the top of a receipt that mixes letters and
    /// digits — `120 Bloor St W`, `Toronto ON M5S 1M8`. A phone number is digits and
    /// punctuation only, so requiring letters excludes it without matching on format.
    ///
    /// - Parameter text: The line's text.
    /// - Returns: `true` when it is plausible.
    static func isPlausibleLocation(_ text: String) -> Bool {
        guard text.count >= 5, text.count <= 80 else { return false }
        let lowered = text.lowercased()
        let noise = ["tel", "phone", "fax", "www.", "http", "@", ".com", "receipt", "invoice"]
        guard !noise.contains(where: lowered.contains) else { return false }
        guard !ReceiptParser.totalKeywords.contains(where: lowered.contains) else { return false }
        guard ReceiptParser.amounts(in: text).isEmpty else { return false }

        let letters = text.filter(\.isLetter).count
        let digits = text.filter(\.isNumber).count
        guard letters >= 3 else { return false }
        // Either a street line (letters and a number) or a locality line (letters and a
        // postcode's worth of digits, as in "Toronto ON M5S 1M8").
        return digits >= 1 && digits <= 10
    }

    /// Finds the time of day the receipt was printed.
    ///
    /// Returned as components rather than a `Date` because the *day* comes from
    /// elsewhere; this only says which hour and minute to put on it.
    ///
    /// - Parameter lines: The recognised lines.
    /// - Returns: The hour and minute, if a time was printed.
    static func time(in lines: [RecognizedLine]) -> (hour: Int, minute: Int)? {
        for line in lines {
            if let found = time(inText: line.text) { return found }
        }
        return nil
    }

    /// Reads a time out of one line.
    ///
    /// Handles both 24-hour (`18:42`) and 12-hour (`6:42 PM`) printing. Seconds are
    /// allowed but discarded — no form on this screen shows them.
    ///
    /// - Parameter text: The line's text.
    /// - Returns: The hour and minute, if the line carries a time.
    static func time(inText text: String) -> (hour: Int, minute: Int)? {
        let pattern = /\b(\d{1,2}):([0-5]\d)(?::[0-5]\d)?\s*([AaPp])?\.?[Mm]?\.?/
        for match in text.matches(of: pattern) {
            guard let hour = Int(match.output.1), let minute = Int(match.output.2) else { continue }
            guard let resolved = resolvedHour(hour, meridiem: match.output.3) else { continue }
            return (resolved, minute)
        }
        return nil
    }

    /// Turns a printed hour into a 24-hour one.
    ///
    /// `12 AM` is midnight and `12 PM` is midday — the one case where adding twelve is
    /// wrong in both directions.
    ///
    /// - Parameters:
    ///   - hour: The printed hour.
    ///   - meridiem: The `a` or `p` that followed it, if any.
    /// - Returns: The hour on a 24-hour clock, or `nil` when it is not a real hour.
    static func resolvedHour(_ hour: Int, meridiem: Substring?) -> Int? {
        guard let meridiem else { return (0...23).contains(hour) ? hour : nil }
        guard (1...12).contains(hour) else { return nil }
        let isAfternoon = meridiem.lowercased() == "p"
        if hour == 12 { return isAfternoon ? 12 : 0 }
        return isAfternoon ? hour + 12 : hour
    }

    /// Puts a printed time onto a date.
    ///
    /// When no time was printed the date keeps whatever it had, which for a date-only
    /// receipt is midday — deliberately, so it cannot slide into the neighbouring day
    /// when read back in another time zone (finding B9).
    ///
    /// - Parameters:
    ///   - date: The date to place the time on.
    ///   - time: The hour and minute, if one was printed.
    ///   - calendar: The calendar that resolves the components.
    /// - Returns: The date carrying that time.
    static func applying(
        _ time: (hour: Int, minute: Int)?,
        to date: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let time else { return date }
        return calendar.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: date
        ) ?? date
    }
}
