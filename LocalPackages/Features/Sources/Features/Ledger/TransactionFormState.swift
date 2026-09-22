import Foundation
import Observation
import Domain

/// Which mode the transaction form is in (§7.8).
public enum TransactionFormMode: String, CaseIterable, Identifiable, Sendable {
    /// Money out, with an expense category.
    case expense
    /// Money in, with an income category.
    case income
    /// A two-legged move between accounts, with no category.
    case transfer

    /// The case's identity, for `ForEach`.
    public var id: String { rawValue }

    /// The segmented control's label.
    public var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .transfer: return "Transfer"
        }
    }

    /// Which category picker this mode uses, or `nil` in transfer mode.
    public var categoryContext: CategoryContext? {
        switch self {
        case .expense: return .expense
        case .income: return .income
        case .transfer: return nil
        }
    }
}

/// The editable state behind Add and Edit Transaction (§7.8).
///
/// Add and Edit share this so they validate identically — an edit screen whose Save
/// silently does nothing on invalid input is a defect, not a scope decision (§7.11).
@MainActor
@Observable
public final class TransactionFormState {
    /// The transaction being edited, or `nil` when adding.
    public let existingID: UUID?
    /// Whether this form is editing an existing transfer.
    public let isExistingTransfer: Bool

    /// Expense, income or transfer.
    public var mode: TransactionFormMode = .expense
    /// The typed amount, parsed by ``MoneyInput``.
    public var amountText = ""
    /// The chosen category, or `nil` in transfer mode.
    public var categoryID: UUID?
    /// The account money leaves, or the account the entry belongs to.
    public var accountID: UUID?
    /// The account money arrives in, in transfer mode only.
    public var destinationAccountID: UUID?
    /// When the transaction occurred.
    public var date: Date = .now
    /// Merchant or payer name.
    public var merchant = ""
    /// Optional place of purchase.
    public var location = ""
    /// Optional free-text note.
    public var memo = ""
    /// Arbitrary user labels, hidden in transfer mode.
    public var tags: [String] = []
    /// The products this purchase contained (§7.8).
    ///
    /// On Edit these are the stored products, shown for reference and edited through
    /// their own sheet. On Add they are *pending*: the transaction has no identifier
    /// yet, so they are written once it does, by ``LedgerViewModel/save(_:)``.
    public var products: [Domain.Product] = []

    /// Identifier of the attached receipt image, when one is attached (§9.3).
    ///
    /// The receipt belongs to the purchase, not to any one product: one till receipt
    /// can cover several things.
    public var receiptFileID: String?
    /// Original file name of the attached receipt.
    public var receiptFileName: String?
    /// Checksum used to verify the receipt after transfer.
    public var receiptChecksum: String?
    /// Progress of the receipt image toward cloud storage.
    public var receiptUploadState: ReceiptUploadState = .none

    /// Whether this transaction repeats.
    public var isRecurring = false
    /// How often it repeats.
    public var frequency: RecurringFrequency = .monthly
    /// Which end condition, if any, the user chose.
    public var endCondition: RecurringEndCondition = .never
    /// The date the series stops, when ``endCondition`` is ``RecurringEndCondition/onDate``.
    public var endDate: Date = .now
    /// How many occurrences to generate, when the end condition is a count.
    public var occurrenceLimitText = ""

    /// Whether Save has been attempted, which is what reveals validation (§7.11).
    public private(set) var hasAttemptedSave = false

    /// Fields preserved from the transaction being edited but not shown in the form.
    ///
    /// Internal rather than private so the commit builders can read it from their own
    /// file; it is a `let`, so nothing can write it from outside the initialisers.
    let preserved: Domain.Transaction?

    /// The identifier a not-yet-written transaction will be saved under.
    ///
    /// Fixed at form creation rather than at save, so products collected before the
    /// first Save already know which purchase they belong to (§7.8).
    let pendingID = UUID()

    /// How a recurring series ends (§4.5).
    public enum RecurringEndCondition: String, CaseIterable, Identifiable, Sendable {
        /// Runs until deleted.
        case never
        /// Stops on a date.
        case onDate
        /// Stops after a number of occurrences.
        case afterCount

        /// The case's identity, for `ForEach`.
        public var id: String { rawValue }

        /// The picker's label.
        public var title: String {
            switch self {
            case .never: return "Never"
            case .onDate: return "On date"
            case .afterCount: return "After count"
            }
        }
    }

    /// Creates empty state for adding a transaction.
    /// - Parameter accountID: The account to preselect, if any.
    public init(accountID: UUID? = nil) {
        self.existingID = nil
        self.isExistingTransfer = false
        self.accountID = accountID
        self.preserved = nil
    }

    /// Creates state pre-filled from an existing transaction.
    /// - Parameters:
    ///   - transaction: The transaction being edited. For a transfer, pass the
    ///     outflow leg; the destination is taken from `counterpartAccountID`.
    ///   - counterpartAccountID: The other leg's account, for a transfer.
    public init(editing transaction: Domain.Transaction, counterpartAccountID: UUID? = nil) {
        self.existingID = transaction.id
        self.isExistingTransfer = transaction.transferGroupID != nil
        switch transaction.type {
        case .income: self.mode = .income
        case .transferOut, .transferIn: self.mode = .transfer
        case .expense, .adjustment: self.mode = .expense
        }
        self.amountText = MoneyInput.magnitudeText(fromCents: transaction.amountCents)
        self.categoryID = transaction.categoryID
        self.accountID = transaction.accountID
        self.destinationAccountID = counterpartAccountID
        self.date = transaction.date
        self.merchant = transaction.merchant
        self.location = transaction.location ?? ""
        self.memo = transaction.memo ?? ""
        self.tags = transaction.tags
        self.receiptFileID = transaction.receiptFileID
        self.receiptFileName = transaction.receiptFileName
        self.receiptChecksum = transaction.receiptChecksum
        self.receiptUploadState = transaction.receiptUploadState
        self.preserved = transaction
    }

    // MARK: - Validation (§7.11)

    /// The parsed amount, or `nil` when the text does not parse.
    ///
    /// Zero is a real amount, not a failure to type one: something acquired for nothing
    /// is still a purchase, and it is what a product with no cost hangs off (§7.8). It
    /// moves no balance and contributes to no total. A transfer is the exception —
    /// moving nothing between two accounts is never what anyone meant — and is refused
    /// by ``amountError`` instead.
    /// The amount field presents a `.decimalPad`, which has no minus key: which way the
    /// money moves is the mode's business, not the keyboard's.
    ///
    /// A sign can still arrive by paste. It is refused rather than quietly stripped —
    /// unlike a balance field, this form has no direction control to overrule it with,
    /// so silently turning a typed "-5.00" into an outgoing 5.00 would be inventing an
    /// intention the user never expressed.
    public var amountCents: Int? {
        guard let cents = MoneyInput.cents(from: amountText), cents >= 0 else { return nil }
        return cents
    }

    /// The amount field's error, or `nil` when valid.
    public var amountError: String? {
        Self.amountError(text: amountText, mode: mode, hasAttemptedSave: hasAttemptedSave)
    }

    /// The amount rule, as a pure function of the field's own inputs.
    ///
    /// ``AmountField`` renders the error itself — reading it back off the form would
    /// make the whole sheet depend on `amountText` again, which is what made typing an
    /// amount re-evaluate every card on the screen. Both callers share this one
    /// definition so the field cannot show "valid" while Save refuses to commit.
    ///
    /// - Parameters:
    ///   - text: The typed amount.
    ///   - mode: Expense, income or transfer.
    ///   - hasAttemptedSave: Whether validation has been revealed yet (§7.11).
    /// - Returns: The message to show, or `nil` when the amount is acceptable.
    static func amountError(
        text: String,
        mode: TransactionFormMode,
        hasAttemptedSave: Bool
    ) -> String? {
        guard hasAttemptedSave else { return nil }
        guard let cents = MoneyInput.cents(from: text), cents >= 0 else {
            return "Enter an amount to continue."
        }
        guard mode == .transfer, cents == 0 else { return nil }
        return "A transfer needs an amount above zero."
    }

    /// The account field's error, or `nil` when valid.
    public var accountError: String? {
        guard hasAttemptedSave, accountID == nil else { return nil }
        return mode == .transfer ? "Choose a source account." : "Choose an account to continue."
    }

    /// The destination field's error, or `nil` when valid or not in transfer mode.
    public var destinationError: String? {
        guard hasAttemptedSave, mode == .transfer else { return nil }
        guard let destinationAccountID else { return "Choose a destination account." }
        guard destinationAccountID != accountID else { return "Choose a different account." }
        return nil
    }

    /// Whether every required field is filled.
    public var isValid: Bool {
        guard let cents = amountCents, accountID != nil else { return false }
        guard mode == .transfer else { return true }
        guard cents > 0, let destinationAccountID else { return false }
        return destinationAccountID != accountID
    }

    /// The parsed occurrence limit, when that end condition is chosen.
    public var occurrenceLimit: Int? {
        guard isRecurring, endCondition == .afterCount else { return nil }
        guard let value = Int(occurrenceLimitText.trimmingCharacters(in: .whitespaces)),
              value > 0 else { return nil }
        return value
    }

    /// Records a Save attempt and reports whether the form may be committed.
    ///
    /// Validation is revealed here rather than on blur or as the user types (§7.11).
    ///
    /// - Returns: `true` when every required field is filled.
    public func attemptSave() -> Bool {
        hasAttemptedSave = true
        return isValid
    }

    /// Converts blank text to `nil` for optional string fields.
    /// - Parameter text: The text to normalise.
    /// - Returns: The trimmed text, or `nil` when it is empty.
    func emptyToNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
