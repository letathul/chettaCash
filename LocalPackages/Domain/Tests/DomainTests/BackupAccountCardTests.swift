import Foundation
import Testing
@testable import Domain

/// An account's card details across a backup archive (§9.4, §9.7).
///
/// Kept out of ``BackupTests`` so neither file outgrows the 300-line limit. The case
/// that matters is the second one: archives written before card details existed must
/// still import, or an upgrade would lose every account the user has.
@Suite("Account card details in a backup")
struct BackupAccountCardTests {

    /// A fixed date, so a round-trip never depends on the clock.
    private var reference: Date { Date(timeIntervalSince1970: 1_789_000_000) }

    /// Round-trips a value through its CSV row.
    /// - Parameter value: The value to round-trip.
    /// - Returns: The rebuilt value.
    private func roundTrip<Value: BackupRowConvertible>(_ value: Value) -> Value? {
        let text = CSVCodec.encode(rows: [value.backupRow()], columns: Value.backupColumns)
        guard let row = CSVCodec.decode(text).first else { return nil }
        return Value.fromBackupRow(row)
    }

    @Test("An archive written before card details existed still imports")
    func accountImportsWithoutCardColumns() throws {
        var row = Account(name: "Chequing").backupRow()
        row["last4"] = nil
        row["cardNetwork"] = nil

        let restored = try #require(Account.fromBackupRow(row))

        #expect(restored.last4 == nil)
        #expect(restored.cardNetwork == nil)
        #expect(restored.name == "Chequing", "the rest of the row is unaffected")
    }

    @Test("An account with no card recorded round-trips as having none")
    func accountWithoutCardRoundTrips() throws {
        let account = Account(name: "Cash", openingBalanceDate: reference)

        let restored = try #require(roundTrip(account))

        #expect(restored == account)
    }
}
