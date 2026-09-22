import Foundation
import Domain

/// Drives receipt uploads, the local cache and backups (§9.4, §9.5, §9.6).
///
/// The upload queue is the local cache itself: a captured receipt is written to the
/// cache immediately and marked `pending`, so it is fully usable offline, and the
/// flush moves anything pending or failed into the store when a connection allows.
@MainActor
public final class ReceiptStorageCoordinator {
    /// Where receipts and backups are stored.
    ///
    /// Internal rather than private so the paging extension can reach it from its own
    /// file; nothing outside the module can see it either way.
    let store: any ReceiptStore
    /// Supplies the transactions whose receipts are tracked.
    private let transactions: any TransactionRepository
    /// Writes and reads backup archives.
    private let backups: any BackupWriting
    /// User preferences, for the cache cap and backup interval.
    private let settings: AppSettings

    /// Receipt images held locally, keyed by file identifier.
    var cache: [String: CachedReceipt] = [:]
    /// Bytes held locally, keyed by file identifier.
    var cachedData: [String: Data] = [:]
    /// When the last successful sync finished.
    private var lastSynced: Date?
    /// The most recent failure, if any.
    private var lastError: String?

    /// Creates the coordinator.
    /// - Parameters:
    ///   - store: Where receipts and backups are stored.
    ///   - transactions: Supplies transactions.
    ///   - backups: Writes and reads backup archives.
    ///   - settings: The shared preferences object.
    public init(
        store: any ReceiptStore,
        transactions: any TransactionRepository,
        backups: any BackupWriting,
        settings: AppSettings
    ) {
        self.store = store
        self.transactions = transactions
        self.backups = backups
        self.settings = settings
    }

    /// Captures a receipt, caching it immediately and queuing its upload (§9.5).
    ///
    /// The receipt is usable straight away even with no connection; the upload
    /// happens on the next flush.
    ///
    /// - Parameters:
    ///   - data: The compressed image bytes.
    ///   - transaction: The transaction it belongs to.
    /// - Returns: The file identifier assigned.
    @discardableResult
    public func capture(_ data: Data, for transaction: Domain.Transaction) -> String {
        enqueue(data, as: ReceiptNaming.fileID(
            date: transaction.date,
            merchant: transaction.merchant,
            amountCents: transaction.amountCents,
            ownerID: transaction.id
        ))
    }

    /// Writes bytes into the local cache and queues their upload.
    /// - Parameters:
    ///   - data: The compressed image bytes.
    ///   - fileID: The identifier to file them under.
    /// - Returns: The identifier, for chaining.
    @discardableResult
    func enqueue(_ data: Data, as fileID: String) -> String {
        cachedData[fileID] = data
        cache[fileID] = CachedReceipt(
            fileID: fileID, sizeBytes: data.count, lastAccessed: .now, uploadState: .pending
        )
        return fileID
    }

    /// Reads a stored receipt back (§9.5).
    ///
    /// The cache is in memory only, so it is empty after every launch: anything the
    /// user attached in an earlier session comes back from the store. A successful
    /// download repopulates the cache and refreshes `lastAccessed`, which is what keeps
    /// the LRU eviction order meaningful.
    ///
    /// - Parameter fileID: The receipt's identifier.
    /// - Returns: The image bytes, or `nil` if the store cannot produce them.
    public func image(for fileID: String) async -> Data? {
        if let cached = cachedData[fileID] {
            touch(fileID, sizeBytes: cached.count, uploadState: cache[fileID]?.uploadState)
            return cached
        }
        guard let data = try? await store.download(fileID: fileID) else { return nil }
        cachedData[fileID] = data
        touch(fileID, sizeBytes: data.count, uploadState: .uploaded)
        await evictIfOverCap()
        return data
    }

    /// Records a read against a cached receipt.
    /// - Parameters:
    ///   - fileID: The receipt's identifier.
    ///   - sizeBytes: How large it is.
    ///   - uploadState: Its upload state, defaulting to uploaded for a downloaded file.
    private func touch(_ fileID: String, sizeBytes: Int, uploadState: ReceiptUploadState?) {
        cache[fileID] = CachedReceipt(
            fileID: fileID,
            sizeBytes: sizeBytes,
            lastAccessed: .now,
            uploadState: uploadState ?? .uploaded
        )
    }

    /// Uploads everything still pending or failed (§9.5, §9.6).
    public func flushUploads() async {
        let waiting = cache.values.filter { $0.uploadState != .uploaded }
        for receipt in waiting {
            guard let data = cachedData[receipt.fileID] else { continue }
            let components = receipt.fileID.split(separator: "/")
            guard components.count >= 3 else { continue }
            let path = ReceiptPath(year: String(components[1]), month: String(components[2]))
            do {
                _ = try await store.upload(
                    data, named: String(components.last ?? ""), to: path
                )
                mark(receipt.fileID, as: .uploaded)
                lastError = nil
            } catch {
                mark(receipt.fileID, as: .failed)
                lastError = "Some receipts could not be uploaded."
            }
        }
        lastSynced = .now
        await evictIfOverCap()
    }

    /// Clears cached receipts that have already uploaded (§9.5).
    public func clearCache() async {
        for fileID in ReceiptCachePolicy.clearablePlan(Array(cache.values)) {
            cache[fileID] = nil
            cachedData[fileID] = nil
        }
    }

    /// Trims the cache back under its cap, least recently read first (§9.5).
    public func evictIfOverCap() async {
        let cap = ReceiptCachePolicy.capBytes(
            fromMB: settings.receiptCacheCapMB == 0 ? nil : settings.receiptCacheCapMB
        )
        for fileID in ReceiptCachePolicy.evictionPlan(Array(cache.values), capBytes: cap) {
            cache[fileID] = nil
            cachedData[fileID] = nil
        }
    }

    /// Writes a backup archive into the store (§9.4).
    /// - Throws: A persistence or storage error if the write fails.
    public func backUpNow() async throws {
        try await backups.writeBackup(to: store)
    }

    /// Writes a scheduled backup if one has come due (§9.4).
    ///
    /// Checked on app foreground rather than by a timer, and the archive's own
    /// filename carries the date the schedule is measured from, so nothing extra
    /// needs persisting.
    ///
    /// - Parameter now: The moment being checked.
    /// - Returns: `true` when an archive was written.
    @discardableResult
    public func writeScheduledBackupIfDue(now: Date = .now) async -> Bool {
        guard settings.backupInterval != .off else { return false }
        let newest = (try? await store.listBackups().first)
            .flatMap { BackupSchedule.date(fromArchiveName: $0.name) }
        guard BackupSchedule.isDue(
            interval: settings.backupInterval, lastBackup: newest, now: now
        ) else { return false }

        do {
            try await backups.writeBackup(to: store)
            lastError = nil
            return true
        } catch {
            lastError = "The scheduled backup could not be written."
            return false
        }
    }

    /// The current storage status (§9.6).
    /// - Returns: The status to show.
    public func status() async -> SyncStatus {
        let isUsingCloud = await (store as? FileSystemReceiptStoreDescribing)?.isCloudBacked ?? false
        if let lastError {
            return SyncStatus(state: .error(message: lastError), isUsingCloud: isUsingCloud)
        }
        let pending = cache.values.filter { $0.uploadState != .uploaded }.count
        if pending > 0 {
            return SyncStatus(
                state: .pendingUploads(count: pending), isUsingCloud: isUsingCloud
            )
        }
        return SyncStatus(state: .upToDate(lastSynced: lastSynced), isUsingCloud: isUsingCloud)
    }

    /// How much the cache is holding, in words.
    /// - Returns: A summary such as "12.4 MB cached · 1 waiting to upload".
    public func cacheSummary() async -> String {
        let bytes = ReceiptCachePolicy.totalBytes(Array(cache.values))
        let waiting = cache.values.filter { $0.uploadState != .uploaded }.count
        let size = ByteCountFormatStyle(style: .file).format(Int64(bytes))
        guard waiting > 0 else { return "\(size) cached" }
        return "\(size) cached · \(waiting) waiting to upload"
    }

    /// When the most recent archive was written.
    /// - Returns: A summary line.
    public func lastBackupSummary() async -> String {
        guard let latest = try? await store.listBackups().first else {
            return "No backup written yet."
        }
        return "Most recent: \(latest.name)"
    }

    /// Records a receipt's new upload state.
    /// - Parameters:
    ///   - fileID: The receipt's identifier.
    ///   - state: Its new state.
    private func mark(_ fileID: String, as state: ReceiptUploadState) {
        guard let existing = cache[fileID] else { return }
        cache[fileID] = CachedReceipt(
            fileID: existing.fileID,
            sizeBytes: existing.sizeBytes,
            lastAccessed: existing.lastAccessed,
            uploadState: state
        )
    }
}
