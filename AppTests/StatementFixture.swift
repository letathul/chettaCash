import UIKit

/// Draws a card statement, so the import pipeline can be tested without a real one.
///
/// Rendered rather than checked in, following ``ReceiptFixture``: it is deterministic, the
/// expected values are readable right here rather than inside a binary, and — the point
/// for a statement — text drawn into a `UIGraphicsPDFRenderer` produces a genuine text
/// layer, which is exactly the fast path ``StatementFileReader`` prefers.
enum StatementFixture {

    /// The card's last four digits, as printed.
    static let last4 = "4417"

    /// One printed transaction line, with what it should parse to.
    struct Row {
        /// The line as printed.
        let printed: String
        /// The descriptor the reader should recover.
        let descriptor: String
        /// The magnitude in cents.
        let cents: Int
    }

    /// The transaction lines, and what each should become.
    static let rows = [
        Row(printed: "03/02  SQ *BLUE BOTTLE 1042        6.75",
            descriptor: "SQ *BLUE BOTTLE 1042", cents: 675),
        Row(printed: "03/03  AMZN Mktp US*2K4TQ39       41.20",
            descriptor: "AMZN Mktp US*2K4TQ39", cents: 4_120),
        Row(printed: "03/05  UNIQLO STORE 0431          89.00",
            descriptor: "UNIQLO STORE 0431", cents: 8_900)
    ]

    /// A credit that is a refund, which should import as income.
    static let refund = "03/07  UNIQLO RETURN             89.00 CR"

    /// A credit that is a payment, which must never be imported (§4.3).
    static let payment = "03/09  PAYMENT - THANK YOU      500.00 CR"

    /// Every line of the statement, in print order.
    static var lines: [String] {
        [
            "CHETTA BANK VISA STATEMENT",
            "Card ending \(last4)",
            "Statement period 03/01 to 03/28",
            ""
        ] + rows.map(\.printed) + [refund, payment]
    }

    /// The statement as a PDF carrying a real text layer.
    /// - Returns: The PDF bytes.
    static func pdfData() -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            for (index, line) in lines.enumerated() {
                let origin = CGPoint(x: 36, y: 48 + Double(index) * 18)
                NSAttributedString(string: line, attributes: attributes).draw(at: origin)
            }
        }
    }

    /// A PDF with no text layer at all, to force the recognition path.
    /// - Returns: The PDF bytes.
    static func imageOnlyPDFData() -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            UIColor.lightGray.setFill()
            context.fill(CGRect(x: 36, y: 48, width: 200, height: 12))
        }
    }
}
