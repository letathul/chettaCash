import Foundation
import Testing
@testable import Domain

/// The rule that keeps at least one usable account in the app (§7.10).
@Suite("Starter account policy")
struct StarterAccountPolicyTests {

    @Test("A user with no accounts at all is owed a starter")
    func starterWhenEmpty() {
        let starter = StarterAccountPolicy.starter(accounts: [], groups: [])

        #expect(starter != nil)
        #expect(starter?.account.name == "Cash")
        #expect(starter?.group?.name == "Cash")
    }

    @Test("One open account is enough, so no starter is owed")
    func noStarterWhenAnOpenAccountExists() {
        let existing = Account(name: "Chequing")

        let starter = StarterAccountPolicy.starter(accounts: [existing], groups: [])

        #expect(starter == nil)
    }

    @Test("A closed account is not usable, so closing the last one earns a starter")
    func starterWhenOnlyAccountIsClosed() {
        let closed = AccountLifecycle.closed(Account(name: "Old Chequing"))

        let starter = StarterAccountPolicy.starter(accounts: [closed], groups: [])

        #expect(starter != nil)
    }

    @Test("An existing Cash group is reused rather than duplicated, whatever its casing")
    func reusesExistingCashGroup() {
        let existing = AccountGroup(name: "cash", sortIndex: 0)

        let starter = StarterAccountPolicy.starter(accounts: [], groups: [existing])

        #expect(starter?.group == nil, "no second group is minted")
        #expect(starter?.account.groupID == existing.id)
    }

    @Test("Asking again after acting returns nothing, so callers are idempotent")
    func isIdempotent() {
        guard let first = StarterAccountPolicy.starter(accounts: [], groups: []) else {
            Issue.record("the first call should owe a starter")
            return
        }
        let groups = first.group.map { [$0] } ?? []

        let second = StarterAccountPolicy.starter(accounts: [first.account], groups: groups)

        #expect(second == nil)
    }

    @Test("The starter is a zero-balance spending account filed under its group")
    func starterShape() {
        let starter = StarterAccountPolicy.starter(accounts: [], groups: [])

        #expect(starter?.account.kind == .account)
        #expect(starter?.account.openingBalanceCents == 0)
        #expect(starter?.account.cachedBalanceCents == 0)
        #expect(starter?.account.isClosed == false)
        #expect(starter?.account.groupID == starter?.group?.id)
    }
}
