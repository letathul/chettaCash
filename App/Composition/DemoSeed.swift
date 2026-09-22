#if DEBUG
import Foundation
import Domain

/// Populates the store with sample accounts for manual and visual checking.
///
/// Debug builds only, and only when launched with `--seed-demo-accounts`. This is
/// development scaffolding, never a code path a shipping build can reach.
enum DemoSeed {
    /// The launch argument that triggers seeding.
    static let launchArgument = "--seed-demo-accounts"

    /// Whether this launch asked for demo data.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Inserts two groups, three accounts and one closed account.
    /// - Parameter dependencies: The composition root to seed through.
    static func run(_ dependencies: AppDependencies) async {
        guard let accounts = try? await dependencies.accounts.accounts(includeClosed: true),
              accounts.isEmpty else { return }

        let everyday = Domain.AccountGroup(name: "Everyday", sortIndex: 0)
        let savings = Domain.AccountGroup(name: "Savings", sortIndex: 1)
        try? await dependencies.accounts.save(everyday)
        try? await dependencies.accounts.save(savings)

        let seeds: [Domain.Account] = [
            Domain.Account(
                name: "TD Chequing", kind: .account, openingBalanceCents: 482_350,
                openingBalanceDate: day(-200),
                sortIndex: 0, groupID: everyday.id
            ),
            Domain.Account(
                name: "TD Visa", kind: .card, openingBalanceCents: -124_075,
                openingBalanceDate: day(-95),
                sortIndex: 1, groupID: everyday.id,
                statementDayOfMonth: 5, paymentDueDayOfMonth: 25
            ),
            Domain.Account(
                name: "Emergency Fund", kind: .account, openingBalanceCents: 1_200_000,
                openingBalanceDate: day(-200),
                sortIndex: 0, groupID: savings.id
            ),
            AccountLifecycle.closed(
                Domain.Account(
                    name: "Old Chequing", kind: .account, openingBalanceCents: 0,
                    openingBalanceDate: day(-200),
                    sortIndex: 1, groupID: savings.id
                ),
                on: Date(timeIntervalSince1970: 1_789_000_000)
            )
        ]
        for seed in seeds {
            try? await dependencies.accounts.save(seed)
        }
        await seedTransactions(dependencies, chequing: seeds[0], card: seeds[1])
    }

    /// Inserts expenses, income, a transfer, an adjustment and a future charge.
    /// - Parameters:
    ///   - dependencies: The composition root to seed through.
    ///   - chequing: The spending account.
    ///   - card: The credit card.
    private static func seedTransactions(
        _ dependencies: AppDependencies,
        chequing: Domain.Account,
        card: Domain.Account
    ) async {
        let categories = (try? await dependencies.categories.allCategories()) ?? []
        let entries = sampleEntries(categories: categories, chequing: chequing, card: card)
        for entry in entries {
            try? await dependencies.transactions.save(entry)
        }

        if let legs = try? TransferFactory.makeLegs(
            amountCents: 50_000, date: day(-2),
            sourceAccountID: chequing.id, destinationAccountID: card.id,
            merchant: "Card payment"
        ) {
            try? await dependencies.transactions.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        }

        let correction = AdjustmentFactory.make(
            accountID: chequing.id, signedCents: -1_250, date: day(-4), memo: "Balance correction"
        )
        try? await dependencies.transactions.save(correction)

        await seedProducts(dependencies, card: card, chequing: chequing)
        await seedComparisons(dependencies)

        // A dormant monthly rule, so the engine has missed occurrences to catch up on.
        let rule = Domain.RecurringRule(
            name: "Rent",
            amountCents: 180_000,
            accountID: chequing.id,
            frequency: .monthly,
            startDate: day(-70)
        )
        try? await dependencies.recurringRules.save(rule)
    }

    /// Inserts two saved price comparisons, one complete and one not.
    /// - Parameter dependencies: The composition root to seed through.
    private static func seedComparisons(_ dependencies: AppDependencies) async {
        let olive = Domain.Comparison(
            label: "Olive oil",
            unitCategory: .volume,
            itemAPriceCents: 1_299,
            itemAQuantity: 500,
            itemAUnit: PackageUnit.millilitres.rawValue,
            itemBPriceCents: 2_199,
            itemBQuantity: 1,
            itemBUnit: PackageUnit.litres.rawValue,
            sortIndex: 0
        )
        let rice = Domain.Comparison(
            label: "Rice",
            unitCategory: .mass,
            itemAPriceCents: 449,
            itemAQuantity: 1,
            itemAUnit: PackageUnit.kilograms.rawValue,
            sortIndex: 1
        )
        for comparison in [olive, rice] {
            try? await dependencies.comparisons.save(comparison)
        }
    }

    /// A date offset from now by whole days.
    /// - Parameter offset: Days to offset. Negative moves into the past.
    /// - Returns: The offset date.
    static func day(_ offset: Int) -> Date {
        .now.addingTimeInterval(Double(offset) * 86_400)
    }

    /// Builds the sample expense and income entries.
    /// - Parameters:
    ///   - categories: The seeded categories, used to resolve labels to identifiers.
    ///   - chequing: The spending account.
    ///   - card: The credit card.
    /// - Returns: The entries to insert.
    private static func sampleEntries(
        categories: [Domain.Category],
        chequing: Domain.Account,
        card: Domain.Account
    ) -> [Domain.Transaction] {
        func categoryID(_ label: String) -> UUID? {
            categories.first { $0.label == label && $0.context == .expense }?.id
        }
        return [
            Domain.Transaction(
                amountCents: 8_432, type: .expense, categoryID: categoryID("Groceries"),
                accountID: chequing.id, date: day(-1), merchant: "Whole Foods",
                tags: ["weekly"]
            ),
            Domain.Transaction(
                amountCents: 1_890, type: .expense, categoryID: categoryID("Food & drink"),
                accountID: card.id, date: day(-1), merchant: "Blue Bottle"
            ),
            Domain.Transaction(
                amountCents: 4_500, type: .expense, categoryID: categoryID("Transport"),
                accountID: card.id, date: day(-3), merchant: "Metro Card"
            ),
            Domain.Transaction(
                amountCents: 320_000, type: .income, accountID: chequing.id,
                date: day(-5), merchant: "Salary"
            ),
            Domain.Transaction(
                amountCents: 12_999, type: .expense, categoryID: categoryID("Bills"),
                accountID: chequing.id, date: day(4), merchant: "Internet"
            ),
            Domain.Transaction(
                amountCents: 23_450, type: .expense, categoryID: categoryID("Shopping"),
                accountID: chequing.id, date: day(-40), merchant: "Uniqlo"
            ),
            Domain.Transaction(
                amountCents: 31_200, type: .expense, categoryID: categoryID("Groceries"),
                accountID: chequing.id, date: day(-72), merchant: "Costco"
            ),
            Domain.Transaction(
                amountCents: 18_700, type: .expense, categoryID: categoryID("Food & drink"),
                accountID: chequing.id, date: day(-105), merchant: "Osteria"
            )
        ]
    }
}
#endif
