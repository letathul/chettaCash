import Foundation
import Domain

/// Building the Dashboard's hero carousel pages (§7.1).
///
/// Split from ``DashboardViewModel/refresh()`` to keep each file within the 300-line
/// limit.
extension DashboardViewModel {

    /// Builds one page per open account, behind an "All accounts" page.
    ///
    /// The pages always cover every open account regardless of the focused-account
    /// setting: focus decides which page is *showing*, not which pages exist.
    ///
    /// - Parameter now: The moment the balances are read at.
    /// - Returns: The carousel's pages, "All accounts" first.
    func buildHeroPages(now: Date) -> [HeroPageModel] {
        let lines = BalanceSeriesEngine.dailyBalances(
            accounts: openAccounts, transactions: transactions, asOf: now
        )
        return [aggregatePage(now: now)] + zip(openAccounts, lines).map { account, series in
            accountPage(for: account, series: series, now: now)
        }
    }

    /// The "All accounts" page, which leads the carousel.
    /// - Parameter now: The moment the balances are read at.
    /// - Returns: The page.
    private func aggregatePage(now: Date) -> HeroPageModel {
        let series = BalanceSeriesEngine.dailyNetWorth(
            accounts: openAccounts, transactions: transactions, asOf: now
        )
        let cents = BalanceEngine.availableCashCents(
            accounts: openAccounts, transactions: transactions, asOf: now
        )
        return HeroPageModel(
            id: series.id,
            accountID: nil,
            title: "All accounts",
            maskedNumber: nil,
            balanceLabel: "Available cash",
            balanceText: money(cents),
            isNegative: cents < 0,
            series: series,
            insight: heroInsight(for: transactions, now: now)
        )
    }

    /// One account's page.
    /// - Parameters:
    ///   - account: The account to describe.
    ///   - series: Its daily balances.
    ///   - now: The moment the balance is read at.
    /// - Returns: The page.
    private func accountPage(
        for account: Domain.Account,
        series: BalanceSeries,
        now: Date
    ) -> HeroPageModel {
        let cents = BalanceEngine.currentBalanceCents(
            account: account, transactions: transactions, asOf: now
        )
        let scoped = transactions.filter { $0.accountID == account.id }
        return HeroPageModel(
            id: series.id,
            accountID: account.id,
            title: account.name,
            maskedNumber: account.last4.map { "•••• \($0)" },
            balanceLabel: account.kind == .card ? "Balance owing" : "Balance",
            balanceText: money(cents),
            isNegative: cents < 0,
            series: series,
            insight: heroInsight(for: scoped, now: now)
        )
    }

    /// Phrases the top category move, when one clears the engine's thresholds.
    ///
    /// The percentage is dropped when there was no spend last month to measure
    /// against, leaving the currency magnitude alone.
    ///
    /// - Parameters:
    ///   - scoped: The transactions in play, already narrowed to the page's account.
    ///   - now: The moment the months are measured against.
    /// - Returns: The insight, or `nil` when nothing is worth saying.
    private func heroInsight(for scoped: [Domain.Transaction], now: Date) -> HeroInsight? {
        guard let change = CategoryInsightEngine.topMovingCategory(
            transactions: scoped, categories: categories, reference: now
        ) else { return nil }
        let magnitude = money(abs(change.deltaCents))
        let changeText = change.percentChange.map { "\($0)% (\(magnitude))" } ?? magnitude
        let isFavourable = change.direction == .decrease
        return HeroInsight(
            message: "\(change.label) is \(isFavourable ? "down" : "up") \(changeText) this month",
            isFavourable: isFavourable,
            glyph: isFavourable ? "checkmark.circle.fill" : "flame.fill"
        )
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: settings.currencyCode)
    }
}
