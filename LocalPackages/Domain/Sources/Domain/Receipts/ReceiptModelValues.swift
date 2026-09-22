import Foundation

/// Parses the strings Apple's on-device model returns for a receipt (§9.7).
///
/// The model is asked for text, not numbers, for two reasons. Money is `Int` cents
/// everywhere in this app, and routing a total through `Double` would put rounding in
/// the one place it must not be. And a date given as `yyyy-MM-dd` is unambiguous,
/// where `09/10/2026` is not — `NSDataDetector` resolves that one in the *device's*
/// locale, so a US receipt misreads on a UK phone (finding B9).
public enum ReceiptModelValues {

    /// Parses a total into cents.
    ///
    /// Accepts what a model plausibly returns around the number it was asked for — a
    /// leading currency symbol, thousands separators, one or no decimal place — and
    /// rejects anything else rather than guessing.
    ///
    /// - Parameter text: The model's answer, if it gave one.
    /// - Returns: The total in cents, or `nil` when it cannot be read.
    public static func cents(from text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !digits.hasPrefix("-") else { return nil }

        let parts = normalized(digits).split(separator: ".", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let units = Int(parts[0]) else { return nil }
            return units * 100
        case 2:
            guard let units = Int(parts[0]), parts[1].count <= 2,
                  let fraction = Int(parts[1]) else { return nil }
            return units * 100 + (parts[1].count == 1 ? fraction * 10 : fraction)
        default:
            return nil
        }
    }

    /// Reduces a number to digits and at most one dot.
    ///
    /// A comma is a thousands separator when a dot is also present, and the decimal
    /// point when it stands alone before exactly two final digits.
    ///
    /// - Parameter digits: The number, already stripped of everything else.
    /// - Returns: The number with `.` as its only separator.
    private static func normalized(_ digits: String) -> String {
        guard !digits.contains("."),
              let comma = digits.lastIndex(of: ","),
              digits.distance(from: comma, to: digits.endIndex) == 3
        else { return digits.replacingOccurrences(of: ",", with: "") }

        var swapped = digits
        swapped.replaceSubrange(comma...comma, with: ".")
        return swapped.replacingOccurrences(of: ",", with: "")
    }

    /// Parses a `yyyy-MM-dd` date.
    ///
    /// Read positionally rather than through a formatter, so the result does not
    /// depend on the device's locale or calendar preference. Anything in the future
    /// or implausibly old is rejected, matching ``ReceiptParser``.
    ///
    /// - Parameters:
    ///   - text: The model's answer, if it gave one.
    ///   - now: The moment used to bound plausibility.
    ///   - calendar: The calendar that turns the components into an instant.
    /// - Returns: The date at midday, or `nil` when it cannot be read.
    public static func date(
        from text: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        date(from: text, time: nil, now: now, calendar: calendar)
    }

    /// Parses a `yyyy-MM-dd` date and an `HH:mm` time together.
    ///
    /// Both are read positionally, for the same reason: a formatter would resolve them
    /// in the *device's* locale and calendar, so a receipt would read differently on two
    /// phones. A time that cannot be read is discarded rather than guessed at, leaving
    /// the midday fallback in place.
    ///
    /// - Parameters:
    ///   - text: The model's date, if it gave one.
    ///   - time: The model's time in `HH:mm` form, if it gave one.
    ///   - now: The moment used to bound plausibility.
    ///   - calendar: The calendar that turns the components into an instant.
    /// - Returns: The date at the printed time, or at midday, or `nil` when unreadable.
    public static func date(
        from text: String?,
        time: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), parts[0].count == 4,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day),
              let parsed = calendar.date(
                  from: DateComponents(
                      year: year,
                      month: month,
                      day: day,
                      // Midday when no time was printed, so a receipt does not slide into
                      // the neighbouring day when read back in another time zone.
                      hour: clock(from: time)?.hour ?? 12,
                      minute: clock(from: time)?.minute ?? 0
                  )
              )
        else { return nil }

        let earliest = now.addingTimeInterval(-10 * 365 * 86_400)
        let latest = now.addingTimeInterval(86_400)
        return (earliest...latest).contains(parsed) ? parsed : nil
    }

    /// Parses an `HH:mm` time on a 24-hour clock.
    ///
    /// Anything else — a 12-hour time the model was not asked for, a stray word, an
    /// impossible hour — is refused, so a bad answer costs the time rather than the day.
    ///
    /// - Parameter text: The model's answer, if it gave one.
    /// - Returns: The hour and minute, or `nil` when it cannot be read.
    static func clock(from text: String?) -> (hour: Int, minute: Int)? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), (0...23).contains(hour),
              let minute = Int(parts[1]), parts[1].count == 2, (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }
}
