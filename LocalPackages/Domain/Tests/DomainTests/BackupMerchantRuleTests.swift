import Foundation
import Testing
@testable import Domain

/// Merchant-to-category pins in a backup archive (§4.8, §9.4).
///
/// The pins are the newest table in the archive, so the archive a previous build wrote
/// has no column for them at all — which is the case worth pinning down.
@Suite("Backup merchant pins")
struct BackupMerchantRuleTests {

    /// A fixed moment, so round trips do not depend on the clock.
    private var reference: Date {
        Date(timeIntervalSince1970: 1_789_000_000)
    }

    /// Encodes a value to CSV and reads it back.
    /// - Parameter value: The value to round-trip.
    /// - Returns: The rebuilt value.
    private func roundTrip<Value: BackupRowConvertible>(_ value: Value) -> Value? {
        let text = CSVCodec.encode(rows: [value.backupRow()], columns: Value.backupColumns)
        guard let row = CSVCodec.decode(text).first else { return nil }
        return Value.fromBackupRow(row)
    }

    @Test("A merchant pin round-trips exactly")
    func merchantPinRoundTrips() throws {
        let pin = MerchantCategoryRule(
            merchantKey: "whole-foods-mkt",
            displayName: "Whole Foods Mkt",
            categoryID: UUID(),
            updatedAt: reference
        )

        #expect(try #require(roundTrip(pin)) == pin)
    }

    @Test("A merchant pin with no category is refused rather than imported inert")
    func pinWithoutCategoryIsSkipped() {
        let row = ["id": UUID().uuidString, "merchantKey": "loblaws", "categoryID": ""]

        #expect(
            MerchantCategoryRule.fromBackupRow(row) == nil,
            "a pin that names no category could never match anything"
        )
    }

    @Test("An archive written before merchant pins existed still imports")
    func olderArchiveWithoutPinsImports() throws {
        let account = Account(name: "Chequing")
        let older = BackupArchive(
            manifest: BackupManifest(
                schemaVersion: 2, exportedAt: reference, rowCounts: ["accounts": 1]
            ),
            tables: [.accounts: [account.backupRow()]]
        )

        try BackupImporter.validate(older)
        let rows = BackupImporter.rowsToApply(older, against: [:])

        #expect(rows[.accounts]?.count == 1)
        #expect(rows[.merchantRules] == nil, "a table the archive predates is simply absent")
    }
}
