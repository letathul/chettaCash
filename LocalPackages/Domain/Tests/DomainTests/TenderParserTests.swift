import Foundation
import Testing
@testable import Domain

/// Reading the card off a receipt's payment line (§9.7).
///
/// The interesting cases here are the refusals. A receipt is dense with four-digit
/// numbers that are not card digits — authorisation codes, store numbers, times, years —
/// and taking one of those would auto-select the wrong account and post real money
/// against the wrong balance.
@Suite("Receipt tender parsing")
struct TenderParserTests {

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

    // MARK: - Digits

    @Test("A masked card number gives up its last four digits")
    func readsMaskedNumber() {
        let tender = TenderParser.parse(lines(["VISA ************4821"]))

        #expect(tender.last4 == "4821")
        #expect(tender.network == .visa)
    }

    @Test("Masking with X or dots reads the same as with asterisks", arguments: [
        "XXXX XXXX XXXX 4821",
        "•••• •••• •••• 4821",
        "CARD ####4821",
        "ACCT xxxx-4821"
    ])
    func readsOtherMasks(text: String) {
        #expect(TenderParser.parse(lines([text])).last4 == "4821")
    }

    @Test("A worded card number is read", arguments: [
        "Card ending in 4821",
        "Visa ending 4821",
        "Ends with 4821",
        "Last 4: 4821"
    ])
    func readsWordedNumber(text: String) {
        #expect(TenderParser.parse(lines([text])).last4 == "4821")
    }

    @Test("A bare number is read when the line says it is a card")
    func readsBareNumberOnCardLine() {
        #expect(TenderParser.parse(lines(["DEBIT CARD 4821"])).last4 == "4821")
    }

    // MARK: - Refusals

    @Test("An authorisation code is not mistaken for the card")
    func rejectsAuthCode() {
        let tender = TenderParser.parse(lines([
            "LOBLAWS", "TOTAL 42.10", "AUTH 4821", "REF 9931"
        ]))

        #expect(tender.last4 == nil, "no line says these digits are a card")
    }

    @Test("A masked number wins even on a line that also names an authorisation")
    func maskingOverrulesTheIdentifierWords() {
        let tender = TenderParser.parse(lines(["AUTH 003912 VISA ****4821"]))

        #expect(tender.last4 == "4821")
    }

    @Test("An amount on the card line is never read as the digits")
    func rejectsAmount() {
        let tender = TenderParser.parse(lines(["VISA CARD 48.21"]))

        #expect(tender.last4 == nil, "48.21 is money, not a card number")
        #expect(tender.network == .visa)
    }

    @Test("Digits inside a longer number are not read")
    func rejectsEmbeddedDigits() {
        #expect(TenderParser.parse(lines(["CARD 123456789012"])).last4 == nil)
    }

    @Test("A bare number on a line that says nothing about a card is refused")
    func rejectsBareNumberWithoutContext() {
        #expect(TenderParser.parse(lines(["LOBLAWS", "4821 BLOOR ST W"])).last4 == nil)
    }

    // MARK: - Network

    @Test("Each network is recognised by name", arguments: [
        ("VISA DEBIT", CardNetwork.visa),
        ("MASTERCARD", CardNetwork.mastercard),
        ("Master Card", CardNetwork.mastercard),
        ("AMERICAN EXPRESS", CardNetwork.amex),
        ("AMEX", CardNetwork.amex),
        ("DISCOVER", CardNetwork.discover),
        ("INTERAC", CardNetwork.interac),
        ("UnionPay", CardNetwork.unionpay)
    ])
    func readsNetwork(text: String, expected: CardNetwork) {
        #expect(TenderParser.parse(lines([text])).network == expected)
    }

    @Test("A network printed with no digits is still reported")
    func networkWithoutDigits() {
        let tender = TenderParser.parse(lines(["LOBLAWS", "TOTAL 42.10", "PAID BY VISA"]))

        #expect(tender.network == .visa)
        #expect(tender.last4 == nil)
        #expect(!tender.isEmpty)
    }

    @Test("A receipt paid in cash carries no tender at all")
    func cashReceiptIsEmpty() {
        let tender = TenderParser.parse(lines(["LOBLAWS", "TOTAL 42.10", "CASH 50.00"]))

        #expect(tender.isEmpty)
    }
}
