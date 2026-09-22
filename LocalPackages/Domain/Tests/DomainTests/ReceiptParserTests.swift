import Foundation
import Testing
@testable import Domain

/// Phase 13 coverage for receipt OCR parsing (§9.7).
///
/// Scope is amount, merchant and date only — there is no line-item extraction.
@Suite("Receipt parsing")
struct ReceiptParserTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// The moment scans are evaluated against.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)) ?? .now
    }

    /// Builds recognised lines, spaced evenly down the page.
    /// - Parameter texts: The lines, top to bottom.
    /// - Returns: The recognised lines.
    private func lines(_ texts: [String]) -> [RecognizedLine] {
        texts.enumerated().map { index, text in
            RecognizedLine(
                text: text,
                topFraction: texts.count <= 1 ? 0 : Double(index) / Double(texts.count - 1)
            )
        }
    }

    // MARK: - Amount

    @Test("The total is taken from the line naming it")
    func totalFromKeyword() {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET", "Bananas 3.49", "Coffee 12.99",
            "Subtotal 16.48", "Tax 1.32", "Total 17.80"
        ]), now: now)

        #expect(result.amountCents == 1_780)
    }

    @Test("Subtotal is never mistaken for the total")
    func subtotalIsIgnored() {
        let result = ReceiptParser.parse(lines([
            "SHOP", "Subtotal 99.99", "Total 12.00"
        ]), now: now)

        #expect(result.amountCents == 1_200)
    }

    @Test("Without a keyword, the largest plausible amount is used")
    func fallsBackToLargestAmount() {
        let result = ReceiptParser.parse(lines([
            "CORNER STORE", "Item A 4.50", "Item B 11.25"
        ]), now: now)

        #expect(result.amountCents == 1_125)
    }

    @Test("Amounts need two decimal places to count", arguments: [
        ("Total 17.80", 1_780),
        ("Total $1,234.56", 123_456),
        ("Qty 2 Total 9.99", 999)
    ])
    func amountFormats(text: String, expected: Int) {
        #expect(ReceiptParser.amounts(in: text).max() == expected)
    }

    @Test("Bare integers and long numbers are not amounts", arguments: [
        "Qty 2", "Card ending 4242", "Ref 1234567", "Version 1.2.3"
    ])
    func nonAmountsAreIgnored(text: String) {
        #expect(ReceiptParser.amounts(in: text).isEmpty)
    }

    @Test("A tip line does not become the total")
    func tipIsExcluded() {
        let result = ReceiptParser.parse(lines([
            "CAFE", "Total 20.00", "Tip 40.00"
        ]), now: now)

        #expect(result.amountCents == 2_000)
    }

    // MARK: - Merchant

    @Test("The merchant comes from the topmost text block")
    func merchantFromTop() {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET", "123 Main Street", "Total 17.80"
        ]), now: now)

        #expect(result.merchant == "WHOLE FOODS MARKET")
    }

    @Test("A numeric top line is skipped in favour of a real name")
    func numericTopLineIsSkipped() {
        let result = ReceiptParser.parse(lines([
            "0123456789", "BLUE BOTTLE", "x", "y", "Total 5.00"
        ]), now: now)

        #expect(result.merchant == "BLUE BOTTLE")
    }

    @Test("A merchant far down the page is not used")
    func merchantMustBeNearTheTop() {
        let result = ReceiptParser.parse([
            RecognizedLine(text: "1234", topFraction: 0.0),
            RecognizedLine(text: "THANK YOU FOR SHOPPING", topFraction: 0.9)
        ], now: now)

        #expect(result.merchant == nil)
    }

    // MARK: - Date

    @Test("An unambiguous printed date is detected")
    func dateIsDetected() throws {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS", "Sep 10, 2026", "Total 17.80"
        ]), now: now)

        let date = try #require(result.date)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 10)
    }

    @Test("A numeric date is read in the device's locale order, not the receipt's")
    func numericDatesAreLocaleDependent() {
        // `09/10/2026` means 10 September on a US receipt and 9 October on a UK one,
        // and NSDataDetector resolves it against the *device's* locale. Pinned here
        // because it is a real limitation of scanning, not something the parser can
        // decide: the extracted date is a pre-fill the user can correct (§9.7).
        let result = ReceiptParser.parse(lines([
            "SHOP", "09/10/2026", "Total 5.00"
        ]), now: now)

        // Whatever it resolves to, an implausible reading is dropped rather than
        // pre-filling a wrong date.
        if let date = result.date {
            #expect(date <= now.addingTimeInterval(86_400))
        }
    }

    @Test("A date in the future is rejected as implausible")
    func futureDateIsRejected() {
        let result = ReceiptParser.parse(lines([
            "SHOP", "12/25/2030", "Total 5.00"
        ]), now: now)

        #expect(result.date == nil)
    }

    // MARK: - Location

    @Test("The address under the shop's name is read")
    func readsAddress() {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET",
            "120 Bloor St W",
            "Toronto ON M5S 1M8",
            "Bananas 3.49",
            "TOTAL 12.99"
        ]), now: now)

        let location = result.location ?? ""
        #expect(location.contains("120 Bloor St W"))
        #expect(location.contains("Toronto ON M5S 1M8"))
    }

    @Test("The merchant line is not repeated as the address")
    func addressExcludesTheMerchant() {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET", "120 Bloor St W", "TOTAL 12.99"
        ]), now: now)

        #expect(result.location == "120 Bloor St W")
    }

    @Test("A phone number or website is not read as an address", arguments: [
        "Tel: 416-555-0134",
        "www.wholefoods.com",
        "orders@wholefoods.com"
    ])
    func addressExcludesContactDetails(text: String) {
        #expect(!ReceiptParser.isPlausibleLocation(text))
    }

    @Test("A line carrying money is not read as an address")
    func addressExcludesAmounts() {
        #expect(!ReceiptParser.isPlausibleLocation("Bananas 3.49"))
    }

    @Test("A receipt printing no address reads none")
    func noAddressReadsNone() {
        let result = ReceiptParser.parse(lines(["WHOLE FOODS MARKET", "TOTAL 12.99"]), now: now)

        #expect(result.location == nil)
    }

    // MARK: - Time

    @Test("A 24-hour time is read", arguments: [
        ("18:42", 18, 42),
        ("09:05", 9, 5),
        ("23:59", 23, 59),
        ("18:42:07", 18, 42)
    ])
    func readsTwentyFourHourTime(text: String, hour: Int, minute: Int) {
        let found = ReceiptParser.time(inText: text)

        #expect(found?.hour == hour)
        #expect(found?.minute == minute)
    }

    @Test("A 12-hour time is converted", arguments: [
        ("6:42 PM", 18, 42),
        ("6:42 AM", 6, 42),
        ("12:30 AM", 0, 30),
        ("12:30 PM", 12, 30)
    ])
    func convertsTwelveHourTime(text: String, hour: Int, minute: Int) {
        let found = ReceiptParser.time(inText: text)

        #expect(found?.hour == hour)
        #expect(found?.minute == minute)
    }

    @Test("An impossible time is refused", arguments: ["25:00", "12:60", "1234"])
    func refusesImpossibleTime(text: String) {
        #expect(ReceiptParser.time(inText: text) == nil)
    }

    @Test("A printed time lands on the scanned date")
    func timeLandsOnTheDate() throws {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET", "Sep 10, 2026", "6:42 PM", "TOTAL 12.99"
        ]), now: now)

        let date = try #require(result.date)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        #expect(parts.hour == 18)
        #expect(parts.minute == 42)
    }

    @Test("A receipt with no time is pinned to midday, not midnight")
    func noTimeIsMidday() throws {
        let result = ReceiptParser.parse(lines([
            "WHOLE FOODS MARKET", "Sep 10, 2026", "TOTAL 12.99"
        ]), now: now)

        let date = try #require(result.date)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        #expect(parts.hour == 12, "midnight would read as the wrong day in another time zone")
        #expect(parts.minute == 0)
    }

    // MARK: - Failure

    @Test("A scan that reads nothing usable returns an empty pre-fill")
    func failedScanIsEmpty() {
        let result = ReceiptParser.parse(lines(["///", "***"]), now: now)

        #expect(result.isEmpty)
        #expect(result.amountCents == nil)
        #expect(result.merchant == nil)
        #expect(result.location == nil)
    }

    @Test("No recognised lines at all is an empty result, not a crash")
    func noLinesIsEmpty() {
        #expect(ReceiptParser.parse([], now: now).isEmpty)
    }

    @Test("A partial read still pre-fills what it found")
    func partialReadIsUseful() {
        let result = ReceiptParser.parse(lines([
            "BLUE BOTTLE COFFEE", "Total 5.75"
        ]), now: now)

        #expect(result.merchant == "BLUE BOTTLE COFFEE")
        #expect(result.amountCents == 575)
        #expect(result.date == nil)
        #expect(result.isEmpty == false)
    }
}
