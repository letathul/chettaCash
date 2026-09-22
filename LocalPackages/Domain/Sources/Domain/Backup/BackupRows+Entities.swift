import Foundation

/// Account groups as CSV rows.
extension AccountGroup: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] { ["id", "name", "sortIndex"] }

    /// Converts this group into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        ["id": BackupField.string(id), "name": name, "sortIndex": BackupField.string(sortIndex)]
    }

    /// Rebuilds a group from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The group, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> AccountGroup? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return AccountGroup(
            id: id, name: row["name"] ?? "", sortIndex: BackupField.int(row["sortIndex"]) ?? 0
        )
    }
}

/// Accounts as CSV rows.
extension Account: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "name", "kind", "openingBalanceCents", "openingBalanceDate",
            "sortIndex", "isClosed", "closedDate", "groupID",
            "statementDayOfMonth", "paymentDueDayOfMonth", "remindBeforeDueDate",
            "last4", "cardNetwork"
        ]
    }

    /// Converts this account into a CSV row.
    ///
    /// `cachedBalanceCents` is deliberately absent: it is a denormalised cache, not
    /// data, and is rebuilt from transactions on import (§4.1).
    ///
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "name": name,
            "kind": kind.rawValue,
            "openingBalanceCents": BackupField.string(openingBalanceCents),
            "openingBalanceDate": BackupField.string(openingBalanceDate),
            "sortIndex": BackupField.string(sortIndex),
            "isClosed": BackupField.string(isClosed),
            "closedDate": BackupField.string(closedDate),
            "groupID": BackupField.string(groupID),
            "statementDayOfMonth": BackupField.string(statementDayOfMonth),
            "paymentDueDayOfMonth": BackupField.string(paymentDueDayOfMonth),
            "remindBeforeDueDate": BackupField.string(remindBeforeDueDate),
            "last4": last4 ?? "",
            "cardNetwork": cardNetwork?.rawValue ?? ""
        ]
    }

    /// Rebuilds an account from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The account, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> Account? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return Account(
            id: id,
            name: row["name"] ?? "",
            kind: AccountKind(rawValue: row["kind"] ?? "") ?? .account,
            openingBalanceCents: BackupField.int(row["openingBalanceCents"]) ?? 0,
            openingBalanceDate: BackupField.date(row["openingBalanceDate"]) ?? .now,
            sortIndex: BackupField.int(row["sortIndex"]) ?? 0,
            isClosed: BackupField.bool(row["isClosed"]),
            closedDate: BackupField.date(row["closedDate"]),
            groupID: BackupField.uuid(row["groupID"]),
            statementDayOfMonth: BackupField.int(row["statementDayOfMonth"]),
            paymentDueDayOfMonth: BackupField.int(row["paymentDueDayOfMonth"]),
            remindBeforeDueDate: BackupField.bool(row["remindBeforeDueDate"], default: true),
            // Absent from archives written before card details existed, which read back
            // as `nil` rather than failing the import.
            last4: (row["last4"]?.isEmpty == false) ? row["last4"] : nil,
            cardNetwork: CardNetwork(rawValue: row["cardNetwork"] ?? "")
        )
    }
}

/// Categories as CSV rows.
extension Category: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        ["id", "label", "context", "isBuiltIn", "isArchived", "sortIndex"]
    }

    /// Converts this category into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "label": label,
            "context": context.rawValue,
            "isBuiltIn": BackupField.string(isBuiltIn),
            "isArchived": BackupField.string(isArchived),
            "sortIndex": BackupField.string(sortIndex)
        ]
    }

    /// Rebuilds a category from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The category, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> Category? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return Category(
            id: id,
            label: row["label"] ?? "",
            context: CategoryContext(rawValue: row["context"] ?? "") ?? .expense,
            isBuiltIn: BackupField.bool(row["isBuiltIn"]),
            isArchived: BackupField.bool(row["isArchived"]),
            sortIndex: BackupField.int(row["sortIndex"]) ?? 0
        )
    }
}

/// Saved price comparisons as CSV rows.
extension Comparison: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        [
            "id", "label", "unitCategory",
            "itemAPriceCents", "itemAQuantity", "itemAUnit",
            "itemBPriceCents", "itemBQuantity", "itemBUnit", "sortIndex"
        ]
    }

    /// Converts this comparison into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "label": label,
            "unitCategory": unitCategory?.rawValue ?? "",
            "itemAPriceCents": BackupField.string(itemAPriceCents),
            "itemAQuantity": BackupField.string(itemAQuantity),
            "itemAUnit": itemAUnit ?? "",
            "itemBPriceCents": BackupField.string(itemBPriceCents),
            "itemBQuantity": BackupField.string(itemBQuantity),
            "itemBUnit": itemBUnit ?? "",
            "sortIndex": BackupField.string(sortIndex)
        ]
    }

    /// Rebuilds a comparison from a CSV row.
    /// - Parameter row: The row.
    /// - Returns: The comparison, or `nil` without a usable identifier.
    public static func fromBackupRow(_ row: [String: String]) -> Comparison? {
        guard let id = BackupField.uuid(row["id"]) else { return nil }
        return Comparison(
            id: id,
            label: row["label"] ?? "",
            unitCategory: (row["unitCategory"]?.isEmpty == false)
                ? UnitCategory(rawValue: row["unitCategory"] ?? "")
                : nil,
            itemAPriceCents: BackupField.int(row["itemAPriceCents"]),
            itemAQuantity: BackupField.double(row["itemAQuantity"]),
            itemAUnit: (row["itemAUnit"]?.isEmpty == false) ? row["itemAUnit"] : nil,
            itemBPriceCents: BackupField.int(row["itemBPriceCents"]),
            itemBQuantity: BackupField.double(row["itemBQuantity"]),
            itemBUnit: (row["itemBUnit"]?.isEmpty == false) ? row["itemBUnit"] : nil,
            sortIndex: BackupField.int(row["sortIndex"]) ?? 0
        )
    }
}

/// Merchant-to-category pins as CSV rows.
extension MerchantCategoryRule: BackupRowConvertible {
    /// The column order this entity's table uses.
    public static var backupColumns: [String] {
        ["id", "merchantKey", "displayName", "categoryID", "updatedAt"]
    }

    /// Converts this pin into a CSV row.
    /// - Returns: The row.
    public func backupRow() -> [String: String] {
        [
            "id": BackupField.string(id),
            "merchantKey": merchantKey,
            "displayName": displayName,
            "categoryID": BackupField.string(categoryID),
            "updatedAt": BackupField.string(updatedAt)
        ]
    }

    /// Rebuilds a pin from a CSV row.
    ///
    /// A pin without a category is not a pin, so a row missing `categoryID` is dropped
    /// rather than imported as one that would never match.
    ///
    /// - Parameter row: The row.
    /// - Returns: The pin, or `nil` without a usable identifier and category.
    public static func fromBackupRow(_ row: [String: String]) -> MerchantCategoryRule? {
        guard let id = BackupField.uuid(row["id"]),
              let categoryID = BackupField.uuid(row["categoryID"]) else { return nil }
        return MerchantCategoryRule(
            id: id,
            merchantKey: row["merchantKey"] ?? "",
            displayName: row["displayName"] ?? "",
            categoryID: categoryID,
            updatedAt: BackupField.date(row["updatedAt"]) ?? .distantPast
        )
    }
}

/// The column order each entity's table uses.
///
/// Declared next to the enum rather than in the service that writes the archive, so a
/// new entity cannot be added to ``BackupEntity`` without the compiler demanding its
/// columns here too.
extension BackupEntity {
    /// This entity's columns, in order.
    public var backupColumns: [String] {
        switch self {
        case .accountGroups: return AccountGroup.backupColumns
        case .accounts: return Account.backupColumns
        case .transactions: return Transaction.backupColumns
        case .recurringRules: return RecurringRule.backupColumns
        case .cardStatements: return CardStatement.backupColumns
        case .products: return Product.backupColumns
        case .categories: return Category.backupColumns
        case .comparisons: return Comparison.backupColumns
        case .merchantRules: return MerchantCategoryRule.backupColumns
        }
    }
}
