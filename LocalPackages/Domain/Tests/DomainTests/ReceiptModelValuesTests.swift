import Foundation
import Testing
@testable import Domain

/// Parsing the strings Apple's on-device model returns (§9.7).
@Suite("Receipt values from the on-device model")
struct ReceiptModelValuesTests {

    /// A fixed moment every date test is bounded against.
    private var now: Date {
        Date(timeIntervalSince1970: 1_789_000_000)
    }

    // MARK: - Totals

    @Test("A plain two-decimal total parses to cents")
    func plainTotal() {
        #expect(ReceiptModelValues.cents(from: "42.10") == 4_210)
    }

    @Test("A currency symbol and spaces are ignored")
    func currencySymbol() {
        #expect(ReceiptModelValues.cents(from: "$ 42.10") == 4_210)
        #expect(ReceiptModelValues.cents(from: "CA$1,234.56") == 123_456)
    }

    @Test("One decimal place is read as tenths, not hundredths")
    func oneDecimalPlace() {
        #expect(ReceiptModelValues.cents(from: "42.1") == 4_210)
    }

    @Test("A whole number is read as whole units")
    func wholeNumber() {
        #expect(ReceiptModelValues.cents(from: "42") == 4_200)
    }

    @Test("A comma decimal separator is read as a decimal point")
    func commaDecimal() {
        #expect(ReceiptModelValues.cents(from: "42,10") == 4_210)
    }

    @Test("A comma thousands separator is not read as a decimal point")
    func commaThousands() {
        #expect(ReceiptModelValues.cents(from: "1,234") == 123_400)
    }

    @Test("A negative or unreadable answer is refused rather than guessed at")
    func refusesNonsense() {
        #expect(ReceiptModelValues.cents(from: "-42.10") == nil)
        #expect(ReceiptModelValues.cents(from: "about forty") == nil)
        #expect(ReceiptModelValues.cents(from: "1.2.3") == nil)
        #expect(ReceiptModelValues.cents(from: "42.105") == nil)
        #expect(ReceiptModelValues.cents(from: nil) == nil)
    }

    // MARK: - Dates

    @Test("An ISO date is read positionally, not through the device's locale")
    func isoDateIsUnambiguous() throws {
        // The case behind finding B9: as numerals this is 09/10 or 10/09 depending on
        // where you live. Asking the model for yyyy-MM-dd removes the ambiguity.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt

        let parsed = try #require(
            ReceiptModelValues.date(from: "2026-09-10", now: now, calendar: calendar)
        )
        let components = calendar.dateComponents([.year, .month, .day], from: parsed)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 10)
    }

    @Test("A date in the future is refused")
    func futureDateRefused() {
        #expect(ReceiptModelValues.date(from: "2099-01-01", now: now) == nil)
    }

    @Test("An implausibly old date is refused")
    func ancientDateRefused() {
        #expect(ReceiptModelValues.date(from: "1998-01-01", now: now) == nil)
    }

    @Test("A malformed date is refused rather than guessed at")
    func malformedDateRefused() {
        #expect(ReceiptModelValues.date(from: "10/09/2026", now: now) == nil)
        #expect(ReceiptModelValues.date(from: "2026-13-01", now: now) == nil)
        #expect(ReceiptModelValues.date(from: "26-09-10", now: now) == nil)
        #expect(ReceiptModelValues.date(from: nil, now: now) == nil)
    }

    // MARK: - Combining readers

    @Test("A missing field is taken from the other reader, the rest kept")
    func completesMissingFields() {
        let model = ReceiptScanResult(
            merchant: "Loblaws", date: now, source: .onDeviceModel
        )
        let heuristics = ReceiptScanResult(
            amountCents: 4_210, merchant: "LOBLAWS #1234", source: .textHeuristics
        )

        let combined = model.completed(with: heuristics)

        #expect(combined.amountCents == 4_210, "the model left it blank")
        #expect(combined.merchant == "Loblaws", "the model's own reading stands")
        #expect(combined.date == now)
        #expect(combined.source == .onDeviceModel)
    }

    // MARK: - Time

    @Test("A printed time lands on the parsed date")
    func timeLandsOnTheDate() throws {
        let parsed = try #require(
            ReceiptModelValues.date(from: "2026-09-10", time: "18:42", now: now)
        )

        let parts = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        #expect(parts.hour == 18)
        #expect(parts.minute == 42)
    }

    @Test("Midnight is kept as midnight when the receipt actually printed it")
    func midnightIsKept() throws {
        let parsed = try #require(
            ReceiptModelValues.date(from: "2026-09-10", time: "00:15", now: now)
        )

        let parts = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        #expect(parts.hour == 0)
        #expect(parts.minute == 15)
    }

    @Test("A time the model could not give falls back to midday")
    func noTimeIsMidday() throws {
        let parsed = try #require(ReceiptModelValues.date(from: "2026-09-10", time: nil, now: now))

        let parts = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        #expect(parts.hour == 12, "midday cannot slide into the neighbouring day")
        #expect(parts.minute == 0)
    }

    @Test("An unreadable time costs the time, not the date", arguments: [
        "25:00", "12:60", "6:42 PM", "", "half past six", "1842"
    ])
    func unreadableTimeFallsBackToMidday(text: String) throws {
        let parsed = try #require(ReceiptModelValues.date(from: "2026-09-10", time: text, now: now))

        #expect(Calendar.current.component(.hour, from: parsed) == 12)
    }

    @Test("A time does not rescue a date that is out of range")
    func timeDoesNotDefeatTheDateBounds() {
        #expect(ReceiptModelValues.date(from: "2030-12-25", time: "18:42", now: now) == nil)
    }

    @Test("A reader that found nothing hands over entirely, source included")
    func emptyReaderHandsOver() {
        let heuristics = ReceiptScanResult(amountCents: 4_210, source: .textHeuristics)

        let combined = ReceiptScanResult(source: .onDeviceModel).completed(with: heuristics)

        #expect(combined.amountCents == 4_210)
        #expect(combined.source == .textHeuristics, "the fallback is what actually read it")
    }
}
