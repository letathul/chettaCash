import Foundation

/// Reads and writes store-only ZIP archives.
///
/// Foundation ships no ZIP API on iOS, and a backup is a handful of small CSV files,
/// so this implements the container format directly rather than taking a dependency.
/// Entries are stored uncompressed: §9.4 cares that the archive is re-importable, not
/// that it is small, and store-only keeps the reader simple enough to trust.
public enum ZipArchive {

    /// Signature of a local file header.
    private static let localHeader: UInt32 = 0x0403_4b50
    /// Signature of a central directory entry.
    private static let centralHeader: UInt32 = 0x0201_4b50
    /// Signature of the end-of-central-directory record.
    private static let endOfDirectory: UInt32 = 0x0605_4b50

    /// Builds a ZIP archive from named files.
    /// - Parameter files: Each file's contents, keyed by name.
    /// - Returns: The archive's bytes.
    public static func archive(files: [String: Data]) -> Data {
        var payload = Data()
        var directory = Data()
        var count: UInt16 = 0

        for name in files.keys.sorted() {
            guard let contents = files[name], let nameData = name.data(using: .utf8) else {
                continue
            }
            let offset = UInt32(payload.count)
            let checksum = crc32(contents)

            payload.append(header(
                signature: localHeader, name: nameData, contents: contents, checksum: checksum
            ))
            payload.append(contents)

            directory.append(centralEntry(
                name: nameData, contents: contents, checksum: checksum, offset: offset
            ))
            count += 1
        }

        let directoryOffset = UInt32(payload.count)
        payload.append(directory)
        payload.append(endRecord(
            count: count, size: UInt32(directory.count), offset: directoryOffset
        ))
        return payload
    }

    /// Reads a ZIP archive's files.
    ///
    /// Walks the local headers rather than the central directory: the archives read
    /// here are ones this app wrote, and the linear scan needs no seeking.
    ///
    /// - Parameter data: The archive's bytes.
    /// - Returns: Each file's contents, keyed by name.
    public static func files(in data: Data) -> [String: Data] {
        var files: [String: Data] = [:]
        var cursor = data.startIndex

        while cursor + 30 <= data.endIndex {
            guard read32(data, at: cursor) == localHeader else { break }
            let nameLength = Int(read16(data, at: cursor + 26))
            let extraLength = Int(read16(data, at: cursor + 28))
            let size = Int(read32(data, at: cursor + 18))
            let nameStart = cursor + 30
            let contentsStart = nameStart + nameLength + extraLength
            guard contentsStart + size <= data.endIndex else { break }

            if let name = String(data: data[nameStart..<(nameStart + nameLength)], encoding: .utf8) {
                files[name] = data[contentsStart..<(contentsStart + size)]
            }
            cursor = contentsStart + size
        }
        return files
    }

    /// Builds a local file header.
    /// - Parameters:
    ///   - signature: The header's signature.
    ///   - name: The file name's bytes.
    ///   - contents: The file's contents.
    ///   - checksum: The contents' CRC-32.
    /// - Returns: The header bytes.
    private static func header(
        signature: UInt32,
        name: Data,
        contents: Data,
        checksum: UInt32
    ) -> Data {
        var header = Data()
        header.append(bytes(signature))
        header.append(bytes(UInt16(20)))            // version needed
        header.append(bytes(UInt16(0)))             // flags
        header.append(bytes(UInt16(0)))             // stored, no compression
        header.append(bytes(UInt16(0)))             // modification time
        header.append(bytes(UInt16(0)))             // modification date
        header.append(bytes(checksum))
        header.append(bytes(UInt32(contents.count)))
        header.append(bytes(UInt32(contents.count)))
        header.append(bytes(UInt16(name.count)))
        header.append(bytes(UInt16(0)))             // extra field length
        header.append(name)
        return header
    }

    /// Builds a central directory entry.
    /// - Parameters:
    ///   - name: The file name's bytes.
    ///   - contents: The file's contents.
    ///   - checksum: The contents' CRC-32.
    ///   - offset: Where the local header starts.
    /// - Returns: The entry bytes.
    private static func centralEntry(
        name: Data,
        contents: Data,
        checksum: UInt32,
        offset: UInt32
    ) -> Data {
        var entry = Data()
        entry.append(bytes(centralHeader))
        entry.append(bytes(UInt16(20)))             // version made by
        entry.append(bytes(UInt16(20)))             // version needed
        entry.append(bytes(UInt16(0)))              // flags
        entry.append(bytes(UInt16(0)))              // stored
        entry.append(bytes(UInt16(0)))              // modification time
        entry.append(bytes(UInt16(0)))              // modification date
        entry.append(bytes(checksum))
        entry.append(bytes(UInt32(contents.count)))
        entry.append(bytes(UInt32(contents.count)))
        entry.append(bytes(UInt16(name.count)))
        entry.append(bytes(UInt16(0)))              // extra field length
        entry.append(bytes(UInt16(0)))              // comment length
        entry.append(bytes(UInt16(0)))              // disk number
        entry.append(bytes(UInt16(0)))              // internal attributes
        entry.append(bytes(UInt32(0)))              // external attributes
        entry.append(bytes(offset))
        entry.append(name)
        return entry
    }

    /// Builds the end-of-central-directory record.
    /// - Parameters:
    ///   - count: How many entries the archive holds.
    ///   - size: The central directory's size.
    ///   - offset: Where the central directory starts.
    /// - Returns: The record bytes.
    private static func endRecord(count: UInt16, size: UInt32, offset: UInt32) -> Data {
        var record = Data()
        record.append(bytes(endOfDirectory))
        record.append(bytes(UInt16(0)))             // disk number
        record.append(bytes(UInt16(0)))             // directory start disk
        record.append(bytes(count))
        record.append(bytes(count))
        record.append(bytes(size))
        record.append(bytes(offset))
        record.append(bytes(UInt16(0)))             // comment length
        return record
    }

    /// Encodes a 16-bit value little-endian.
    /// - Parameter value: The value.
    /// - Returns: Its bytes.
    private static func bytes(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Encodes a 32-bit value little-endian.
    /// - Parameter value: The value.
    /// - Returns: Its bytes.
    private static func bytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// Reads a little-endian 16-bit value.
    /// - Parameters:
    ///   - data: The bytes to read from.
    ///   - offset: Where to read.
    /// - Returns: The value.
    private static func read16(_ data: Data, at offset: Data.Index) -> UInt16 {
        guard offset + 2 <= data.endIndex else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    /// Reads a little-endian 32-bit value.
    /// - Parameters:
    ///   - data: The bytes to read from.
    ///   - offset: Where to read.
    /// - Returns: The value.
    private static func read32(_ data: Data, at offset: Data.Index) -> UInt32 {
        guard offset + 4 <= data.endIndex else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    /// Computes a CRC-32 checksum, as the ZIP format requires.
    /// - Parameter data: The bytes to check.
    /// - Returns: The checksum.
    static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xFFFF_FFFF
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                checksum = (checksum & 1) == 1
                    ? (checksum >> 1) ^ 0xEDB8_8320
                    : checksum >> 1
            }
        }
        return checksum ^ 0xFFFF_FFFF
    }
}
