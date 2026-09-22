import Foundation
import UIKit
import Vision
import Domain

/// Turns a receipt photo into recognised text (§9.7).
///
/// Abstracted so ``ReceiptScanner`` can be tested without an image or a simulator.
protocol ReceiptRecognizing: Sendable {
    /// Recognises the text on an image.
    /// - Parameter image: The photo to read.
    /// - Returns: The recognised text.
    /// - Throws: A Vision error if recognition fails.
    func recognize(_ image: UIImage) async throws -> RecognizedReceipt
}

/// Reads a receipt with Vision's document recogniser.
///
/// `RecognizeDocumentsRequest` is used rather than plain text recognition because it
/// understands a receipt's *structure* — paragraphs, and the table that the item and
/// price columns form — which keeps a price attached to its line rather than arriving
/// as a loose number somewhere on the page.
struct VisionReceiptRecognizer: ReceiptRecognizing {

    /// Recognises the text on an image.
    /// - Parameter image: The photo to read.
    /// - Returns: The recognised text.
    /// - Throws: ``ReceiptRecognitionError`` if the image cannot be read, or a Vision
    ///   error if recognition fails.
    func recognize(_ image: UIImage) async throws -> RecognizedReceipt {
        guard let cgImage = image.cgImage else { throw ReceiptRecognitionError.unreadableImage }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false

        let observations = try await request.perform(
            on: cgImage, orientation: image.imageOrientation.cgOrientation
        )
        guard let document = observations.first?.document else {
            return RecognizedReceipt(lines: [])
        }
        return RecognizedReceipt(
            lines: document.text.lines.map(Self.line(from:)),
            transcript: document.text.transcript
        )
    }

    /// Converts one recognised line into the Domain's position-carrying form.
    ///
    /// Vision's normalised origin is the *bottom* left, so the line's top edge
    /// becomes a fraction measured from the top by subtracting from one.
    ///
    /// - Parameter observation: The recognised line.
    /// - Returns: The Domain line.
    private static func line(from observation: RecognizedTextObservation) -> RecognizedLine {
        RecognizedLine(
            text: observation.transcript,
            topFraction: max(0, min(1, 1 - Double(observation.topLeft.y)))
        )
    }
}

/// Why a receipt image could not be read.
enum ReceiptRecognitionError: Error {
    /// The image carried no bitmap Vision could work from.
    case unreadableImage
}

private extension UIImage.Orientation {
    /// The Core Graphics orientation Vision expects.
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
