import Foundation

/// Where a receipt lives in cloud storage (§9.3).
public struct ReceiptPath: Equatable, Hashable, Sendable {
    /// The four-digit year folder.
    public let year: String
    /// The `YYYY-MM` month folder.
    public let month: String

    /// The folder path relative to the app's storage root.
    public var folder: String { "Receipts/\(year)/\(month)" }

    /// The per-month manifest's path.
    ///
    /// The manifest maps each filename to its transaction identifier, so if the
    /// database is ever lost the receipts can be re-linked rather than becoming an
    /// anonymous pile of images (§9.3).
    public var manifestPath: String { "\(folder)/manifest.csv" }

    /// Creates a path.
    /// - Parameters:
    ///   - year: The year folder.
    ///   - month: The month folder.
    public init(year: String, month: String) {
        self.year = year
        self.month = month
    }
}

/// A file listed in cloud storage.
public struct RemoteFile: Equatable, Hashable, Sendable {
    /// The store's identifier for the file.
    public let fileID: String
    /// The file's name.
    public let name: String
    /// The file's size in bytes.
    public let sizeBytes: Int

    /// Creates a remote file.
    /// - Parameters:
    ///   - fileID: The store's identifier.
    ///   - name: The file's name.
    ///   - sizeBytes: The file's size.
    public init(fileID: String, name: String, sizeBytes: Int) {
        self.fileID = fileID
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

/// What a stored receipt belongs to (§9.3).
public enum ReceiptOwnerKind: String, Sendable, Equatable {
    /// A Ledger transaction.
    case transaction
    /// A Vault product.
    case product
}

/// Builds receipt folder paths and filenames (§9.3).
///
/// Filenames carry the date, a merchant slug, the amount and a short identifier
/// derived from the transaction's UUID, so a folder of receipts is readable on its
/// own and each file is traceable back to its transaction.
public enum ReceiptNaming {

    /// The folder a receipt taken on a date belongs in.
    /// - Parameters:
    ///   - date: When the receipt was captured.
    ///   - calendar: The calendar deciding the year and month.
    /// - Returns: The path.
    public static func path(for date: Date, calendar: Calendar = .current) -> ReceiptPath {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        return ReceiptPath(year: year, month: month)
    }

    /// The filename a receipt should carry.
    /// - Parameters:
    ///   - date: When the receipt was captured.
    ///   - merchant: The merchant name, which is slugified.
    ///   - amountCents: The transaction amount.
    ///   - ownerID: The transaction or product the receipt belongs to.
    ///   - calendar: The calendar deciding the date portion.
    /// - Returns: A name such as `2026-09-12_whole-foods_42.10_a3f9.jpg`.
    public static func fileName(
        date: Date,
        merchant: String,
        amountCents: Int,
        ownerID: UUID,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
        let amount = String(format: "%d.%02d", abs(amountCents) / 100, abs(amountCents) % 100)
        return "\(day)_\(slug(merchant))_\(amount)_\(shortID(ownerID)).jpg"
    }

    /// The identifier a stored receipt is known by: its path relative to the root.
    ///
    /// The store uses the same relative path as its own file identifier, so this one
    /// value is both "where it lives" and "how to ask for it back".
    ///
    /// - Parameters:
    ///   - date: When the receipt was captured.
    ///   - merchant: The merchant name, which is slugified.
    ///   - amountCents: The amount.
    ///   - ownerID: The transaction or product it belongs to.
    /// - Returns: A value such as `Receipts/2026/2026-09/2026-09-12_shop_42.10_a3f9.jpg`.
    public static func fileID(
        date: Date,
        merchant: String,
        amountCents: Int,
        ownerID: UUID
    ) -> String {
        let name = fileName(
            date: date, merchant: merchant, amountCents: amountCents, ownerID: ownerID
        )
        return "\(path(for: date).folder)/\(name)"
    }

    /// The identifier for page `page` of a multi-page receipt.
    ///
    /// A transaction stores exactly one receipt identifier (§7.8) — one till receipt
    /// covers however many products a purchase contained. But one receipt can still
    /// need two photographs when the paper is longer than a viewfinder, so extra pages
    /// are filed as siblings of the first: same folder, same name, a `-p2` suffix
    /// before the extension. The transaction keeps pointing at page one, and the pages
    /// are found again by shared prefix rather than by a second database column.
    ///
    /// - Parameters:
    ///   - baseFileID: Page one's identifier, from ``fileID(date:merchant:amountCents:ownerID:)``.
    ///   - page: The one-based page number. Page 1 is `baseFileID` itself.
    /// - Returns: The page's identifier.
    public static func pageFileID(baseFileID: String, page: Int) -> String {
        guard page > 1 else { return baseFileID }
        let dot = baseFileID.lastIndex(of: ".")
        guard let dot, dot > baseFileID.startIndex else { return "\(baseFileID)-p\(page)" }
        return "\(baseFileID[..<dot])-p\(page)\(baseFileID[dot...])"
    }

    /// The prefix every page of one receipt shares.
    ///
    /// Page one is `…_a3f9.jpg` and page two `…_a3f9-p2.jpg`, so the identifier with
    /// its extension removed is what they have in common.
    ///
    /// - Parameter baseFileID: Page one's identifier.
    /// - Returns: The shared prefix.
    public static func pagePrefix(forBaseFileID baseFileID: String) -> String {
        let dot = baseFileID.lastIndex(of: ".")
        guard let dot, dot > baseFileID.startIndex else { return baseFileID }
        return String(baseFileID[..<dot])
    }

    /// Reports whether one identifier is a page of the receipt starting at another.
    /// - Parameters:
    ///   - fileID: The identifier to test.
    ///   - baseFileID: Page one's identifier.
    /// - Returns: `true` when `fileID` is page one or one of its siblings.
    public static func isPage(_ fileID: String, ofBaseFileID baseFileID: String) -> Bool {
        pageNumber(of: fileID, ofBaseFileID: baseFileID) != nil
    }

    /// Which page of a receipt an identifier is.
    ///
    /// Sorting the identifiers as text does not work: `-` sorts before `.`, so
    /// `…_a3f9-p2.jpg` would come ahead of `…_a3f9.jpg`, and `-p10` ahead of `-p2`.
    /// The page number has to be read out and compared as a number.
    ///
    /// - Parameters:
    ///   - fileID: The identifier to inspect.
    ///   - baseFileID: Page one's identifier.
    /// - Returns: The one-based page number, or `nil` when `fileID` is not one of its
    ///   pages.
    public static func pageNumber(of fileID: String, ofBaseFileID baseFileID: String) -> Int? {
        if fileID == baseFileID { return 1 }
        let marker = "\(pagePrefix(forBaseFileID: baseFileID))-p"
        guard fileID.hasPrefix(marker) else { return nil }
        let rest = fileID.dropFirst(marker.count)
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, let page = Int(digits), page > 1 else { return nil }
        // Whatever follows the digits must be the extension, not more name: otherwise
        // a different receipt whose slug merely starts the same way would be adopted.
        let tail = rest.dropFirst(digits.count)
        guard tail.isEmpty || tail.hasPrefix(".") else { return nil }
        return page
    }

    /// A short, stable identifier derived from an owner's UUID.
    /// - Parameter id: The owner's identifier.
    /// - Returns: The first four hex characters, lowercased.
    public static func shortID(_ id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
    }

    /// Reduces a merchant name to a filename-safe slug.
    ///
    /// Diacritics are folded to ASCII first, so `Café` becomes `cafe`. These names
    /// end up in iCloud Drive where they may be read on other platforms, and an
    /// ASCII slug travels without surprises.
    ///
    /// - Parameter merchant: The merchant name.
    /// - Returns: A lowercase, hyphenated slug, or `"receipt"` when nothing survives.
    public static func slug(_ merchant: String) -> String {
        let folded = merchant
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let allowed = folded.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "receipt" : String(collapsed.prefix(40))
    }

    /// A manifest row linking a stored file back to whatever owns it (§9.3).
    ///
    /// The kind is carried alongside the identifier because a receipt can belong to a
    /// transaction *or* to a Vault product, and a bare UUID does not say which table to
    /// look in when the database is being rebuilt from the folder.
    ///
    /// - Parameters:
    ///   - fileName: The stored filename.
    ///   - ownerID: The transaction or product it belongs to.
    ///   - ownerKind: Which of the two it is.
    /// - Returns: The row, keyed by column name.
    public static func manifestRow(
        fileName: String,
        ownerID: UUID,
        ownerKind: ReceiptOwnerKind
    ) -> [String: String] {
        ["fileName": fileName, "ownerID": ownerID.uuidString, "ownerKind": ownerKind.rawValue]
    }

    /// The manifest's column order.
    public static let manifestColumns = ["fileName", "ownerID", "ownerKind"]
}

/// Stores receipt images and backup archives (§9.2).
///
/// The protocol exists so v2 can add Google Drive as an *implementation* rather than
/// a refactor (§13.2). **There is no provider picker in v1** — iCloud Drive is the
/// only implementation, and no disabled "coming soon" option ships.
public protocol ReceiptStore: Sendable {
    /// Whether the store is reachable right now.
    ///
    /// iCloud Drive needs a ubiquity container, which requires a signed build and a
    /// signed-in account; a build without one falls back to on-device storage.
    var isAvailable: Bool { get async }

    /// Uploads a file.
    /// - Parameters:
    ///   - data: The file's contents.
    ///   - named: The file's name.
    ///   - path: The folder it belongs in.
    /// - Returns: The store's identifier for the file.
    /// - Throws: A storage error if the write fails.
    func upload(_ data: Data, named: String, to path: ReceiptPath) async throws -> String

    /// Downloads a file.
    /// - Parameter fileID: The store's identifier.
    /// - Returns: The file's contents.
    /// - Throws: A storage error if the read fails.
    func download(fileID: String) async throws -> Data

    /// Deletes a file.
    /// - Parameter fileID: The store's identifier.
    /// - Throws: A storage error if the delete fails.
    func delete(fileID: String) async throws

    /// Lists the files in a folder.
    /// - Parameter path: The folder to list.
    /// - Returns: The files it holds.
    /// - Throws: A storage error if the listing fails.
    func list(path: ReceiptPath) async throws -> [RemoteFile]

    /// Writes a backup archive into the `Backups/` folder (§9.3).
    /// - Parameters:
    ///   - data: The archive's bytes.
    ///   - named: The archive's file name.
    /// - Returns: The store's identifier for the archive.
    /// - Throws: A storage error if the write fails.
    func writeBackup(_ data: Data, named: String) async throws -> String

    /// Lists the backup archives currently stored, newest first.
    /// - Returns: The archives.
    /// - Throws: A storage error if the listing fails.
    func listBackups() async throws -> [RemoteFile]

    /// Reads a backup archive.
    /// - Parameter fileID: The store's identifier.
    /// - Returns: The archive's bytes.
    /// - Throws: A storage error if the read fails.
    func readBackup(fileID: String) async throws -> Data
}
