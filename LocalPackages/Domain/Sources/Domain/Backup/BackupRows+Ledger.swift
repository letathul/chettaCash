import Foundation

/// Transactions as CSV rows.
extension Transaction: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "amountCents", "type", "signedOverrideCents", "categoryID", "accountID",
            "date", "merchant", "location", "memo", "tags",
            "transferGroupID", "recurringRuleID", "isSeriesOverride",
            "receiptFileID", "receiptFileName", "receiptChecksum", "receiptUploadState"
        ]
    }

    /// Converts this transaction into a CSV row.
    ///
    /// Tracked-product chips are omitted: they are informational only and belong to
    /// the transaction rather than being records in their own right (§7.8).
    ///
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "amountCents": BackupField.string(amountCents),
            "type": type.rawValue,
            "signedOverrideCents": BackupField.string(signedOverrideCents),
            "categoryID": BackupField.string(categoryID),
            "accountID": BackupField.string(accountID),
            "date": BackupField.string(date),
            "merchant": merchant,
            "location": location ?? "",
            "memo": memo ?? "",
            "tags": BackupField.string(tags),
            "transferGroupID": BackupField.string(transferGroupID),
            "recurringRuleID": BackupField.string(recurringRuleID),
            "isSeriesOverride": BackupField.string(isSeriesOverride),
            "receiptFileID": receiptFileID ?? "",
            "receiptFileName": receiptFileName ?? "",
            "receiptChecksum": receiptChecksum ?? "",
            "receiptUploadState": receiptUploadState.rawValue
        ]
    }

    /// Rebuilds a transaction from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The transaction, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> Transaction? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return Transaction(
            id: id,
            amountCents: BackupField.int(row["amountCents"]) ?? 0,
            type: TransactionType(rawValue: row["type"] ?? "") ?? .expense,
            signedOverrideCents: BackupField.int(row["signedOverrideCents"]),
            categoryID: BackupField.uuid(row["categoryID"]),
            accountID: BackupField.uuid(row["accountID"]),
            date: BackupField.date(row["date"]) ?? .now,
            merchant: row["merchant"] ?? "",
            location: (row["location"]?.isEmpty == false) ? row["location"] : nil,
            memo: (row["memo"]?.isEmpty == false) ? row["memo"] : nil,
            tags: BackupField.tags(row["tags"]),
            transferGroupID: BackupField.uuid(row["transferGroupID"]),
            recurringRuleID: BackupField.uuid(row["recurringRuleID"]),
            isSeriesOverride: BackupField.bool(row["isSeriesOverride"]),
            receiptFileID: (row["receiptFileID"]?.isEmpty == false) ? row["receiptFileID"] : nil,
            receiptFileName: (row["receiptFileName"]?.isEmpty == false)
                ? row["receiptFileName"] : nil,
            receiptChecksum: (row["receiptChecksum"]?.isEmpty == false)
                ? row["receiptChecksum"] : nil,
            receiptUploadState: ReceiptUploadState(rawValue: row["receiptUploadState"] ?? "")
                ?? .none
        )
    }
}

/// Recurring rules as CSV rows.
extension RecurringRule: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "name", "amountCents", "type", "categoryID", "accountID",
            "frequency", "startDate", "endDate", "occurrenceLimit",
            "occurrencesGenerated", "isActive", "productID"
        ]
    }

    /// Converts this rule into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "name": name,
            "amountCents": BackupField.string(amountCents),
            "type": type.rawValue,
            "categoryID": BackupField.string(categoryID),
            "accountID": BackupField.string(accountID),
            "frequency": frequency.rawValue,
            "startDate": BackupField.string(startDate),
            "endDate": BackupField.string(endDate),
            "occurrenceLimit": BackupField.string(occurrenceLimit),
            "occurrencesGenerated": BackupField.string(occurrencesGenerated),
            "isActive": BackupField.string(isActive),
            "productID": BackupField.string(productID)
        ]
    }

    /// Rebuilds a rule from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The rule, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> RecurringRule? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return RecurringRule(
            id: id,
            name: row["name"] ?? "",
            amountCents: BackupField.int(row["amountCents"]) ?? 0,
            type: TransactionType(rawValue: row["type"] ?? "") ?? .expense,
            categoryID: BackupField.uuid(row["categoryID"]),
            accountID: BackupField.uuid(row["accountID"]),
            frequency: RecurringFrequency(rawValue: row["frequency"] ?? "") ?? .monthly,
            startDate: BackupField.date(row["startDate"]) ?? .now,
            endDate: BackupField.date(row["endDate"]),
            occurrenceLimit: BackupField.int(row["occurrenceLimit"]),
            occurrencesGenerated: BackupField.int(row["occurrencesGenerated"]) ?? 0,
            isActive: BackupField.bool(row["isActive"], default: true),
            productID: BackupField.uuid(row["productID"])
        )
    }
}

/// Card statements as CSV rows.
extension CardStatement: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "accountID", "periodStart", "closingDate", "dueDate",
            "computedBalanceCents", "overrideBalanceCents",
            "isPeriodClosed", "interestPromptResolved"
        ]
    }

    /// Converts this statement into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "accountID": BackupField.string(accountID),
            "periodStart": BackupField.string(periodStart),
            "closingDate": BackupField.string(closingDate),
            "dueDate": BackupField.string(dueDate),
            "computedBalanceCents": BackupField.string(computedBalanceCents),
            "overrideBalanceCents": BackupField.string(overrideBalanceCents),
            "isPeriodClosed": BackupField.string(isPeriodClosed),
            "interestPromptResolved": BackupField.string(interestPromptResolved)
        ]
    }

    /// Rebuilds a statement from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The statement, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> CardStatement? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return CardStatement(
            id: id,
            accountID: BackupField.uuid(row["accountID"]),
            periodStart: BackupField.date(row["periodStart"]) ?? .now,
            closingDate: BackupField.date(row["closingDate"]) ?? .now,
            dueDate: BackupField.date(row["dueDate"]) ?? .now,
            computedBalanceCents: BackupField.int(row["computedBalanceCents"]) ?? 0,
            overrideBalanceCents: BackupField.int(row["overrideBalanceCents"]),
            isPeriodClosed: BackupField.bool(row["isPeriodClosed"]),
            interestPromptResolved: BackupField.bool(row["interestPromptResolved"])
        )
    }
}

/// Products as CSV rows.
///
/// `transactionID` is the one column that must survive a round trip intact: a product
/// restored without its purchase would be an orphan, which the model does not allow.
extension Product: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "transactionID", "name", "categoryID", "tags", "notes", "sortIndex",
            "hasTrial", "trialEndsDate", "trialReminderLeadTime",
            "hasWarranty", "warrantyExpiresDate", "warrantyReminderLeadTime",
            "recurringRuleID"
        ]
    }

    /// Converts this product into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "transactionID": BackupField.string(transactionID),
            "name": name,
            "categoryID": BackupField.string(categoryID),
            "tags": BackupField.string(tags),
            "notes": notes ?? "",
            "sortIndex": BackupField.string(sortIndex),
            "hasTrial": BackupField.string(hasTrial),
            "trialEndsDate": BackupField.string(trialEndsDate),
            "trialReminderLeadTime": trialReminderLeadTime.rawValue,
            "hasWarranty": BackupField.string(hasWarranty),
            "warrantyExpiresDate": BackupField.string(warrantyExpiresDate),
            "warrantyReminderLeadTime": warrantyReminderLeadTime.rawValue,
            "recurringRuleID": BackupField.string(recurringRuleID)
        ]
    }

    /// Rebuilds a product from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The product, or `nil` without a usable identifier or purchase.
    public static func fromBackupRow(_ row: [String: String]) -> Product? {
        guard let id = BackupField.uuid(row["id"]),
              let transactionID = BackupField.uuid(row["transactionID"]) else { return nil }
        return Product(
            id: id,
            transactionID: transactionID,
            name: row["name"] ?? "",
            categoryID: BackupField.uuid(row["categoryID"]),
            tags: BackupField.tags(row["tags"]),
            notes: (row["notes"]?.isEmpty == false) ? row["notes"] : nil,
            sortIndex: BackupField.int(row["sortIndex"]) ?? 0,
            hasTrial: BackupField.bool(row["hasTrial"]),
            trialEndsDate: BackupField.date(row["trialEndsDate"]),
            trialReminderLeadTime: ReminderLeadTime(rawValue: row["trialReminderLeadTime"] ?? "")
                ?? .useDefault,
            hasWarranty: BackupField.bool(row["hasWarranty"]),
            warrantyExpiresDate: BackupField.date(row["warrantyExpiresDate"]),
            warrantyReminderLeadTime: ReminderLeadTime(
                rawValue: row["warrantyReminderLeadTime"] ?? ""
            ) ?? .useDefault,
            recurringRuleID: BackupField.uuid(row["recurringRuleID"])
        )
    }
}
