import Foundation

/// Date reading for ``StatementTextParser``.
///
/// Split from the parser to keep each file within the 300-line limit.
extension StatementTextParser {

    /// The month names a statement may print, lowercased, in calendar order.
    static let monthNames = [
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    ]

    /// Reads a date in any of the forms a statement prints.
    /// - Parameters:
    ///   - text: The candidate text.
    ///   - context: The clock and calendar.
    /// - Returns: The date, or `nil` when the text is not a plausible statement date.
    static func date(from text: String, context: StatementParseContext) -> Date? {
        let candidate = text.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
        guard !candidate.isEmpty else { return nil }

        if let iso = ReceiptModelValues.date(
            from: candidate, now: context.now, calendar: context.calendar
        ) {
            return iso
        }
        if let numeric = numericDate(from: candidate, context: context) { return numeric }
        return namedMonthDate(from: candidate, context: context)
    }

    /// Reads `03/09/2026`, `03-09-26` or `03/09`.
    ///
    /// The order comes from the context, which settles it once for the whole file — see
    /// ``StatementDateOrder``. A part above twelve can only be a day whatever the order says,
    /// so `25/12` still reads correctly in a file the reader called month-first.
    ///
    /// - Parameters:
    ///   - text: The candidate text.
    ///   - context: The clock and calendar.
    /// - Returns: The date, or `nil`.
    static func numericDate(from text: String, context: StatementParseContext) -> Date? {
        let parts = text
            .split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
            .map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let first = Int(parts[0]), let second = Int(parts[1]) else { return nil }

        let (month, day) = monthAndDay(first, second, order: context.dateOrder)
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        guard parts.count == 3, let rawYear = Int(parts[2]) else {
            return resolved(month: month, day: day, year: nil, context: context)
        }
        let year = rawYear < 100 ? 2_000 + rawYear : rawYear
        return resolved(month: month, day: day, year: year, context: context)
    }

    /// Splits a numeric date's first two numbers into a month and a day.
    ///
    /// The file's order decides, except where one number settles it on its own: a number above
    /// twelve is a day, whichever position it sits in.
    ///
    /// - Parameters:
    ///   - first: The first number printed.
    ///   - second: The second number printed.
    ///   - order: Which position the file puts the month in.
    /// - Returns: The month and the day.
    static func monthAndDay(
        _ first: Int,
        _ second: Int,
        order: StatementDateOrder
    ) -> (month: Int, day: Int) {
        if first > 12, second <= 12 { return (second, first) }
        if second > 12, first <= 12 { return (first, second) }
        return order == .dayFirst ? (second, first) : (first, second)
    }

    /// Reads `Mar 9` or `9 Mar`.
    /// - Parameters:
    ///   - text: The candidate text.
    ///   - context: The clock and calendar.
    /// - Returns: The date, or `nil`.
    static func namedMonthDate(from text: String, context: StatementParseContext) -> Date? {
        let words = text
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." })
            .map { $0.lowercased() }
        guard words.count == 2 else { return nil }

        let monthIndex = words.firstIndex { word in
            monthNames.contains { word.hasPrefix($0) }
        }
        guard let monthIndex,
              let month = monthNames.firstIndex(where: { words[monthIndex].hasPrefix($0) })
                .map({ $0 + 1 }),
              let day = Int(words[1 - monthIndex]), (1...31).contains(day) else { return nil }

        return resolved(month: month, day: day, year: nil, context: context)
    }

    /// Builds a date, choosing the year when the statement did not print one.
    ///
    /// A year-less date resolves to the plausible year nearest `now`, so a December
    /// statement read in January lands in the year just gone rather than a year ahead.
    ///
    /// - Parameters:
    ///   - month: The month.
    ///   - day: The day of the month.
    ///   - year: The year, when the statement printed one.
    ///   - context: The clock and calendar.
    /// - Returns: The date, or `nil` when it is implausible or not a real day.
    static func resolved(
        month: Int,
        day: Int,
        year: Int?,
        context: StatementParseContext
    ) -> Date? {
        let currentYear = context.calendar.component(.year, from: context.now)
        let years = year.map { [$0] } ?? [currentYear, currentYear - 1, currentYear + 1]

        let dates = years.compactMap { candidateYear -> Date? in
            var components = DateComponents()
            components.year = candidateYear
            components.month = month
            components.day = day
            guard let date = context.calendar.date(from: components),
                  context.calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        guard let nearest = dates.min(by: {
            abs($0.timeIntervalSince(context.now)) < abs($1.timeIntervalSince(context.now))
        }) else { return nil }

        let limit = Double(plausibleYears) * 365.25 * 86_400
        guard abs(nearest.timeIntervalSince(context.now)) <= limit else { return nil }
        return nearest
    }
}
