import UIKit

/// Draws a statement whose amounts sit in their own column, as a real bank's does.
///
/// **This is the layout that cost the importer most of its rows.** When a page's descriptors
/// and amounts are drawn as separate runs, the PDF's text layer stores them in *drawing*
/// order rather than in visual rows — so `PDFPage.string` returns several descriptors run
/// together on one line with their amounts stacked afterwards. A line-oriented reader then
/// sees one row where the page shows several, and drops the rest for having no leading date.
///
/// ``StatementFixture`` cannot catch that, because it draws each row as one whole string and
/// so produces the tidy text layer the reader was written against.
enum ColumnarStatementFixture {

    /// The card's last four digits, as printed.
    static let last4 = "7570"

    /// One printed transaction, drawn as two runs in two columns.
    struct Row {
        /// The transaction date, as printed.
        let date: String
        /// The descriptor, as printed.
        let descriptor: String
        /// The amount, as printed, sign and all.
        let amount: String
        /// The magnitude in cents.
        let cents: Int
        /// Whether the printed amount is a credit.
        let isCredit: Bool
    }

    /// The transactions, taken from the shapes a real Rogers Bank statement printed.
    ///
    /// Two `PRESTO AUTO` fares of exactly 20.00 on one day, and two `MCDONALD'S` of 6.54 on
    /// another, are here deliberately: they are the pairs the old merge key collapsed.
    static let rows = [
        Row(date: "Jul 15", descriptor: "CashBack / Remises Rebate ON",
            amount: "-93.42", cents: 9_342, isCredit: true),
        Row(date: "Jul 16", descriptor: "Dockside Restaurant Gananoque ON",
            amount: "15.25", cents: 1_525, isCredit: false),
        Row(date: "Jul 16", descriptor: "Dockside Restaurant Gananoque ON",
            amount: "9.30", cents: 930, isCredit: false),
        Row(date: "Jul 16", descriptor: "PETRO-CANADA 30584 PORT HOPE ON",
            amount: "71.80", cents: 7_180, isCredit: false),
        Row(date: "Jul 17", descriptor: "MCDONALD'S #23799 SAINT-ZOTIQUE QC",
            amount: "6.54", cents: 654, isCredit: false),
        Row(date: "Jul 17", descriptor: "MCDONALD'S #23799 SAINT-ZOTIQUE QC",
            amount: "6.54", cents: 654, isCredit: false),
        Row(date: "Jul 18", descriptor: "PAYMENT, THANK YOU",
            amount: "-4,201.00", cents: 420_100, isCredit: true),
        Row(date: "Aug 7", descriptor: "PRESTO AUTO/SDKRTCP88C TORONTO ON",
            amount: "20.00", cents: 2_000, isCredit: false),
        Row(date: "Aug 7", descriptor: "PRESTO AUTO/SDMRDFCDRN TORONTO ON",
            amount: "20.00", cents: 2_000, isCredit: false),
        Row(date: "Aug 12", descriptor: "COSTCO WHOLESALE W253 BURLINGTON ON",
            amount: "617.36", cents: 61_736, isCredit: false)
    ]

    /// How many rows should survive the reader, payments included.
    static var expectedRowCount: Int { rows.count }

    /// How many of them are charges rather than credits.
    static var chargeCount: Int { rows.count { !$0.isCredit } }

    /// The statement as a PDF carrying a real, column-drawn text layer.
    /// - Returns: The PDF bytes.
    static func pdfData() -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.black
            ]
            draw("Account Number XXXX XXXX XXXX \(last4)", at: CGPoint(x: 36, y: 40), attributes)
            draw("Transaction Details", at: CGPoint(x: 36, y: 58), attributes)
            draw("Trans Date Description", at: CGPoint(x: 36, y: 76), attributes)
            draw("Amount ($)", at: CGPoint(x: 420, y: 76), attributes)

            // Every descriptor first, then every amount: the drawing order that makes a
            // text layer run the rows together.
            for (index, row) in rows.enumerated() {
                let top = 100 + Double(index) * 16
                draw("\(row.date)  \(row.descriptor)", at: CGPoint(x: 36, y: top), attributes)
            }
            for (index, row) in rows.enumerated() {
                let top = 100 + Double(index) * 16
                draw(row.amount, at: CGPoint(x: 460, y: top), attributes)
            }
        }
    }

    /// Draws one run of text.
    /// - Parameters:
    ///   - text: What to draw.
    ///   - origin: Where to draw it.
    ///   - attributes: How to draw it.
    private static func draw(
        _ text: String,
        at origin: CGPoint,
        _ attributes: [NSAttributedString.Key: Any]
    ) {
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
    }
}
