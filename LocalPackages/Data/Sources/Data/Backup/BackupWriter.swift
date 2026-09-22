import Foundation
import Domain

/// Builds and writes backup archives into a store (§9.4).
public struct BackupWriter: BackupWriting {
    /// Builds the archive.
    private let service: BackupService
    /// How many archives to keep before pruning older ones.
    private let keepCount: Int

    /// Creates the writer.
    /// - Parameters:
    ///   - repositories: Every repository the archive draws from.
    ///   - keepCount: How many archives to keep. Older ones are pruned (§9.4).
    public init(repositories: BackupRepositories, keepCount: Int = 5) {
        self.service = BackupService(repositories: repositories)
        self.keepCount = keepCount
    }

    /// Builds an archive and writes it, then prunes older ones.
    /// - Parameter store: Where to write it.
    /// - Throws: A persistence or storage error if the write fails.
    public func writeBackup(to store: any ReceiptStore) async throws {
        let now = Date.now
        let archive = try await service.makeArchive(exportedAt: now)
        let data = try service.encode(archive)
        _ = try await store.writeBackup(data, named: BackupArchive.fileName(for: now))
        try await prune(store)
    }

    /// Removes archives beyond the most recent few.
    /// - Parameter store: The store to prune.
    /// - Throws: A storage error if a delete fails.
    private func prune(_ store: any ReceiptStore) async throws {
        let archives = try await store.listBackups()
        guard archives.count > keepCount else { return }
        for stale in archives.dropFirst(keepCount) {
            try await store.delete(fileID: stale.fileID)
        }
    }
}

/// Reports whether the filesystem store is backed by iCloud Drive.
extension FileSystemReceiptStore: FileSystemReceiptStoreDescribing {
    /// Whether files are going to iCloud Drive rather than on-device storage.
    public var isCloudBacked: Bool {
        get async { await isUsingCloud }
    }
}
