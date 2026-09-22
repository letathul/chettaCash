import Foundation
import Domain

/// The product writes (§7.3, §7.7, §7.8).
///
/// Split from ``ProductsViewModel`` to keep each file within the 300-line limit.
extension ProductsViewModel {

    /// Saves a product and its billing rule (§7.7).
    ///
    /// The purchase is never touched: it records what was paid on the day, and rewriting
    /// it from a product edit would silently alter past balances and totals.
    ///
    /// - Parameter form: The form to commit.
    /// - Returns: `true` when the form validated and was saved.
    @discardableResult
    public func save(_ form: ProductFormState) async -> Bool {
        guard var product = form.commit() else { return false }
        do {
            try await applyRecurring(form, to: &product)
            try await productRepository.save(product)
            await load()
            return true
        } catch {
            errorMessage = "Could not save that product."
            return false
        }
    }

    /// Saves a product that was built without the full form (§7.8).
    ///
    /// There is no billing rule to reconcile and no form to validate: the product arrives
    /// already assembled. ``save(_:)`` taking a form stays the path for the Add and Edit
    /// Product sheet, which does have a rule to apply.
    ///
    /// - Parameter product: The product to persist.
    /// - Returns: `true` when the write succeeded.
    @discardableResult
    public func save(_ product: Domain.Product) async -> Bool {
        do {
            try await productRepository.save(product)
            await load()
            return true
        } catch {
            errorMessage = "Could not save that product."
            return false
        }
    }

    /// Writes products created alongside a transaction that did not yet exist (§7.8).
    ///
    /// The Add Transaction form collects products before its transaction has been
    /// persisted, so their `transactionID` is stamped here, once there is one to stamp.
    ///
    /// - Parameters:
    ///   - pending: The products collected on the form.
    ///   - transactionID: The purchase they belong to.
    /// - Throws: A persistence error if a write fails.
    public func attach(_ pending: [Domain.Product], to transactionID: UUID) async throws {
        guard !pending.isEmpty else { return }
        for (index, product) in pending.enumerated() {
            var stamped = product
            stamped.transactionID = transactionID
            stamped.sortIndex = index
            try await productRepository.save(stamped)
        }
        await load()
    }

    /// Deletes a product, leaving its purchase and receipt in the Ledger.
    ///
    /// The receipt stays because it belongs to the purchase, which may still have
    /// sibling products pointing at the same image.
    ///
    /// - Parameter product: The product to delete.
    public func delete(_ product: Domain.Product) async {
        do {
            if let rule = rulesByProductID[product.id] {
                try await recurringRuleRepository.delete(id: rule.id)
            }
            try await productRepository.delete(id: product.id)
            await load()
        } catch {
            errorMessage = "Could not delete that product."
        }
    }

    /// Creates the zero-cost purchase behind a product nothing was paid for (§7.8).
    ///
    /// A product always belongs to a transaction, so something acquired for free — a
    /// gift, a hand-me-down, a warranty on an old device — gets a purchase of zero
    /// cents. It moves no balance and contributes nothing to any total.
    ///
    /// - Parameter accountID: The account to record it against, defaulting to the first
    ///   open one.
    /// - Returns: The new purchase, or `nil` when it could not be written.
    public func makeFreePurchase(accountID: UUID? = nil) async -> Domain.Transaction? {
        let transaction = Domain.Transaction(
            amountCents: 0,
            type: .expense,
            accountID: accountID ?? selectableAccounts.first?.id,
            date: .now,
            merchant: ""
        )
        do {
            try await transactionRepository.save(transaction)
            await load()
            return transaction
        } catch {
            errorMessage = "Could not start that product."
            return nil
        }
    }

    /// Creates a custom product category (§8.4).
    /// - Parameter label: The category's display text.
    /// - Returns: The identifier to select, whether newly created or already present.
    @discardableResult
    public func addCategory(label: String) async -> UUID? {
        if let existing = selectableCategories.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return existing.id
        }
        let category = Domain.Category(
            label: label, context: .product, sortIndex: selectableCategories.count
        )
        do {
            try await categoryRepository.save(category)
            await load()
            return category.id
        } catch {
            errorMessage = "Could not save that category."
            return nil
        }
    }

    /// Creates, updates or ends the product's billing rule.
    ///
    /// The rule's amount comes from the purchase, because the product has no price.
    ///
    /// - Parameters:
    ///   - form: The form being committed.
    ///   - product: The product being saved, updated with its rule identifier.
    /// - Throws: A persistence error if a write fails.
    private func applyRecurring(
        _ form: ProductFormState,
        to product: inout Domain.Product
    ) async throws {
        let existing = rulesByProductID[product.id]
        guard form.isRecurring else {
            if let existing {
                try await recurringRuleRepository.delete(id: existing.id)
                product.recurringRuleID = nil
            }
            return
        }
        if let existing {
            let updated = ProductBilling.updated(
                existing, from: product, purchase: form.purchase, frequency: form.frequency
            )
            try await recurringRuleRepository.save(updated)
            product.recurringRuleID = updated.id
        } else if let rule = ProductBilling.recurringRule(
            for: product, purchase: form.purchase, frequency: form.frequency
        ) {
            try await recurringRuleRepository.save(rule)
            product.recurringRuleID = rule.id
        }
    }
}
