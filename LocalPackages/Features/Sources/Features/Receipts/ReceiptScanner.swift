import Foundation
import UIKit
import Domain

/// Runs a receipt photo through recognition and extraction (§9.7).
///
/// The only receipt type the UI touches. The order is deliberate: Vision reads the
/// page, the on-device model interprets it, and the heuristics fill whatever the
/// model left blank — or replace it entirely when the model could not run.
///
/// A scan never fails loudly. The worst outcome is an empty result, which leaves the
/// form exactly as the user would have found it by typing.
@MainActor
@Observable
final class ReceiptScanner {
    /// How far along the current scan is, for the progress row (§9.7).
    ///
    /// Owned here rather than by the view because only the scanner knows which step it
    /// is actually on. Returns to ``ReceiptScanPhase/idle`` on every exit path.
    private(set) var phase: ReceiptScanPhase = .idle

    /// Reads text off the image.
    private let recognizer: any ReceiptRecognizing
    /// The preferred reader.
    private let primary: any ReceiptExtracting
    /// The reader that covers what the preferred one cannot.
    private let fallback: any ReceiptExtracting

    /// The long edge a photo is reduced to before recognition (§9.7).
    ///
    /// Large enough for Vision to resolve small print, small enough that the stored
    /// image stays within the cache budget §9.5 sets.
    ///
    /// `nonisolated` so the off-main-actor compression can read it.

    /// Creates a scanner.
    /// - Parameters:
    ///   - recognizer: Reads text off the image.
    ///   - primary: The preferred reader.
    ///   - fallback: The reader that covers what the preferred one cannot.
    nonisolated init(
        recognizer: any ReceiptRecognizing = VisionReceiptRecognizer(),
        primary: any ReceiptExtracting = FoundationModelsReceiptExtractor(),
        fallback: any ReceiptExtracting = HeuristicReceiptExtractor()
    ) {
        self.recognizer = recognizer
        self.primary = primary
        self.fallback = fallback
    }

    /// Scans a photo.
    /// - Parameters:
    ///   - image: The photo to read.
    ///   - context: The clock and the categories the form offers.
    /// - Returns: What the receipt said, empty when nothing legible was found.
    func scan(
        _ image: UIImage, context: ReceiptScanContext = ReceiptScanContext()
    ) async -> ReceiptScanResult {
        phase = .reading
        defer { phase = .idle }

        guard let receipt = try? await recognizer.recognize(image), !receipt.isEmpty else {
            return ReceiptScanResult()
        }

        phase = .understanding
        let led = await primary.extract(from: receipt, context: context)
        let backup = await fallback.extract(from: receipt, context: context)
        var result = led.completed(with: backup)

        phase = .matching
        // The card's details are read here rather than by either extractor, and are not
        // merged: a masked number is an exact pattern, so there is nothing for the model
        // to be better at and no reason to let it overrule the match.
        let tender = TenderParser.parse(receipt.lines)
        result.tender = tender.isEmpty ? nil : tender
        return result
    }

    /// Reduces a photo to the stored size (§9.7).
    /// - Parameter image: The photo to reduce.
    /// - Returns: The reduced photo.
    nonisolated static func compressed(_ image: UIImage) -> UIImage {
        ReceiptCompression.compressed(image)
    }

    /// The bytes to store for a photo (§9.5).
    /// - Parameter image: The photo to encode.
    /// - Returns: JPEG bytes, or `nil` if it cannot be encoded.
    nonisolated static func storableData(for image: UIImage) -> Data? {
        ReceiptCompression.storableData(for: image)
    }

    /// The bytes to store for a photo, encoded off the main actor (§9.5).
    /// - Parameter image: The photo to encode.
    /// - Returns: JPEG bytes, or `nil` if it cannot be encoded.
    nonisolated static func storableDataOffMainActor(for image: UIImage) async -> Data? {
        await ReceiptCompression.storableDataOffMainActor(for: image)
    }
}
