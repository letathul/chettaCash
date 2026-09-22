import Foundation
import Domain

/// Receipts that run to more than one page (§9.3).
///
/// Split from ``ReceiptStorageCoordinator`` to keep each file within the 300-line
/// limit.
extension ReceiptStorageCoordinator {

    /// Attaches an already-compressed receipt that runs to several pages (§9.3).
    ///
    /// A transaction stores one receipt identifier, because one till receipt covers
    /// however many products a purchase contained (§7.8). A receipt too long for one
    /// photograph is still *one* receipt, so the extra pages are filed as siblings of
    /// the first and found again by shared prefix — no second column, no second row.
    ///
    /// - Parameters:
    ///   - pages: The compressed image bytes, in reading order.
    ///   - transaction: The transaction they belong to.
    /// - Returns: The identifiers assigned, page one first.
    @discardableResult
    public func capturePages(
        _ pages: [Data],
        for transaction: Domain.Transaction
    ) -> [String] {
        guard !pages.isEmpty else { return [] }
        let base = ReceiptNaming.fileID(
            date: transaction.date,
            merchant: transaction.merchant,
            amountCents: transaction.amountCents,
            ownerID: transaction.id
        )
        return pages.enumerated().map { index, data in
            enqueue(data, as: ReceiptNaming.pageFileID(baseFileID: base, page: index + 1))
        }
    }

    /// Every stored page of a receipt, page one first.
    ///
    /// The cache is in memory only, so a receipt attached in an earlier session has to
    /// be rediscovered from the store's own folder listing.
    ///
    /// - Parameter fileID: Page one's identifier.
    /// - Returns: The identifiers of every page, page one first.
    public func pages(for fileID: String) async -> [String] {
        var found = Set(cache.keys.filter { ReceiptNaming.isPage($0, ofBaseFileID: fileID) })
        let components = fileID.split(separator: "/")
        if components.count >= 3 {
            let path = ReceiptPath(year: String(components[1]), month: String(components[2]))
            let remote = (try? await store.list(path: path)) ?? []
            for file in remote where ReceiptNaming.isPage(file.fileID, ofBaseFileID: fileID) {
                found.insert(file.fileID)
            }
        }
        found.insert(fileID)
        // Ordered by page number rather than by text: "-p2" sorts ahead of ".jpg", so
        // sorting these as strings would put page two first.
        return found
            .compactMap { id in
                ReceiptNaming.pageNumber(of: id, ofBaseFileID: fileID).map { (id, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Deletes a receipt from the cache and the store.
    ///
    /// Used when the user removes an attachment. Unlike eviction this is deliberate, so
    /// it applies whatever the upload state: the user asked for the image to be gone.
    ///
    /// - Parameter fileID: The receipt's identifier.
    public func discard(fileID: String) async {
        // Every page, not just the first: dropping only page one would leave the rest
        // in the store forever, reachable by nothing and counted against no cap.
        for page in await pages(for: fileID) {
            cache[page] = nil
            cachedData[page] = nil
            try? await store.delete(fileID: page)
        }
    }
}
