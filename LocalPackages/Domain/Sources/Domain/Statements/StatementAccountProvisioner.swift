import Foundation

/// Which card a statement belongs to, and whether one can safely be created for it.
public enum StatementAccountMatch: Sendable, Equatable {
    /// Exactly one account matches; import against it.
    case matched(UUID)
    /// Several accounts match. The user must choose — never auto-create.
    case ambiguous([UUID])
    /// Digits were printed and no account has them. This card is safe to create.
    case unknown(Account)
    /// Nothing identified a card at all, so there is nothing to look up or create.
    case indeterminate
}

/// Finds the card a statement belongs to, creating one only when that cannot be wrong (§9.7).
///
/// **Why this exists rather than a call to ``AccountMatcher/match(_:in:)``.** That returns
/// `nil` both when no account matches and when several do, which is the right answer for
/// pre-filling a form but the wrong one here: auto-creating a card in the *ambiguous* case
/// would add a third card beside two the user already has, which is precisely the
/// wrong-balance mistake the matcher was written to prevent. The two causes are separated
/// here using the matcher's own ``AccountMatcher/candidates(_:in:)``, so the rules for what
/// counts as a match are stated once.
public enum StatementAccountProvisioner {

    /// Resolves a statement's card.
    /// - Parameters:
    ///   - tender: The digits and network read off the statement.
    ///   - accounts: The accounts to match against.
    ///   - groupID: The group a created card would join.
    ///   - sortIndex: The ordering position a created card would take.
    ///   - openingDate: The date a created card's zero opening balance applies from.
    /// - Returns: What was found, and a card to create when creating one is safe.
    public static func resolve(
        _ tender: ReceiptTender,
        in accounts: [Account],
        groupID: UUID? = nil,
        sortIndex: Int = 0,
        openingDate: Date = .now
    ) -> StatementAccountMatch {
        let candidates = AccountMatcher.candidates(tender, in: accounts)

        if candidates.count == 1, let only = candidates.first {
            return .matched(only.id)
        }
        if candidates.count > 1 {
            return .ambiguous(candidates.map(\.id))
        }
        // No candidate. Only digits justify creating a card: a bare network name says the
        // user paid with *a* Visa, not which one, and a card invented from that would
        // collect charges that belong to a card they already have.
        guard let last4 = tender.last4, !last4.isEmpty else { return .indeterminate }
        return .unknown(
            makeCard(
                last4: last4, network: tender.network, groupID: groupID,
                sortIndex: sortIndex, openingDate: openingDate
            )
        )
    }

    /// Builds the card to offer when a statement names one the user has not set up.
    ///
    /// The opening balance is zero, and safe to be: ``BalanceEngine`` derives a card's
    /// balance from the opening figure plus every posted transaction, so the imported
    /// charges alone produce the right balance and no phantom money is invented (§4.1).
    ///
    /// - Parameters:
    ///   - last4: The card's last four digits.
    ///   - network: The network it runs on, if the statement named one.
    ///   - groupID: The group it joins.
    ///   - sortIndex: Its ordering position.
    ///   - openingDate: The date its zero opening balance applies from.
    /// - Returns: The card.
    public static func makeCard(
        last4: String,
        network: CardNetwork? = nil,
        groupID: UUID? = nil,
        sortIndex: Int = 0,
        openingDate: Date = .now
    ) -> Account {
        Account(
            name: network.map { "\($0.displayName) ••\(last4)" } ?? "Card ••\(last4)",
            kind: .card,
            openingBalanceCents: 0,
            openingBalanceDate: openingDate,
            sortIndex: sortIndex,
            groupID: groupID,
            last4: last4,
            cardNetwork: network
        )
    }
}
