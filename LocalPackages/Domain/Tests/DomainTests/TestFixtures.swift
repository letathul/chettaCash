import Foundation
@testable import Domain

/// Builders that keep each test to a few lines.
enum Fixtures {
    /// A fixed reference moment, so tests never depend on the wall clock.
    static let now = Date(timeIntervalSince1970: 1_789_000_000)

    /// Returns a date offset from ``now`` by a number of days.
    /// - Parameter days: Days to offset. Negative values move into the past.
    /// - Returns: The offset date.
    static func day(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    /// Builds a spending or card account.
    /// - Parameters:
    ///   - name: Display name.
    ///   - kind: Spending account or credit card.
    ///   - openingCents: Opening balance in cents, stored as given.
    ///   - isClosed: Whether the account is closed.
    /// - Returns: The account.
    static func account(
        name: String = "Chequing",
        kind: AccountKind = .account,
        openingCents: Int = 0,
        isClosed: Bool = false
    ) -> Account {
        Account(
            name: name,
            kind: kind,
            openingBalanceCents: openingCents,
            openingBalanceDate: day(-365),
            isClosed: isClosed
        )
    }

    /// Builds a transaction against an account.
    /// - Parameters:
    ///   - type: The transaction type.
    ///   - cents: Positive magnitude in cents.
    ///   - account: The owning account.
    ///   - date: When it occurred. Defaults to yesterday, so it is posted.
    ///   - signedOverride: Signed amount, for adjustments.
    ///   - merchant: Merchant or payer name.
    /// - Returns: The transaction.
    static func transaction(
        _ type: TransactionType,
        cents: Int,
        account: Account,
        date: Date = day(-1),
        signedOverride: Int? = nil,
        merchant: String = ""
    ) -> Transaction {
        Transaction(
            amountCents: cents,
            type: type,
            signedOverrideCents: signedOverride,
            accountID: account.id,
            date: date,
            merchant: merchant
        )
    }

    /// A calendar pinned to UTC, so a fingerprint's day never depends on the test machine.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}
