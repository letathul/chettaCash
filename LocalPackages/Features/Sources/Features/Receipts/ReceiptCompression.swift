import Foundation
import UIKit

/// Reducing a receipt photo to the size it is stored at (§9.5, §9.7).
///
/// Public because two very different callers need the same answer: the in-app scanner,
/// and the Add Expense intent, which attaches files handed to it by the Shortcuts app.
/// A second implementation would drift, and the one that drifted would be the one
/// filling the receipt cache with originals.
public enum ReceiptCompression {

    /// The longest edge a stored photo keeps.
    public static let longEdge: CGFloat = 1_600

    /// Reduces a photo to the stored size.
    ///
    /// Images shorter than ``longEdge`` are left alone rather than scaled up, which
    /// would add bytes without adding detail.
    ///
    /// - Parameter image: The photo to reduce.
    /// - Returns: The reduced photo.
    public nonisolated static func compressed(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longEdge, longest > 0 else { return image }
        let scale = longEdge / longest
        let target = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// The bytes to store for a photo.
    /// - Parameter image: The photo to encode.
    /// - Returns: JPEG bytes, or `nil` if it cannot be encoded.
    public nonisolated static func storableData(for image: UIImage) -> Data? {
        compressed(image).jpegData(compressionQuality: 0.7)
    }

    /// The bytes to store for a photo, encoded off the main actor.
    ///
    /// Reducing and JPEG-encoding a 1,600px photo is tens of milliseconds of real
    /// work, and doing it on the main actor stalls the scan's own progress animation —
    /// the one place a hitch is most visible, because the user is watching it.
    ///
    /// - Parameter image: The photo to encode.
    /// - Returns: JPEG bytes, or `nil` if it cannot be encoded.
    public nonisolated static func storableDataOffMainActor(for image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { storableData(for: image) }.value
    }
}
