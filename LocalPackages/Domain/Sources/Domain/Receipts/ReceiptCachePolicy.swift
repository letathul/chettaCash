import Foundation

/// A receipt image held in the local cache (§9.5).
public struct CachedReceipt: Identifiable, Equatable, Sendable {
    /// The store's identifier for the file.
    public let fileID: String
    /// How large the cached image is.
    public let sizeBytes: Int
    /// When it was last read, which drives least-recently-used eviction.
    public let lastAccessed: Date
    /// Whether it has reached cloud storage yet.
    public let uploadState: ReceiptUploadState

    /// The receipt's identity.
    public var id: String { fileID }

    /// Creates a cached receipt.
    /// - Parameters:
    ///   - fileID: The store's identifier.
    ///   - sizeBytes: How large the cached image is.
    ///   - lastAccessed: When it was last read.
    ///   - uploadState: Whether it has reached cloud storage.
    public init(
        fileID: String,
        sizeBytes: Int,
        lastAccessed: Date,
        uploadState: ReceiptUploadState
    ) {
        self.fileID = fileID
        self.sizeBytes = sizeBytes
        self.lastAccessed = lastAccessed
        self.uploadState = uploadState
    }
}

/// Decides what may be removed from the receipt cache (§9.5).
///
/// **The safety rule is non-negotiable: a receipt is only evictable once its upload
/// state is `uploaded`.** Both cache clearing and least-recently-used eviction skip
/// anything pending or failed. A photo taken on a plane must never be deletable
/// before it reaches the cloud.
public enum ReceiptCachePolicy {

    /// The default cache cap in megabytes.
    public static let defaultCapMB = 200

    /// The caps the user can choose between. `nil` means unlimited.
    public static let selectableCapsMB: [Int?] = [100, 200, 500, nil]

    /// How many bytes a megabyte cap allows.
    /// - Parameter megabytes: The cap in megabytes, or `nil` for unlimited.
    /// - Returns: The cap in bytes, or `nil` for unlimited.
    public static func capBytes(fromMB megabytes: Int?) -> Int? {
        megabytes.map { $0 * 1_024 * 1_024 }
    }

    /// Whether a receipt may be removed from the cache.
    ///
    /// This is the single gate both eviction paths go through.
    ///
    /// - Parameter receipt: The cached receipt.
    /// - Returns: `true` only once the receipt has reached cloud storage.
    public static func isEvictable(_ receipt: CachedReceipt) -> Bool {
        receipt.uploadState == .uploaded
    }

    /// The total size of everything currently cached.
    /// - Parameter receipts: The cached receipts.
    /// - Returns: The total in bytes.
    public static func totalBytes(_ receipts: [CachedReceipt]) -> Int {
        receipts.reduce(0) { $0 + $1.sizeBytes }
    }

    /// What "Clear cached receipts" should actually remove (§9.5).
    ///
    /// Everything that has uploaded, and nothing that has not.
    ///
    /// - Parameter receipts: The cached receipts.
    /// - Returns: The identifiers to remove.
    public static func clearablePlan(_ receipts: [CachedReceipt]) -> [String] {
        receipts.filter(isEvictable).map(\.fileID)
    }

    /// What least-recently-used eviction should remove to get under the cap.
    ///
    /// Removes the oldest-read evictable receipts first and stops as soon as the
    /// total fits. If the cap cannot be reached without touching pending or failed
    /// uploads, it stops short rather than breaking the safety rule — the cache runs
    /// over its cap until those receipts upload.
    ///
    /// - Parameters:
    ///   - receipts: The cached receipts.
    ///   - capBytes: The cap in bytes, or `nil` for unlimited.
    /// - Returns: The identifiers to remove, oldest-read first.
    public static func evictionPlan(
        _ receipts: [CachedReceipt],
        capBytes: Int?
    ) -> [String] {
        guard let capBytes else { return [] }
        var total = totalBytes(receipts)
        guard total > capBytes else { return [] }

        var removed: [String] = []
        for receipt in receipts.filter(isEvictable).sorted(by: { $0.lastAccessed < $1.lastAccessed }) {
            guard total > capBytes else { break }
            removed.append(receipt.fileID)
            total -= receipt.sizeBytes
        }
        return removed
    }
}
