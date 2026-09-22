import Foundation
import Observation
import Domain

/// The editable state behind both account forms (§7.9).
///
/// The inline add form (§7.6) and the Edit Account sheet share this so they validate
/// identically — an edit screen whose Save silently does nothing on invalid input is
/// a defect, not a scope decision (§7.11).
@MainActor
@Observable
public final class AccountFormState {
    /// The account being edited, or `nil` when adding.
    public let existingID: UUID?
    /// The chosen group.
    public var groupID: UUID?

    /// Spending account or credit card.
    ///
    /// Changing this resets ``balanceDirection`` to the default for the new kind, so
    /// switching to Card preselects "Owed" rather than leaving a stale "In hand".
    /// Written out by hand because `@Observable` transforms *stored* properties only.
    public var kind: AccountKind {
        get {
            access(keyPath: \.kind)
            return storedKind
        }
        set {
            withMutation(keyPath: \.kind) { storedKind = newValue }
            balanceDirection = BalanceEntry.defaultDirection(for: newValue)
        }
    }

    /// Backing storage for ``kind``.
    @ObservationIgnored private var storedKind: AccountKind = .account

    /// The account's display name.
    public var name = ""

    /// The typed opening balance, as an unsigned magnitude.
    ///
    /// The field is a `.decimalPad`, which has no minus key: the user types what the
    /// figure *is* and says which side of zero it falls on with ``balanceDirection``.
    public var openingBalanceText = ""

    /// Whether the opening balance is money held or money owed.
    ///
    /// A card is usually owed and a spending account usually held, but neither is a
    /// rule — a card can be in credit after an overpayment and an account can be
    /// overdrawn — so this is the user's to set (§4.1).
    public var balanceDirection: BalanceEntry.Direction = .positive
    /// The date the opening balance applies from.
    public var openingBalanceDate: Date = .now
    /// Day of month the card statement closes.
    public var statementDayOfMonth = 1
    /// Day of month the card payment is due.
    public var paymentDueDayOfMonth = 15
    /// Whether to remind ahead of the due date.
    public var remindBeforeDueDate = true

    /// The typed last four digits of this account's card (§9.7).
    ///
    /// Offered on every kind, not just a card: a chequing account has a debit card, and
    /// a receipt prints those exactly the same way.
    public var last4Text = ""
    /// The payment network that card runs on.
    public var cardNetwork: CardNetwork?

    /// Whether Save has been attempted, which is what reveals validation (§7.11).
    public private(set) var hasAttemptedSave = false

    /// Fields preserved from the account being edited but not shown in the form.
    private let preserved: Domain.Account?

    /// Creates empty state for adding an account.
    /// - Parameter groupID: The group to preselect, if any.
    public init(groupID: UUID? = nil) {
        self.existingID = nil
        self.groupID = groupID
        self.preserved = nil
        self.openingBalanceText = "0.00"
        self.balanceDirection = BalanceEntry.defaultDirection(for: storedKind)
    }

    /// Creates state pre-filled from an existing account.
    /// - Parameter account: The account being edited.
    public init(editing account: Domain.Account) {
        self.existingID = account.id
        self.groupID = account.groupID
        // Straight to the backing store: going through `kind` would reset the direction
        // to the kind's default, overwriting the one this account actually has.
        self.storedKind = account.kind
        self.name = account.name
        self.openingBalanceText = MoneyInput.magnitudeText(fromCents: account.openingBalanceCents)
        self.balanceDirection = BalanceEntry.direction(ofCents: account.openingBalanceCents)
        self.openingBalanceDate = account.openingBalanceDate
        self.statementDayOfMonth = account.statementDayOfMonth ?? 1
        self.paymentDueDayOfMonth = account.paymentDueDayOfMonth ?? 15
        self.remindBeforeDueDate = account.remindBeforeDueDate
        self.last4Text = account.last4 ?? ""
        self.cardNetwork = account.cardNetwork
        self.preserved = account
    }

    // MARK: - Validation (§7.11)

    /// The trimmed account name.
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the opening balance field has been cleared.
    public var isOpeningBalanceBlank: Bool {
        openingBalanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The opening balance in signed cents, or `nil` when the text does not parse.
    ///
    /// A cleared field means zero: someone adding an account mid-signup often does not
    /// know the figure, and "Correct balance" (§4.4) exists to fix it later. Anything
    /// non-empty still has to parse, so a typo is caught rather than saved as zero.
    ///
    /// Do not simplify this to `MoneyInput.magnitudeCents(from:) ?? 0` — that returns
    /// zero for `"abc"` too, silently discarding what the user typed.
    public var openingBalanceCents: Int? {
        guard !isOpeningBalanceBlank else { return 0 }
        guard let magnitude = MoneyInput.magnitudeCents(from: openingBalanceText) else {
            return nil
        }
        return BalanceEntry.signedCents(magnitude: magnitude, direction: balanceDirection)
    }

    /// The name field's error, or `nil` when valid.
    public var nameError: String? {
        guard hasAttemptedSave, trimmedName.isEmpty else { return nil }
        return "Account name is required."
    }

    /// The group field's error, or `nil` when valid.
    public var groupError: String? {
        guard hasAttemptedSave, groupID == nil else { return nil }
        return "Choose a group to continue."
    }

    /// The opening balance field's error, or `nil` when valid.
    public var openingBalanceError: String? {
        guard hasAttemptedSave, openingBalanceCents == nil else { return nil }
        return "Enter an amount like 0.00."
    }

    /// Whether every required field is filled.
    public var isValid: Bool {
        !trimmedName.isEmpty && groupID != nil && openingBalanceCents != nil
    }

    /// Records a Save attempt and builds the account when the form is valid.
    ///
    /// Validation is revealed here rather than on blur or as the user types (§7.11).
    ///
    /// - Parameter sortIndex: The position to give a newly created account.
    /// - Returns: The account to persist, or `nil` when the form is invalid.
    public func commit(sortIndex: Int) -> Domain.Account? {
        hasAttemptedSave = true
        guard isValid, let cents = openingBalanceCents else { return nil }

        var account = preserved ?? Domain.Account(sortIndex: sortIndex)
        account.name = trimmedName
        account.kind = kind
        account.openingBalanceCents = cents
        account.openingBalanceDate = openingBalanceDate
        account.groupID = groupID
        account.statementDayOfMonth = kind == .card ? statementDayOfMonth : nil
        account.paymentDueDayOfMonth = kind == .card ? paymentDueDayOfMonth : nil
        account.remindBeforeDueDate = kind == .card ? remindBeforeDueDate : true
        account.last4 = last4
        account.cardNetwork = cardNetwork
        return account
    }

    /// The card's last four digits, or `nil` when the field does not hold exactly four.
    ///
    /// A partial entry is stored as nothing rather than as itself. These digits exist
    /// only to match a scanned receipt to this account, and half of them would match the
    /// wrong card — or, worse, match one card while the user believes another is set up.
    var last4: String? {
        let digits = last4Text.filter(\.isNumber)
        return digits.count == 4 ? digits : nil
    }
}
