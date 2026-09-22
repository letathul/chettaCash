import Foundation
import Testing
@testable import Domain

/// Settling whether `03/09` is March or September, once per file (§9.7).
@Suite("Statement date order")
struct StatementDateOrderTests {

    /// A fixed moment the dates resolve against.
    private let now = Date(timeIntervalSince1970: 1_787_000_000)

    @Test("One unambiguous date settles the whole file")
    func oneUnambiguousDateSettlesIt() {
        // 25 cannot be a month, so this file writes the day first — and so its 03/09 is
        // the third of September, not the ninth of March.
        #expect(StatementDateOrderReader.infer(from: ["03/09/2026", "25/12/2026"]) == .dayFirst)
        #expect(StatementDateOrderReader.infer(from: ["03/09/2026", "12/25/2026"]) == .monthFirst)
    }

    @Test("With nothing to go on the North American convention stands")
    func defaultsToMonthFirst() {
        #expect(StatementDateOrderReader.infer(from: ["03/09/2026", "01/02/2026"]) == .monthFirst)
        #expect(StatementDateOrderReader.infer(from: []) == .monthFirst)
    }

    @Test("Text that is not a date at all is passed over")
    func ignoresNonDates() {
        let order = StatementDateOrderReader.infer(
            from: ["Reference 99/99/9999", "not a date", "25/12/2026"]
        )

        #expect(order == .dayFirst)
    }

    @Test("A day-first file reads its ambiguous dates day-first")
    func dayFirstFileReadsDayFirst() {
        let context = StatementParseContext(now: now, dateOrder: .dayFirst)

        let date = StatementTextParser.date(from: "03/09/2026", context: context)

        let month = Calendar.current.component(.month, from: date ?? .distantPast)
        #expect(month == 9, "the third of September")
    }

    @Test("A month-first file reads the same text month-first")
    func monthFirstFileReadsMonthFirst() {
        let context = StatementParseContext(now: now, dateOrder: .monthFirst)

        let date = StatementTextParser.date(from: "03/09/2026", context: context)

        let month = Calendar.current.component(.month, from: date ?? .distantPast)
        #expect(month == 3, "the ninth of March")
    }

    @Test("A number above twelve is a day whatever the file's order says")
    func aDayIsADay() {
        let monthFirst = StatementParseContext(now: now, dateOrder: .monthFirst)

        let date = StatementTextParser.date(from: "25/12/2026", context: monthFirst)

        let calendar = Calendar.current
        #expect(calendar.component(.day, from: date ?? .distantPast) == 25)
        #expect(calendar.component(.month, from: date ?? .distantPast) == 12)
    }

    @Test("A whole export of day-first dates reads as one month, not two")
    func exportReadsConsistently() {
        let csv = """
            Date,Description,Amount
            03/09/2026,COSTCO,-42.10
            25/09/2026,SHELL,-77.24
            """
        var columns = CSVStatementColumns(descriptor: "Description", amount: .single("Amount"))
        columns.transactionDate = "Date"

        let document = CSVStatementParser.document(
            csv: csv, columns: columns, context: StatementParseContext(now: now)
        )

        let months = document.rows.map { Calendar.current.component(.month, from: $0.date) }
        #expect(months == [9, 9], "25/09 proves the file is day-first, so 03/09 is September")
    }
}
