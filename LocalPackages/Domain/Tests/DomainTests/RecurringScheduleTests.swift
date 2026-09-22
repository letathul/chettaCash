import Foundation
import Testing
@testable import Domain

/// Phase 6 acceptance criteria for occurrence dates (§4.5).
///
/// Month-end is the case the specification singles out as most likely to be got
/// wrong, so it is tested across several anchors and both leap and common years.
@Suite("Recurring schedule")
struct RecurringScheduleTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    ///   - hour: The hour.
    ///   - minute: The minute.
    /// - Returns: That instant.
    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 30
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )) ?? .now
    }

    /// Builds a rule.
    /// - Parameters:
    ///   - frequency: How often it fires.
    ///   - start: The first occurrence.
    /// - Returns: The rule.
    private func rule(_ frequency: RecurringFrequency, start: Date) -> RecurringRule {
        RecurringRule(name: "Rent", amountCents: 100_000, frequency: frequency, startDate: start)
    }

    /// Collects the first several occurrence dates of a rule.
    /// - Parameters:
    ///   - rule: The rule to walk.
    ///   - count: How many dates to collect.
    /// - Returns: The dates, in order.
    private func sequence(of rule: RecurringRule, count: Int) -> [Date] {
        (0..<count).compactMap {
            RecurringSchedule.date(atIndex: $0, of: rule, calendar: calendar)
        }
    }

    @Test("A monthly rule starting on the 31st fires on 28 February and does not roll forward")
    func monthEndClampsToFebruary() {
        let monthly = rule(.monthly, start: date(2026, 1, 31))

        let dates = sequence(of: monthly, count: 4)

        #expect(dates == [
            date(2026, 1, 31),
            date(2026, 2, 28),
            date(2026, 3, 31),
            date(2026, 4, 30)
        ])
    }

    @Test("A clamped month does not drag the rest of the series onto the 28th")
    func clampingDoesNotDrift() {
        let monthly = rule(.monthly, start: date(2026, 1, 31))

        let dates = sequence(of: monthly, count: 13)

        #expect(dates.last == date(2027, 1, 31), "the anchor is the start date, not last month")
        #expect(dates[5] == date(2026, 6, 30))
        #expect(dates[6] == date(2026, 7, 31))
    }

    @Test("A 31st anchor clamps in a leap February too")
    func leapFebruaryClamps() {
        let monthly = rule(.monthly, start: date(2028, 1, 31))
        #expect(sequence(of: monthly, count: 2).last == date(2028, 2, 29))
    }

    @Test("A 30th anchor also clamps in February", arguments: [29, 30])
    func otherShortMonthAnchors(day: Int) {
        let monthly = rule(.monthly, start: date(2026, 1, day))
        #expect(sequence(of: monthly, count: 2).last == date(2026, 2, 28))
    }

    @Test("An ordinary anchor is untouched")
    func ordinaryAnchor() {
        let monthly = rule(.monthly, start: date(2026, 1, 15))
        #expect(sequence(of: monthly, count: 3) == [
            date(2026, 1, 15), date(2026, 2, 15), date(2026, 3, 15)
        ])
    }

    @Test("Occurrences keep the start date's time of day")
    func preservesTimeOfDay() {
        let monthly = rule(.monthly, start: date(2026, 1, 31, 18, 45))
        let dates = sequence(of: monthly, count: 3)

        for occurrence in dates {
            let time = calendar.dateComponents([.hour, .minute], from: occurrence)
            #expect(time.hour == 18)
            #expect(time.minute == 45)
        }
    }

    @Test("A yearly rule starting on 29 February clamps in common years")
    func yearlyLeapDay() {
        let yearly = rule(.yearly, start: date(2028, 2, 29))

        let dates = sequence(of: yearly, count: 3)

        #expect(dates == [date(2028, 2, 29), date(2029, 2, 28), date(2030, 2, 28)])
    }

    @Test("Weekly and biweekly advance by fixed day counts")
    func weeklyAndBiweekly() {
        #expect(sequence(of: rule(.weekly, start: date(2026, 1, 29)), count: 3) == [
            date(2026, 1, 29), date(2026, 2, 5), date(2026, 2, 12)
        ])
        #expect(sequence(of: rule(.biweekly, start: date(2026, 1, 29)), count: 3) == [
            date(2026, 1, 29), date(2026, 2, 12), date(2026, 2, 26)
        ])
    }

    @Test("Walking forward one at a time matches indexing directly")
    func nextDateMatchesIndexing() {
        let monthly = rule(.monthly, start: date(2026, 1, 31))
        var walked = [RecurringSchedule.firstDate(of: monthly)]
        for _ in 0..<5 {
            guard let last = walked.last,
                  let next = RecurringSchedule.nextDate(
                      after: last, rule: monthly, calendar: calendar
                  ) else { break }
            walked.append(next)
        }

        #expect(walked == sequence(of: monthly, count: 6))
    }
}
