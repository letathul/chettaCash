import UIKit

/// Draws a receipt to photograph, so the pipeline can be tested without a camera.
///
/// A rendered image rather than a checked-in photo: it is deterministic, it is
/// legible at any scale, and the expected values are visible right here in the test
/// rather than in a binary asset nobody can read.
enum ReceiptFixture {

    /// The shop printed at the top.
    static let merchant = "LOBLAWS"
    /// The total, in cents.
    static let totalCents = 2_254
    /// The purchase date, as printed.
    static let printedDate = "2026-03-09"

    /// The receipt's lines, as printed.
    static let lines = [
        merchant,
        "123 Main Street",
        printedDate,
        "",
        "Milk 2L            4.99",
        "Bread              3.49",
        "Coffee            12.99",
        "",
        "SUBTOTAL          21.47",
        "TAX                1.07",
        "TOTAL             22.54"
    ]

    /// Renders the receipt.
    /// - Returns: The image to scan.
    static func image() -> UIImage {
        let size = CGSize(width: 700, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            var top: CGFloat = 40
            for line in lines {
                line.draw(at: CGPoint(x: 40, y: top), withAttributes: attributes)
                top += 52
            }
        }
    }
}
