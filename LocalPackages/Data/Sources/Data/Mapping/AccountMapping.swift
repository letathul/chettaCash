import Foundation
import Domain

/// Conversion between ``AccountGroupRecord`` and ``Domain/AccountGroup``.
extension AccountGroupRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/AccountGroup``.
    func toDomain() -> Domain.AccountGroup {
        Domain.AccountGroup(id: id, name: name, sortIndex: sortIndex)
    }

    /// Overwrites this record's fields from a Domain value.
    /// - Parameter group: The values to apply. Its `id` is not copied, because a
    ///   record's identity is fixed once inserted.
    func apply(_ group: Domain.AccountGroup) {
        name = group.name
        sortIndex = group.sortIndex
    }
}

/// Conversion between ``AccountRecord`` and ``Domain/Account``.
extension AccountRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/Account``, with the group flattened to an identifier.
    func toDomain() -> Domain.Account {
        Domain.Account(
            id: id,
            name: name,
            kind: kind,
            openingBalanceCents: openingBalanceCents,
            openingBalanceDate: openingBalanceDate,
            cachedBalanceCents: cachedBalanceCents,
            sortIndex: sortIndex,
            isClosed: isClosed,
            closedDate: closedDate,
            groupID: group?.id,
            statementDayOfMonth: statementDayOfMonth,
            paymentDueDayOfMonth: paymentDueDayOfMonth,
            remindBeforeDueDate: remindBeforeDueDate,
            last4: last4,
            cardNetwork: cardNetwork
        )
    }

    /// Overwrites this record's scalar fields from a Domain value.
    ///
    /// The `group` relationship is resolved by the repository, which owns the
    /// `ModelContext` needed to look the group up.
    ///
    /// - Parameter account: The values to apply.
    func apply(_ account: Domain.Account) {
        name = account.name
        kind = account.kind
        openingBalanceCents = account.openingBalanceCents
        openingBalanceDate = account.openingBalanceDate
        cachedBalanceCents = account.cachedBalanceCents
        sortIndex = account.sortIndex
        isClosed = account.isClosed
        closedDate = account.closedDate
        statementDayOfMonth = account.statementDayOfMonth
        paymentDueDayOfMonth = account.paymentDueDayOfMonth
        remindBeforeDueDate = account.remindBeforeDueDate
        last4 = account.last4
        cardNetwork = account.cardNetwork
    }
}

/// Conversion between ``CategoryRecord`` and ``Domain/Category``.
extension CategoryRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/Category``.
    func toDomain() -> Domain.Category {
        Domain.Category(
            id: id,
            label: label,
            context: context,
            isBuiltIn: isBuiltIn,
            isArchived: isArchived,
            sortIndex: sortIndex
        )
    }

    /// Overwrites this record's fields from a Domain value.
    /// - Parameter category: The values to apply.
    func apply(_ category: Domain.Category) {
        label = category.label
        context = category.context
        isBuiltIn = category.isBuiltIn
        isArchived = category.isArchived
        sortIndex = category.sortIndex
    }
}

/// Conversion between ``CardStatementRecord`` and ``Domain/CardStatement``.
extension CardStatementRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/CardStatement``.
    func toDomain() -> Domain.CardStatement {
        Domain.CardStatement(
            id: id,
            accountID: account?.id,
            periodStart: periodStart,
            closingDate: closingDate,
            dueDate: dueDate,
            computedBalanceCents: computedBalanceCents,
            overrideBalanceCents: overrideBalanceCents,
            isPeriodClosed: isPeriodClosed,
            interestPromptResolved: interestPromptResolved
        )
    }

    /// Overwrites this record's scalar fields from a Domain value.
    ///
    /// The `account` relationship is resolved by the repository.
    ///
    /// - Parameter statement: The values to apply.
    func apply(_ statement: Domain.CardStatement) {
        periodStart = statement.periodStart
        closingDate = statement.closingDate
        dueDate = statement.dueDate
        computedBalanceCents = statement.computedBalanceCents
        overrideBalanceCents = statement.overrideBalanceCents
        isPeriodClosed = statement.isPeriodClosed
        interestPromptResolved = statement.interestPromptResolved
    }
}

/// Conversion between ``StatementPaymentRecord`` and ``Domain/StatementPayment``.
extension StatementPaymentRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/StatementPayment``.
    func toDomain() -> Domain.StatementPayment {
        Domain.StatementPayment(
            id: id,
            statementID: statement?.id,
            transactionID: transaction?.id,
            amountCents: amountCents
        )
    }
}

/// Conversion between ``ProductRecord`` and ``Domain/Product``.
extension ProductRecord {
    /// Converts this record into its Domain value type.
    ///
    /// A record whose `transaction` is somehow missing cannot become a `Product`, whose
    /// `transactionID` is not optional. The repository refuses to write such a row, so
    /// this returns `nil` rather than inventing an identifier.
    ///
    /// - Returns: The equivalent ``Domain/Product``, or `nil` when it has no purchase.
    func toDomain() -> Domain.Product? {
        guard let transactionID = transaction?.id else { return nil }
        return Domain.Product(
            id: id,
            transactionID: transactionID,
            name: name,
            categoryID: categoryID,
            tags: tags,
            notes: notes,
            sortIndex: sortIndex,
            hasTrial: hasTrial,
            trialEndsDate: trialEndsDate,
            trialReminderLeadTime: trialReminderLeadTime,
            hasWarranty: hasWarranty,
            warrantyExpiresDate: warrantyExpiresDate,
            warrantyReminderLeadTime: warrantyReminderLeadTime,
            recurringRuleID: recurringRule?.id
        )
    }

    /// Overwrites this record's scalar fields from a Domain value.
    ///
    /// The `transaction` and `recurringRule` relationships are resolved by the
    /// repository.
    ///
    /// - Parameter product: The values to apply.
    func apply(_ product: Domain.Product) {
        name = product.name
        categoryID = product.categoryID
        tags = product.tags
        notes = product.notes
        sortIndex = product.sortIndex
        hasTrial = product.hasTrial
        trialEndsDate = product.trialEndsDate
        trialReminderLeadTime = product.trialReminderLeadTime
        hasWarranty = product.hasWarranty
        warrantyExpiresDate = product.warrantyExpiresDate
        warrantyReminderLeadTime = product.warrantyReminderLeadTime
    }
}

/// Conversion between ``ComparisonRecord`` and ``Domain/Comparison``.
extension ComparisonRecord {
    /// Converts this record into its Domain value type.
    /// - Returns: The equivalent ``Domain/Comparison``.
    func toDomain() -> Domain.Comparison {
        Domain.Comparison(
            id: id,
            label: label,
            unitCategory: unitCategory,
            itemAPriceCents: itemAPriceCents,
            itemAQuantity: itemAQuantity,
            itemAUnit: itemAUnit,
            itemBPriceCents: itemBPriceCents,
            itemBQuantity: itemBQuantity,
            itemBUnit: itemBUnit,
            sortIndex: sortIndex
        )
    }

    /// Overwrites this record's fields from a Domain value.
    /// - Parameter comparison: The values to apply.
    func apply(_ comparison: Domain.Comparison) {
        label = comparison.label
        unitCategory = comparison.unitCategory
        itemAPriceCents = comparison.itemAPriceCents
        itemAQuantity = comparison.itemAQuantity
        itemAUnit = comparison.itemAUnit
        itemBPriceCents = comparison.itemBPriceCents
        itemBQuantity = comparison.itemBQuantity
        itemBUnit = comparison.itemBUnit
        sortIndex = comparison.sortIndex
    }
}

/// Conversion between ``MerchantCategoryRuleRecord`` and ``Domain/MerchantCategoryRule``.
extension MerchantCategoryRuleRecord {
    /// Converts this record into its Domain value type.
    ///
    /// `categoryID` is optional on the record only because CloudKit requires it to be;
    /// a pin naming no category cannot match anything, so such a row is dropped.
    ///
    /// - Returns: The equivalent ``Domain/MerchantCategoryRule``, or `nil` when the row
    ///   names no category.
    func toDomain() -> Domain.MerchantCategoryRule? {
        guard let categoryID else { return nil }
        return Domain.MerchantCategoryRule(
            id: id,
            merchantKey: merchantKey,
            displayName: displayName,
            categoryID: categoryID,
            updatedAt: updatedAt
        )
    }

    /// Overwrites this record's fields from a Domain value.
    /// - Parameter rule: The values to apply.
    func apply(_ rule: Domain.MerchantCategoryRule) {
        merchantKey = rule.merchantKey
        displayName = rule.displayName
        categoryID = rule.categoryID
        updatedAt = rule.updatedAt
    }
}
