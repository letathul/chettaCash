import Foundation
import Testing
@testable import Domain

/// Phase 13 acceptance criteria for the backup archive (§9.4).
@Suite("Backup archive")
struct BackupTests {

    /// A fixed moment, so round trips do not depend on the clock.
    private var reference: Date {
        Date(timeIntervalSince1970: 1_789_000_000)
    }

    // MARK: - CSV encoding

    @Test("A field containing a comma survives a round trip")
    func commasSurvive() {
        let rows = [["id": "1", "merchant": "Smith, Jones & Co"]]

        let text = CSVCodec.encode(rows: rows, columns: ["id", "merchant"])
        let decoded = CSVCodec.decode(text)

        #expect(decoded == rows)
    }

    @Test("Quotes and newlines survive a round trip")
    func quotesAndNewlinesSurvive() {
        let rows = [["id": "1", "memo": "He said \"hello\"\nthen left"]]

        let decoded = CSVCodec.decode(CSVCodec.encode(rows: rows, columns: ["id", "memo"]))

        #expect(decoded == rows)
    }

    @Test("An empty table decodes to no rows")
    func emptyTable() {
        let text = CSVCodec.encode(rows: [], columns: ["id", "name"])
        #expect(CSVCodec.decode(text).isEmpty)
    }

    @Test("Tags survive even when one contains a comma")
    func tagsWithCommasSurvive() {
        let tags = ["weekly", "food, drink", "household"]
        #expect(BackupField.tags(BackupField.string(tags)) == tags)
    }

    // MARK: - Entity round trips

    /// Round-trips a value through its CSV row.
    /// - Parameter value: The value to round-trip.
    /// - Returns: The rebuilt value.
    private func roundTrip<Value: BackupRowConvertible>(_ value: Value) -> Value? {
        let text = CSVCodec.encode(rows: [value.backupRow()], columns: Value.backupColumns)
        guard let row = CSVCodec.decode(text).first else { return nil }
        return Value.fromBackupRow(row)
    }

    @Test("An account round-trips exactly")
    func accountRoundTrips() throws {
        let account = Account(
            name: "TD Visa", kind: .card, openingBalanceCents: -124_075,
            openingBalanceDate: reference, sortIndex: 2, isClosed: true,
            closedDate: reference, groupID: UUID(),
            statementDayOfMonth: 5, paymentDueDayOfMonth: 25, remindBeforeDueDate: false,
            last4: "4821", cardNetwork: .visa
        )

        let restored = try #require(roundTrip(account))

        #expect(restored == account)
    }

    @Test("A transaction round-trips exactly, tags and all")
    func transactionRoundTrips() throws {
        let transaction = Transaction(
            amountCents: 8_432, type: .expense, signedOverrideCents: nil,
            categoryID: UUID(), accountID: UUID(), date: reference,
            merchant: "Whole Foods, Market", location: "Downtown",
            memo: "Line one\nLine two", tags: ["weekly", "food, drink"],
            transferGroupID: UUID(), recurringRuleID: UUID(), isSeriesOverride: true,
            receiptFileID: "abc", receiptFileName: "r.jpg", receiptChecksum: "sha",
            receiptUploadState: .uploaded
        )

        let restored = try #require(roundTrip(transaction))

        #expect(restored == transaction)
    }

    @Test("Every other entity round-trips exactly")
    func otherEntitiesRoundTrip() throws {
        let group = AccountGroup(name: "Everyday", sortIndex: 1)
        #expect(try #require(roundTrip(group)) == group)

        let category = Category(label: "Food & drink", context: .expense, isBuiltIn: true)
        #expect(try #require(roundTrip(category)) == category)

        let rule = RecurringRule(
            name: "Rent", amountCents: 180_000, accountID: UUID(),
            startDate: reference, endDate: reference, occurrenceLimit: 12,
            occurrencesGenerated: 3, productID: UUID()
        )
        #expect(try #require(roundTrip(rule)) == rule)

        let statement = CardStatement(
            accountID: UUID(), periodStart: reference, closingDate: reference,
            dueDate: reference, computedBalanceCents: 10_000,
            overrideBalanceCents: 10_450, isPeriodClosed: true, interestPromptResolved: true
        )
        #expect(try #require(roundTrip(statement)) == statement)

        var product = Product(
            transactionID: UUID(), name: "Laptop", tags: ["work"],
            notes: "Warranty card is in the box", sortIndex: 2
        )
        product.hasWarranty = true
        product.warrantyExpiresDate = reference
        product.warrantyReminderLeadTime = .oneWeekBefore
        #expect(try #require(roundTrip(product)) == product)

        let comparison = Comparison(
            label: "Olive oil", unitCategory: .volume,
            itemAPriceCents: 1_299, itemAQuantity: 500, itemAUnit: "mL",
            itemBPriceCents: 2_199, itemBQuantity: 1, itemBUnit: "L", sortIndex: 3
        )
        #expect(try #require(roundTrip(comparison)) == comparison)
    }

    @Test("Dates keep millisecond precision through the archive")
    func datePrecision() throws {
        // Finance dates are day-level, so milliseconds are ample — but the limit is
        // worth pinning down, because an exact-equality round trip depends on it.
        let precise = Date(timeIntervalSince1970: 1_789_000_000.123_456)
        let restored = try #require(BackupField.date(BackupField.string(precise)))

        #expect(abs(restored.timeIntervalSince(precise)) < 0.001)
        #expect(restored != precise, "sub-millisecond precision is not preserved")
    }

    @Test("Optional product columns absent from a row read as not set")
    func sparseProductRowImports() throws {
        // Columns a row does not carry must read as "not set" rather than failing the
        // whole import.
        let row = [
            "id": UUID().uuidString,
            "transactionID": UUID().uuidString,
            "name": "Laptop"
        ]

        let restored = try #require(Product.fromBackupRow(row))

        #expect(restored.name == "Laptop")
        #expect(restored.notes == nil)
        #expect(restored.categoryID == nil)
        #expect(restored.sortIndex == 0)
    }

    @Test("A product row with no purchase is refused rather than orphaned")
    func productWithoutPurchaseIsSkipped() {
        // A product only exists as part of a transaction (§7.8), so a row missing its
        // `transactionID` cannot be rebuilt — inventing one would attach it to nothing.
        let row = ["id": UUID().uuidString, "name": "Laptop"]

        #expect(Product.fromBackupRow(row) == nil)
    }

    @Test("A row without a usable identifier is skipped rather than guessed at")
    func rowWithoutIdentifierIsSkipped() {
        #expect(Account.fromBackupRow(["name": "Orphan"]) == nil)
        #expect(Transaction.fromBackupRow(["id": "not-a-uuid"]) == nil)
    }

    // MARK: - Import (§9.4)

    /// Builds an archive holding one account and one transaction.
    /// - Parameters:
    ///   - account: The account to include.
    ///   - transaction: The transaction to include.
    /// - Returns: The archive.
    private func archive(
        account: Account,
        transaction: Transaction
    ) -> BackupArchive {
        BackupArchive.make(
            tables: [
                .accounts: [account.backupRow()],
                .transactions: [transaction.backupRow()]
            ],
            exportedAt: reference
        )
    }

    @Test("Importing into an empty store inserts everything")
    func importIntoEmptyStore() throws {
        let account = Account(name: "Chequing")
        let transaction = Transaction(amountCents: 100, accountID: account.id)
        let archive = archive(account: account, transaction: transaction)

        let diff = BackupImporter.diff(archive, against: [:])

        #expect(diff.changes[.accounts]?.inserted == 1)
        #expect(diff.changes[.transactions]?.inserted == 1)
        #expect(diff.isNoOp == false)
    }

    @Test("Importing the same archive twice produces no duplicates")
    func importIsIdempotent() {
        let account = Account(name: "Chequing")
        let transaction = Transaction(amountCents: 100, accountID: account.id)
        let archive = archive(account: account, transaction: transaction)
        let existing: [BackupEntity: [[String: String]]] = [
            .accounts: [account.backupRow()],
            .transactions: [transaction.backupRow()]
        ]

        let diff = BackupImporter.diff(archive, against: existing)
        let toApply = BackupImporter.rowsToApply(archive, against: existing)

        #expect(diff.changes[.accounts]?.unchanged == 1)
        #expect(diff.changes[.accounts]?.inserted == 0)
        #expect(diff.changes[.transactions]?.unchanged == 1)
        #expect(diff.isNoOp)
        #expect(toApply.isEmpty, "an unchanged re-import writes nothing at all")
    }

    @Test("A changed row is reported as updated, matched on identifier")
    func changedRowIsUpdated() {
        var account = Account(name: "Chequing")
        let transaction = Transaction(amountCents: 100, accountID: account.id)
        let existing: [BackupEntity: [[String: String]]] = [
            .accounts: [account.backupRow()],
            .transactions: [transaction.backupRow()]
        ]
        account.name = "TD Chequing"

        let archive = archive(account: account, transaction: transaction)
        let diff = BackupImporter.diff(archive, against: existing)

        #expect(diff.changes[.accounts]?.updated == 1)
        #expect(diff.changes[.accounts]?.inserted == 0, "the same id is an update, not an insert")
        #expect(BackupImporter.rowsToApply(archive, against: existing)[.accounts]?.count == 1)
    }

    @Test("An archive from a newer build is refused rather than partly read")
    func newerSchemaIsRefused() {
        let archive = BackupArchive(
            manifest: BackupManifest(
                schemaVersion: BackupArchive.currentSchemaVersion + 1,
                exportedAt: reference,
                rowCounts: [:]
            ),
            tables: [:]
        )

        #expect(throws: BackupImportError.schemaTooNew(
            found: BackupArchive.currentSchemaVersion + 1,
            supported: BackupArchive.currentSchemaVersion
        )) {
            try BackupImporter.validate(archive)
        }
    }

    @Test("An archive from this build or older is accepted")
    func currentSchemaIsAccepted() throws {
        try BackupImporter.validate(BackupArchive.make(tables: [:], exportedAt: reference))
    }

    @Test("The diff summary reads the way the specification describes it")
    func diffSummary() {
        var diff = BackupDiff()
        diff.changes[.transactions] = BackupDiff.EntityChange(
            inserted: 3, updated: 0, unchanged: 409
        )
        diff.changes[.accounts] = BackupDiff.EntityChange(inserted: 0, updated: 0, unchanged: 6)

        let summary = BackupImporter.summary(of: diff)

        #expect(summary.contains("412 transactions"))
        #expect(summary.contains("6 accounts"))
        #expect(summary.contains("3 new"))
        #expect(summary.contains("415 unchanged"))
    }

    @Test("An archive is named by its export date")
    func archiveFileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)) ?? reference

        #expect(BackupArchive.fileName(for: date, calendar: calendar)
                == "chetta-cash-backup-2026-09-12.zip")
    }
}
