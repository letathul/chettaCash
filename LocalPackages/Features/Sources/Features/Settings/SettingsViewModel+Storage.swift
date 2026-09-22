import Foundation
import Domain

/// The Settings view model's storage and backup actions (§9.4, §9.5, §9.6).
///
/// Split from ``SettingsViewModel`` to keep each file within the 300-line limit.
extension SettingsViewModel {

    /// Loads storage status, the cache summary and the most recent backup.
    public func loadStorage() async {
        guard let storage else { return }
        syncStatus = await storage.status()
        cacheSummary = await storage.cacheSummary()
        lastBackupSummary = await storage.lastBackupSummary()
    }

    /// Writes a backup archive now (§9.4).
    public func backUpNow() async {
        guard let storage, !isBackingUp else { return }
        isBackingUp = true
        do {
            try await storage.backUpNow()
            errorMessage = nil
        } catch {
            errorMessage = "Could not write that backup."
        }
        isBackingUp = false
        await loadStorage()
    }

    /// Flushes pending uploads and refreshes status (§9.6).
    ///
    /// Does real work: this is not a decorative button.
    public func syncNow() async {
        guard let storage, !isSyncing else { return }
        isSyncing = true
        await storage.flushUploads()
        isSyncing = false
        await loadStorage()
    }

    /// Clears cached receipt images (§9.5).
    ///
    /// Skips anything still pending or failed — a photo taken offline must never be
    /// deletable before it reaches the cloud.
    public func clearReceiptCache() async {
        guard let storage else { return }
        await storage.clearCache()
        await loadStorage()
    }
}
