import Foundation

/// Builds the recurring rule a subscription product implies (§7.7, §9 links).
///
/// There is no longer any "log as expense" link to build: a product is born from a
/// transaction, so the money is already recorded by the time the product exists. What
/// remains is the subscription link — a ``RecurringRule`` whose occurrences the Phase 6
/// engine generates like any other rule, so there is no second subscription registry.
///
/// The rule's amount comes from the **purchase**, because a product carries no price of
/// its own.
public enum ProductBilling {

    /// Builds the rule that bills for a product.
    ///
    /// Returns `nil` when the purchase was free or the product already has a rule, so
    /// editing a subscription updates its rule rather than creating a second.
    ///
    /// - Parameters:
    ///   - product: The product being billed.
    ///   - purchase: The transaction the product was bought in, which sets the amount.
    ///   - frequency: How often it charges.
    /// - Returns: The rule to insert, or `nil` when none is implied.
    public static func recurringRule(
        for product: Product,
        purchase: Transaction,
        frequency: RecurringFrequency
    ) -> RecurringRule? {
        guard product.recurringRuleID == nil, purchase.amountCents > 0 else { return nil }
        return RecurringRule(
            name: product.name,
            amountCents: purchase.amountCents,
            type: .expense,
            categoryID: product.categoryID,
            accountID: purchase.accountID,
            frequency: frequency,
            startDate: nextChargeDate(after: purchase.date, frequency: frequency),
            productID: product.id
        )
    }

    /// Applies edited product values to an existing rule.
    ///
    /// The rule's schedule is left alone: changing a subscription's price should not
    /// silently move when it charges.
    ///
    /// - Parameters:
    ///   - rule: The rule to update.
    ///   - product: The product carrying the new values.
    ///   - purchase: The transaction supplying the amount.
    ///   - frequency: The chosen frequency.
    /// - Returns: The updated rule.
    public static func updated(
        _ rule: RecurringRule,
        from product: Product,
        purchase: Transaction,
        frequency: RecurringFrequency
    ) -> RecurringRule {
        var updated = rule
        updated.name = product.name
        updated.amountCents = purchase.amountCents
        updated.categoryID = product.categoryID
        updated.accountID = purchase.accountID
        updated.frequency = frequency
        updated.productID = product.id
        updated.isActive = true
        return updated
    }

    /// The first billing date after a purchase.
    ///
    /// A subscription bought today charges again one period from now, not today — the
    /// purchase itself is already in the Ledger, which is where the product came from.
    ///
    /// - Parameters:
    ///   - date: The purchase date.
    ///   - frequency: How often it charges.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The first charge date.
    public static func nextChargeDate(
        after date: Date,
        frequency: RecurringFrequency,
        calendar: Calendar = .current
    ) -> Date {
        let seed = RecurringRule(frequency: frequency, startDate: date)
        return RecurringSchedule.nextDate(after: date, rule: seed, calendar: calendar) ?? date
    }
}
