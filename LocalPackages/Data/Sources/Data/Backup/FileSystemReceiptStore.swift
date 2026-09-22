import Foundation
import Domain

/// Stores receipts and backups as files, in iCloud Drive when it is available (§9.2).
///
/// The ubiquity container needs a signed build with the iCloud entitlement and a
/// signed-in account. When that is not available — an unsigned development build, or
/// a user signed out of iCloud — this falls back to the app's Documents directory so
/// the feature still works locally and the files still appear in the Files app.
///
/// Writes go through `NSFileCoordinator`, because another device's iCloud daemon can
/// be reading the same folder.
public actor FileSystemReceiptStore: ReceiptStore {

    /// The folder shown in the Files app.
    public static let rootFolderName = "Chetta Cash"

    /// The container identifier, when iCloud Drive is in use.
    private let ubiquityContainerID: String?
    /// Cached root, resolved once.
    private var cachedRoot: URL?

    /// Creates the store.
    /// - Parameter ubiquityContainerID: The iCloud container to use, if any.
    public init(ubiquityContainerID: String? = nil) {
        self.ubiquityContainerID = ubiquityContainerID
    }

    /// Whether a writable root could be resolved.
    public var isAvailable: Bool {
        get async { (try? root()) != nil }
    }

    /// Whether the resolved root is in iCloud Drive rather than on-device.
    public var isUsingCloud: Bool {
        get async {
            guard let root = try? root() else { return false }
            return root.path.contains("Mobile Documents")
        }
    }

    /// Uploads a receipt image.
    /// - Parameters:
    ///   - data: The image bytes.
    ///   - named: The file name.
    ///   - path: The year and month folder.
    /// - Returns: The file's path relative to the root, used as its identifier.
    /// - Throws: A storage error if the write fails.
    public func upload(_ data: Data, named: String, to path: ReceiptPath) async throws -> String {
        let relative = "\(path.folder)/\(named)"
        try write(data, relativePath: relative)
        return relative
    }

    /// Downloads a receipt image.
    /// - Parameter fileID: The file's relative path.
    /// - Returns: The image bytes.
    /// - Throws: A storage error if the read fails.
    public func download(fileID: String) async throws -> Data {
        try read(relativePath: fileID)
    }

    /// Deletes a stored file.
    /// - Parameter fileID: The file's relative path.
    /// - Throws: A storage error if the delete fails.
    public func delete(fileID: String) async throws {
        let url = try root().appending(path: fileID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Lists a receipt folder.
    /// - Parameter path: The folder to list.
    /// - Returns: The files it holds.
    /// - Throws: A storage error if the listing fails.
    public func list(path: ReceiptPath) async throws -> [RemoteFile] {
        try contents(ofRelativeFolder: path.folder)
    }

    /// Writes a backup archive.
    /// - Parameters:
    ///   - data: The archive bytes.
    ///   - named: The archive file name.
    /// - Returns: The archive's relative path.
    /// - Throws: A storage error if the write fails.
    public func writeBackup(_ data: Data, named: String) async throws -> String {
        let relative = "Backups/\(named)"
        try write(data, relativePath: relative)
        return relative
    }

    /// Lists stored backup archives, newest name first.
    /// - Returns: The archives.
    /// - Throws: A storage error if the listing fails.
    public func listBackups() async throws -> [RemoteFile] {
        try contents(ofRelativeFolder: "Backups").sorted { $0.name > $1.name }
    }

    /// Reads a backup archive.
    /// - Parameter fileID: The archive's relative path.
    /// - Returns: The archive bytes.
    /// - Throws: A storage error if the read fails.
    public func readBackup(fileID: String) async throws -> Data {
        try read(relativePath: fileID)
    }

    /// The storage root, preferring iCloud Drive.
    /// - Returns: The root folder's URL.
    /// - Throws: A storage error if no root can be created.
    private func root() throws -> URL {
        if let cachedRoot { return cachedRoot }
        let base: URL
        if let ubiquityContainerID,
           let container = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerID) {
            base = container.appending(path: "Documents")
        } else {
            base = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
        }
        let resolved = base.appending(path: Self.rootFolderName)
        try FileManager.default.createDirectory(
            at: resolved, withIntermediateDirectories: true
        )
        cachedRoot = resolved
        return resolved
    }

    /// Writes bytes to a relative path, creating folders as needed.
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - relativePath: Where to write them.
    /// - Throws: A storage error if the write fails.
    private func write(_ data: Data, relativePath: String) throws {
        let url = try root().appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    /// Reads bytes from a relative path.
    /// - Parameter relativePath: Where to read from.
    /// - Returns: The bytes.
    /// - Throws: A storage error if the read fails.
    private func read(relativePath: String) throws -> Data {
        let url = try root().appending(path: relativePath)
        var coordinationError: NSError?
        var result: Data?
        var readError: (any Error)?
        NSFileCoordinator().coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { target in
            do { result = try Data(contentsOf: target) } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let result else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return result
    }

    /// Lists a folder's files.
    /// - Parameter folder: The folder's relative path.
    /// - Returns: The files it holds, or none when the folder does not exist yet.
    /// - Throws: A storage error if the listing fails.
    private func contents(ofRelativeFolder folder: String) throws -> [RemoteFile] {
        let url = try root().appending(path: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        )
        return entries.map { entry in
            let size = (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return RemoteFile(
                fileID: "\(folder)/\(entry.lastPathComponent)",
                name: entry.lastPathComponent,
                sizeBytes: size
            )
        }
    }
}
