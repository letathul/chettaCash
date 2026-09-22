import Foundation

/// The rule that keeps at least one usable account in the app (§7.10).
///
/// A user who skips onboarding, or who closes every account they have, would
/// otherwise be left with nowhere to record a transaction. This policy decides
/// whether a starter "Cash" account is owed, and builds it.
///
/// It is deliberately a pure function of the accounts and groups handed to it, so
/// it costs nothing to ask on every foreground. Asking again after acting returns
/// `nil`, which is what makes the caller idempotent.
public enum StarterAccountPolicy {
    /// The group the starter account is filed under.
    public static let groupName = "Cash"
    /// The starter account's display name.
    public static let accountName = "Cash"

    /// The account to create, and the group to create alongside it when one is needed.
    public struct Starter: Equatable, Sendable {
        /// The group to insert first, or `nil` when an existing group is reused.
        public let group: AccountGroup?
        /// The account to insert, with ``Account/groupID`` already set.
        public let account: Account

        /// Creates a starter.
        /// - Parameters:
        ///   - group: The group to insert first, or `nil` to reuse an existing one.
        ///   - account: The account to insert.
        public init(group: AccountGroup?, account: Account) {
            self.group = group
            self.account = account
        }
    }

    /// Decides whether a starter account is owed, and builds it.
    ///
    /// An account that is closed does not count as usable, so closing the last open
    /// account earns a fresh starter rather than leaving the user stranded (§4.7 keeps
    /// the closed one around for its history).
    ///
    /// - Parameters:
    ///   - accounts: Every account, closed ones included.
    ///   - groups: Every existing group, used to avoid minting a second "Cash".
    ///   - now: The opening-balance date to stamp. Defaults to the current time.
    /// - Returns: What to create, or `nil` when at least one open account already exists.
    public static func starter(
        accounts: [Account],
        groups: [AccountGroup],
        now: Date = .now
    ) -> Starter? {
        guard accounts.allSatisfy(\.isClosed) else { return nil }

        let existing = groups.first { $0.name.caseInsensitiveCompare(groupName) == .orderedSame }
        let group = existing ?? AccountGroup(name: groupName, sortIndex: groups.count)
        let account = Account(
            name: accountName,
            kind: .account,
            openingBalanceCents: 0,
            openingBalanceDate: now,
            sortIndex: accounts.filter { $0.groupID == group.id }.count,
            groupID: group.id
        )
        return Starter(group: existing == nil ? group : nil, account: account)
    }
}
