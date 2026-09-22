import Foundation
import Testing
@testable import Domain
@testable import Features

/// Money is entered as an unsigned magnitude plus a direction (§4.1, §7.9).
///
/// The balance fields present a `.decimalPad`, which has no minus key, so nothing here
/// can be expressed by typing a sign. These pin the rule that decides it instead —
/// including the case that matters most: a card balance must still be stored negative.
@MainActor
@Suite("Account balance entry")
struct AccountBalanceEntryTests {

    @Test("A card balance entered as a magnitude is stored negative")
    func cardBalanceIsStoredNegative() {
        let form = AccountFormState(groupID: UUID())
        form.kind = .card
        form.name = "Visa"
        form.openingBalanceText = "1234.56"

        #expect(form.balanceDirection == .negative, "a card defaults to money owed")
        #expect(form.openingBalanceCents == -123_456)
        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == -123_456)
    }

    @Test("A spending account balance entered as a magnitude is stored positive")
    func accountBalanceIsStoredPositive() {
        let form = AccountFormState(groupID: UUID())
        form.name = "Chequing"
        form.openingBalanceText = "1234.56"

        #expect(form.balanceDirection == .positive)
        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == 123_456)
    }

    @Test("A card in credit is expressible without typing a sign")
    func cardCanBeInCredit() {
        let form = AccountFormState(groupID: UUID())
        form.kind = .card
        form.name = "Visa"
        form.balanceDirection = .positive
        form.openingBalanceText = "50.00"

        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == 5_000)
    }

    @Test("A spending account can be overdrawn without typing a sign")
    func accountCanBeOverdrawn() {
        let form = AccountFormState(groupID: UUID())
        form.name = "Chequing"
        form.balanceDirection = .negative
        form.openingBalanceText = "50.00"

        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == -5_000)
    }

    @Test("Switching to Card preselects owed, and back to Account preselects in hand")
    func directionFollowsTheKind() {
        let form = AccountFormState(groupID: UUID())
        #expect(form.balanceDirection == .positive)

        form.kind = .card
        #expect(form.balanceDirection == .negative)

        form.kind = .account
        #expect(form.balanceDirection == .positive)
    }

    @Test("Editing a card seeds the magnitude and direction it already has")
    func editingSeedsFromTheStoredBalance() {
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: -123_456, groupID: UUID()
        )
        let form = AccountFormState(editing: card)

        #expect(form.kind == .card)
        #expect(form.openingBalanceText == "1234.56", "the field shows no sign")
        #expect(form.balanceDirection == .negative)
        // Round-trips untouched: opening an edit screen and saving must not flip a sign.
        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == -123_456)
    }

    @Test("Editing a card that is in credit keeps it in credit")
    func editingACreditCardKeepsItsDirection() {
        let card = Domain.Account(
            name: "Visa", kind: .card, openingBalanceCents: 5_000, groupID: UUID()
        )
        let form = AccountFormState(editing: card)

        #expect(form.balanceDirection == .positive, "the stored sign wins over the kind default")
        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == 5_000)
    }

    @Test("A blank balance is zero, but an unparsable one is still refused")
    func blankIsZeroAndGarbageIsRefused() {
        let form = AccountFormState(groupID: UUID())
        form.name = "Chequing"
        form.openingBalanceText = ""
        #expect(form.openingBalanceCents == 0)

        form.openingBalanceText = "abc"
        #expect(form.openingBalanceCents == nil)
        #expect(form.commit(sortIndex: 0) == nil)
    }

    @Test("A zero balance is never stored as negative zero, whatever the direction")
    func zeroIsUnsigned() {
        let form = AccountFormState(groupID: UUID())
        form.kind = .card
        form.name = "Visa"
        form.openingBalanceText = "0.00"

        #expect(form.balanceDirection == .negative)
        #expect(form.commit(sortIndex: 0)?.openingBalanceCents == 0)
    }
}

/// The transaction amount is a magnitude too; its sign comes from the mode (§7.8).
@MainActor
@Suite("Transaction amount entry")
struct TransactionAmountEntryTests {

    @Test("The field and Save agree on what is valid", arguments: [
        "50.00", "-50.00", "\u{2212}50.00", "", "abc"
    ])
    func fieldAndSaveAgree(text: String) {
        // These are derived in two places — the form for Save, the field for its own
        // caption — and they must never disagree. A field reading "valid" while Save
        // silently does nothing is the defect §7.11 exists to prevent.
        let form = TransactionFormState(accountID: UUID())
        form.amountText = text
        _ = form.attemptSave()

        let fieldError = TransactionFormState.amountError(
            text: text, mode: form.mode, hasAttemptedSave: true
        )
        #expect(form.amountError == fieldError)
    }

    @Test("A pasted sign is refused rather than silently flipped")
    func pastedSignIsRefused() {
        // The decimal pad cannot type one, so a sign here arrived by paste. There is no
        // direction control on this form to overrule it with, so it is an error rather
        // than something to reinterpret.
        let form = TransactionFormState(accountID: UUID())
        form.amountText = "-50.00"

        #expect(form.attemptSave() == false)
        #expect(form.amountCents == nil)
        #expect(form.amountError == "Enter an amount to continue.")
    }

    @Test("A zero amount is a real amount, but never for a transfer")
    func zeroIsOnlyValidOffTransfer() {
        let expense = TransactionFormState(accountID: UUID())
        expense.amountText = "0"
        #expect(expense.attemptSave())
        #expect(expense.amountError == nil)

        let transfer = TransactionFormState(accountID: UUID())
        transfer.mode = .transfer
        transfer.amountText = "0"
        transfer.destinationAccountID = UUID()
        #expect(transfer.attemptSave() == false)
        #expect(transfer.amountError == "A transfer needs an amount above zero.")
    }

    @Test("Editing seeds the field unsigned, since a decimal pad cannot retype a sign")
    func editingSeedsUnsigned() {
        let transaction = Domain.Transaction(
            amountCents: 4_250, type: .expense, accountID: UUID(), date: .now, merchant: "Shop"
        )
        let form = TransactionFormState(editing: transaction)
        #expect(form.amountText == "42.50")
        #expect(form.amountCents == 4_250)
    }

    @Test("Validation stays hidden until Save is attempted")
    func validationHiddenBeforeSave() {
        let form = TransactionFormState(accountID: UUID())
        form.amountText = ""
        #expect(form.amountError == nil)
        #expect(form.attemptSave() == false)
        #expect(form.amountError == "Enter an amount to continue.")
    }
}
