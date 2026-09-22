import Foundation

/// Writes a backup archive into a store (§9.4).
///
/// Declared here so `Features` can trigger a backup without importing `Data`, and so
/// `Data` can conform without importing `Features`.
public protocol BackupWriting: Sendable {
    /// Builds and writes an archive.
    /// - Parameter store: Where to write it.
    /// - Throws: A persistence or storage error if the write fails.
    func writeBackup(to store: any ReceiptStore) async throws
}

/// Reports whether a store is backed by iCloud Drive rather than on-device storage.
public protocol FileSystemReceiptStoreDescribing: Sendable {
    /// Whether files are going to iCloud Drive.
    var isCloudBacked: Bool { get async }
}
