import Foundation
import Domain

/// Reads a receipt with the built-in text heuristics (§9.7).
///
/// The fallback for every case the on-device model cannot cover: an ineligible
/// device, Apple Intelligence turned off, a model still downloading, or a generation
/// that simply failed. It needs nothing but the recognised text.
struct HeuristicReceiptExtractor: ReceiptExtracting {

    /// Extracts what the heuristics can read.
    ///
    /// The category is left to the model: classifying a purchase needs an understanding
    /// of what was bought that no amount of pattern matching supplies. History covers
    /// the common case anyway — see ``ReceiptPrefillBuilder``.
    ///
    /// - Parameters:
    ///   - receipt: The recognised text.
    ///   - context: The clock and the categories the form offers.
    /// - Returns: What could be extracted.
    func extract(
        from receipt: RecognizedReceipt, context: ReceiptScanContext
    ) async -> ReceiptScanResult {
        ReceiptParser.parse(receipt.lines, now: context.now)
    }
}
