import AppIntents
import Foundation
import UniformTypeIdentifiers
import Domain

/// Records money arriving, without opening the app (§15.2).
///
/// The mirror of ``AddExpenseIntent``, and deliberately thin: every decision it makes is
/// ``QuickEntryIntent``'s, so the two cannot drift apart. What differs is
/// ``QuickEntryIntent/entryType-swift.type.property`` — which decides the sign, since
/// `amountCents` is always a magnitude (§2) — the categories it may file under, and the
/// words. There is no receipt parameter: a receipt is something a shop hands you.
struct LogIncomeIntent: QuickEntryIntent {
    /// The action's name in Siri and the Shortcuts editor.
    static let title: LocalizedStringResource = "Log Income"

    /// What the action does, for the Shortcuts editor.
    static var description: IntentDescription? {
        IntentDescription(
            "Records money arriving in one of your accounts.",
            categoryName: "Ledger",
            searchKeywords: ["income", "paid", "salary", "refund", "deposit", "log"]
        )
    }

    /// Money arriving in an account.
    static let entryType: Domain.TransactionType = .income

    /// Income is filed under the income categories, which are their own short list (§4.8).
    static let categoryContext: CategoryContext = .income

    /// Stays in the background: the point is not opening the app.
    static let openAppWhenRun = false

    /// Runs without proving who is holding the phone (§15.3).
    ///
    /// Same reasoning as ``AddExpenseIntent``: recording income discloses nothing. It is
    /// reading a figure back that the §11 lock exists to prevent.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    /// How the action reads in the editor once its parameters are filled.
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) from \(\.$merchant) into \(\.$account)") {
            \.$accountNumber
            \.$accountName
            \.$category
            \.$date
            \.$tags
            \.$location
            \.$memo
            \.$rememberCategory
            \.$allowsDuplicate
        }
    }

    /// How much arrived, in the app's single currency.
    @Parameter(title: "Amount", requestValueDialog: "How much did you receive?")
    var amount: Double

    /// Who it came from.
    @Parameter(title: "From", requestValueDialog: "Who was it from?")
    var merchant: String

    /// The category, as free text.
    @Parameter(title: "Category")
    var category: String?

    /// The account it arrived in.
    @Parameter(title: "Account")
    var account: AccountEntity?

    /// The account number it arrived in, as text.
    @Parameter(title: "Account Number")
    var accountNumber: String?

    /// The account's name, as text.
    @Parameter(title: "Account Name")
    var accountName: String?

    /// When it arrived. Defaults to now.
    @Parameter(title: "Date")
    var date: Date?

    /// User labels. The `shortcut` tag is added on top of these.
    @Parameter(title: "Tags")
    var tags: [String]?

    /// Where it came from.
    @Parameter(title: "Location")
    var location: String?

    /// A free-text note.
    @Parameter(title: "Notes")
    var memo: String?

    /// Whether to file this payer under the same category next time.
    @Parameter(title: "Remember category for this payer", default: true)
    var rememberCategory: Bool

    /// Whether to record this even when an identical entry was logged moments ago.
    @Parameter(title: "Allow duplicate", default: false)
    var allowsDuplicate: Bool

    /// Income carries no receipt: a receipt is something a shop hands you.
    var receipts: [IntentFile]? { nil }

    /// Records the income.
    /// - Returns: The entry, and a short confirmation of what was written.
    /// - Throws: ``QuickEntryError`` when the amount, payer or category cannot be used, or a
    ///   persistence error if a write fails.
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
