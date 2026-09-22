import Foundation

/// Computes when a ``RecurringRule`` fires (§4.5).
///
/// **Month-end handling is the subtle part.** A monthly rule starting on the 31st
/// fires on the last day of shorter months and must never roll forward into the
/// following month. Every date is derived from the rule's own start date, which is
/// the anchor: deriving February's date from January's gives the right answer, but
/// deriving March's from February's clamped 28th would drift the whole series to the
/// 28th forever.
public enum RecurringSchedule {

    /// The date of a rule's first occurrence.
    /// - Parameter rule: The rule to schedule.
    /// - Returns: The start date, which is always occurrence zero.
    public static func firstDate(of rule: RecurringRule) -> Date {
        rule.startDate
    }

    /// The date of the occurrence following a given one.
    ///
    /// - Parameters:
    ///   - date: The previous occurrence's date.
    ///   - rule: The rule being scheduled.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The next occurrence's date, or `nil` if the calendar cannot produce one.
    public static func nextDate(
        after date: Date,
        rule: RecurringRule,
        calendar: Calendar = .current
    ) -> Date? {
        switch rule.frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly:
            return nextAnchored(after: date, rule: rule, calendar: calendar, includeMonth: false)
        case .yearly:
            return nextAnchored(after: date, rule: rule, calendar: calendar, includeMonth: true)
        }
    }

    /// The date of the occurrence at a given position in the series.
    ///
    /// - Parameters:
    ///   - index: The zero-based position, where `0` is the start date.
    ///   - rule: The rule being scheduled.
    ///   - calendar: The calendar to compute in.
    /// - Returns: That occurrence's date, or `nil` if the calendar cannot produce it.
    public static func date(
        atIndex index: Int,
        of rule: RecurringRule,
        calendar: Calendar = .current
    ) -> Date? {
        guard index >= 0 else { return nil }
        var current = firstDate(of: rule)
        for _ in 0..<index {
            guard let next = nextDate(after: current, rule: rule, calendar: calendar) else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Finds the next date matching the rule's anchor day, clamping short months.
    ///
    /// Uses `.previousTimePreservingSmallerComponents` so a 31st anchor lands on the
    /// last day of a shorter month rather than spilling into the next one. The
    /// search matches on date components only, so the start date's time of day is
    /// transplanted back afterwards.
    ///
    /// - Parameters:
    ///   - date: The previous occurrence's date.
    ///   - rule: The rule being scheduled.
    ///   - calendar: The calendar to compute in.
    ///   - includeMonth: Whether to anchor the month too, which makes it yearly.
    /// - Returns: The next occurrence's date.
    private static func nextAnchored(
        after date: Date,
        rule: RecurringRule,
        calendar: Calendar,
        includeMonth: Bool
    ) -> Date? {
        let anchor = calendar.dateComponents([.month, .day], from: rule.startDate)
        var matching = DateComponents()
        matching.day = anchor.day
        if includeMonth { matching.month = anchor.month }

        guard let matched = calendar.nextDate(
            after: date,
            matching: matching,
            matchingPolicy: .previousTimePreservingSmallerComponents
        ) else { return nil }

        return restoringTimeOfDay(of: rule.startDate, onto: matched, calendar: calendar)
    }

    /// Copies one date's time of day onto another date's day.
    /// - Parameters:
    ///   - source: The date supplying hour, minute and second.
    ///   - target: The date supplying the calendar day.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The combined date, or `target` if it cannot be built.
    private static func restoringTimeOfDay(
        of source: Date,
        onto target: Date,
        calendar: Calendar
    ) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        ) ?? target
    }
}
