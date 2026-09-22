import AppIntents
import Foundation
import UniformTypeIdentifiers
import Domain

/// Logs an expense without opening the app (§15).
///
/// Runs in the app's process with no window, so everything it needs is a parameter or
/// already in the database. It writes and reports what it wrote; it never reads a
/// balance back, because a write reveals nothing to whoever is holding a locked phone
/// while a spoken balance reveals everything (§15.3, §13.1.9).
///
/// It does not refuse for want of an account. An entry whose account cannot be settled is
/// still written, parked, and handed to the Today card (§15.5) — losing what the user said
/// is worse than admitting the app does not know where to file it.
///
/// Only ``perform()`` is main-actor isolated, not the whole type: `AppIntent`'s static
/// requirements are read by the system off the main actor, so isolating the conformance
/// itself does not compile under strict concurrency.
struct AddExpenseIntent: QuickEntryIntent {
    /// The action's name in Siri and the Shortcuts editor.
    static let title: LocalizedStringResource = "Add Expense"

    /// What the action does, for the Shortcuts editor.
    static var description: IntentDescription? {
        IntentDescription(
            "Records an expense against one of your accounts.",
            categoryName: "Ledger",
            searchKeywords: ["expense", "spend", "transaction", "log", "receipt"]
        )
    }

    /// Money leaving an account.
    static let entryType: Domain.TransactionType = .expense

    /// Expenses are filed under the expense categories.
    static let categoryContext: CategoryContext = .expense

    /// Stays in the background: the point is not opening the app.
    static let openAppWhenRun = false

    /// Runs without proving who is holding the phone (§15.3).
    ///
    /// Stated explicitly rather than left to the framework default, because it looks like an
    /// oversight otherwise and the next reader will want to "fix" it. Recording an expense
    /// discloses nothing: someone holding a locked phone who logs a four pound coffee learns
    /// nothing they did not already know, and has made a mess the owner can delete. What the
    /// lock actually protects is reading — account names, card digits, balances — and that is
    /// withheld in ``AccountEntityQuery`` instead, where the disclosure would happen.
    ///
    /// `.requiresLocalDeviceAuthentication` would fire Face ID on every run, which is the
    /// whole feature gone. Any intent that *reads* a figure must use it regardless
    /// (§13.1.9).
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    /// How the action reads in the editor once its parameters are filled.
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) expense for \(\.$merchant) to \(\.$account)") {
            \.$accountNumber
            \.$accountName
            \.$category
            \.$date
            \.$tags
            \.$receipts
            \.$location
            \.$memo
            \.$rememberCategory
            \.$allowsDuplicate
        }
    }

    /// How much was spent, in the app's single currency.
    ///
    /// A plain number rather than a currency amount, deliberately. Chetta Cash renders
    /// every figure in one currency and converts nothing (§5.1), so a currency picker
    /// in the Shortcuts editor would offer a choice the app cannot honour — and an
    /// amount picked as EUR would land in the ledger as the same number of dollars.
    @Parameter(title: "Amount", requestValueDialog: "How much did you spend?")
    var amount: Double

    /// Who it was spent with.
    @Parameter(title: "Merchant", requestValueDialog: "Where did you spend it?")
    var merchant: String

    /// The category, as free text.
    ///
    /// Free text rather than a picker because a Shortcut is often built before the
    /// category exists. A pinned merchant overrules whatever is passed here.
    @Parameter(title: "Category")
    var category: String?

    /// The account the expense is recorded against.
    ///
    /// Optional because ``accountNumber`` can name the account instead, and often must: a
    /// Shortcut's picker is frozen at the moment the Shortcut was built, so it cannot name a
    /// card acquired since. When neither is set, ``perform()`` asks for one — and the
    /// identifier a picker did supply is checked against the accounts that exist rather than
    /// trusted, because it may have been closed or replaced since it was chosen.
    @Parameter(title: "Account")
    var account: AccountEntity?

    /// The account number this expense was paid with, as text.
    ///
    /// Free text rather than a picker because the whole point is a number that arrives with
    /// the entry — off a bank notification or a parsed message — rather than one chosen when
    /// the Shortcut was written. Only the last four digits are read, and only those are ever
    /// stored (§9.7); a full number passed here is reduced before it reaches the database.
    ///
    /// Outranks ``account`` when both are given.
    @Parameter(title: "Account Number")
    var accountNumber: String?

    /// The account's name, as text.
    ///
    /// The text alternative to ``account``, for the same reason ``accountNumber`` is: a name
    /// can arrive with the entry — a Wallet pass's name, say — where the picker is frozen at
    /// the moment the Shortcut was built. Matched case- and accent-insensitively, and by
    /// containment when exactly one account could be meant.
    ///
    /// A name reaching no account, or several, parks the entry rather than guessing or
    /// minting a card from what may be a typo (§15.4). ``accountNumber`` outranks this when
    /// both are given, because four digits identify one card exactly where a name is only
    /// what someone calls it — but the name is still used to christen whatever the number
    /// creates.
    @Parameter(title: "Account Name")
    var accountName: String?

    /// When it happened. Defaults to now.
    @Parameter(title: "Date")
    var date: Date?

    /// User labels. The `shortcut` tag is added on top of these.
    @Parameter(title: "Tags")
    var tags: [String]?

    /// Receipt images or PDFs. Several files are the pages of one receipt (§9.3).
    @Parameter(title: "Receipts", supportedContentTypes: [.image, .pdf])
    var receipts: [IntentFile]?

    /// Where it happened.
    @Parameter(title: "Location")
    var location: String?

    /// A free-text note.
    @Parameter(title: "Notes")
    var memo: String?

    /// Whether to file this merchant under the same category next time.
    @Parameter(title: "Remember category for this merchant", default: true)
    var rememberCategory: Bool

    /// Whether to record this even when an identical entry was logged moments ago.
    ///
    /// Off by default, because a Siri retry and an automation firing twice are both far more
    /// common than buying the same thing twice at the same shop inside two minutes (§15.6).
    /// On for the person who really did.
    @Parameter(title: "Allow duplicate", default: false)
    var allowsDuplicate: Bool

    /// Records the expense.
    ///
    /// Everything here is ``QuickEntryIntent``'s, which Log Income shares: the same account
    /// resolution, planner, duplicate guard and single-commit write. What this type supplies
    /// is the parameters and ``entryType``.
    ///
    /// Returns the entry as well as saying what happened, so a Shortcut can carry on with
    /// it. A run recognised as a repeat (§15.6) hands back the entry that already exists
    /// rather than nothing, which is what makes a retry idempotent instead of merely quiet.
    ///
    /// - Returns: The entry, and a short confirmation of what was written.
    /// - Throws: ``QuickEntryError`` when the amount, merchant or category cannot be used, or
    ///   a persistence error if a write fails.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TransactionEntity>
        & ProvidesDialog {
        let outcome = try await record()
        return .result(value: outcome.entity, dialog: outcome.dialog)
    }

    /// Asks which account, through this intent's own picker.
    /// - Returns: The chosen account, or `nil` when the user gave none.
    /// - Throws: The framework's own request, so it can present the picker.
    @MainActor
    func requestAccount() async throws -> AccountEntity? {
        try await $account.requestValue("Which account?")
    }
}
