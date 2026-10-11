import Foundation
import Testing
@testable import Features

/// The Dashboard's two pure presentation helpers (§7.1).
///
/// Both are deliberately `static` and injectable so they can be pinned here rather
/// than only observed on screen.
@Suite("Dashboard presentation")
struct DashboardPresentationTests {

    /// A UTC calendar, so the greeting never depends on the runner's zone.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC instant at a given hour on a fixed day.
    /// - Parameter hour: The hour of day.
    /// - Returns: That instant.
    private func at(hour: Int) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 22, hour: hour)
        ) ?? .now
    }

    @Test("The greeting follows the time of day", arguments: [
        (0, "Good morning"), (9, "Good morning"), (11, "Good morning"),
        (12, "Good afternoon"), (17, "Good afternoon"),
        (18, "Good evening"), (23, "Good evening")
    ])
    func greetingFollowsTheHour(hour: Int, expected: String) {
        let greeting = DashboardView.greeting(now: at(hour: hour), calendar: calendar)

        #expect(greeting == expected)
    }

    @Test("A row's date reads as a relative day before falling back to a date")
    func relativeDayReadsNaturally() {
        let now = at(hour: 12)
        let days = { (back: Int) in
            self.calendar.date(byAdding: .day, value: -back, to: now) ?? now
        }

        #expect(row(days(0), now) == "Today")
        #expect(row(days(1), now) == "Yesterday")
        #expect(row(days(3), now) == "Sat", "three days back is still named by weekday")
        #expect(row(days(30), now).contains("Aug"), "beyond a week it reads as a date")
    }

    /// Renders a row's subtitle for a date.
    /// - Parameters:
    ///   - date: The transaction's date.
    ///   - now: The moment to measure against.
    /// - Returns: The subtitle.
    private func row(_ date: Date, _ now: Date) -> String {
        DashboardViewModel.relativeDay(date, now: now, calendar: calendar)
    }
}
