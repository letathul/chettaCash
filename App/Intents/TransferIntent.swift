import AppIntents
import Foundation
import Domain

/// Moves money between two accounts, without opening the app (§15.2, §4.3).
///
/// The one intent that does **not** park on doubt. A parked expense is an entry whose account
/// the user can supply later; a transfer with one end missing is not an entry at all — there
/// is nothing to hold and nothing the Today card could ask. So this refuses, and says which
/// end it could not work out.
///
/// The two legs come from ``TransferFactory`` and are written by
/// ``TransactionRepository/saveTransfer(outLeg:inLeg:)``, which commits both at once. A
/// half-transfer must never exist in the database (§4.3), and going through anything else
/// here would be the way to create one.
struct TransferIntent: AppIntent {
    /// The action's name in Siri and the Shortcuts editor.
    static let title: LocalizedStringResource = "Transfer Money"

    /// What the action does, for the Shortcuts editor.
    static var description: IntentDescription? {
        IntentDescription(
            "Moves money from one of your accounts to another. Paying a card is a transfer.",
            categoryName: "Ledger",
            searchKeywords: ["transfer", "move", "pay", "card payment", "between accounts"]
        )
    }

    /// Stays in the background: the point is not opening the app.
    static let openAppWhenRun = false

    /// Runs without proving who is holding the phone (§15.3).
    ///
    /// A transfer moves money the user already had between accounts they already own. It
    /// creates no obligation and discloses no figure, so the reasoning is the same as for
    /// ``AddExpenseIntent``.
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    /// How the action reads in the editor once its parameters are filled.
    static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$amount) from \(\.$source) to \(\.$destination)") {
            \.$date
            \.$memo
        }
    }

    /// How much to move, in the app's single currency.
    ///
    /// Zero is refused here, unlike an expense. A free item is still a purchase worth
    /// recording; a transfer of nothing is two rows describing an event that did not happen.
    @Parameter(title: "Amount", requestValueDialog: "How much are you moving?")
    var amount: Double

    /// The account money leaves.
    @Parameter(title: "From", requestValueDialog: "Which account is it coming from?")
    var source: AccountEntity

    /// The account money arrives in.
    ///
    /// Paying a credit card is this: a `transferIn` on the card, which moves its balance
    /// toward zero and counts toward no spending total (§4.3).
    @Parameter(title: "To", requestValueDialog: "Which account is it going to?")
    var destination: AccountEntity

    /// When it happened. Defaults to now.
    @Parameter(title: "Date")
    var date: Date?

    /// A free-text note carried by both legs.
    @Parameter(title: "Notes")
    var memo: String?

    /// Moves the money.
    /// - Returns: A short confirmation of what was moved.
    /// - Throws: ``TransferIntentError`` when the accounts or the amount cannot be used, or a
    ///   persistence error if the write fails.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dependencies = try await AppEnvironment.shared()
        guard let amountCents = MoneyInput.cents(fromAmount: amount) else {
            throw TransferIntentError.unusableAmount
        }
        let accounts = try await dependencies.accounts.accounts(includeClosed: true)
        let from = try resolved(source, in: accounts, end: .source)
        let into = try resolved(destination, in: accounts, end: .destination)

        let legs: (out: Domain.Transaction, in: Domain.Transaction)
        do {
            legs = try TransferFactory.makeLegs(
                amountCents: amountCents,
                date: date ?? .now,
                sourceAccountID: from.id,
                destinationAccountID: into.id,
                memo: memo
            )
        } catch let problem as TransferError {
            throw TransferIntentError(problem)
        }

        try await dependencies.transactions.saveTransfer(outLeg: legs.out, inLeg: legs.in)
        NotificationCenter.default.post(name: .chettaCashDataDidChange, object: nil)

        let formatted = CurrencyFormatter.string(
            fromCents: amountCents, currencyCode: dependencies.settings.currencyCode
        )
        return .result(dialog: IntentDialog(stringLiteral:
            "Moved \(formatted) from \(from.name) to \(into.name)."
        ))
    }

    /// Checks that one end of the transfer is an account money may still move through.
    ///
    /// The identifier a saved Shortcut holds proves nothing on its own — the account may
    /// have been closed since, or replaced by a restored backup. Unlike an expense this
    /// cannot be parked, so it is refused by name.
    ///
    /// - Parameters:
    ///   - picked: The account chosen in the editor.
    ///   - accounts: Every account, closed ones included.
    ///   - end: Which end of the transfer this is, for the spoken refusal.
    /// - Returns: The account.
    /// - Throws: ``TransferIntentError`` when it is gone or closed.
    @MainActor
    private func resolved(
        _ picked: AccountEntity,
        in accounts: [Domain.Account],
        end: TransferEnd
    ) throws -> Domain.Account {
        guard let account = accounts.first(where: { $0.id == picked.id }) else {
            throw TransferIntentError.unknownAccount(end)
        }
        guard !account.isClosed else { throw TransferIntentError.closedAccount(end) }
        return account
    }
}

/// Which end of a transfer a refusal is about.
enum TransferEnd: Sendable {
    /// The account money leaves.
    case source
    /// The account money arrives in.
    case destination

    /// How the end is named in a spoken refusal.
    var spokenName: String {
        switch self {
        case .source: return "the account it's coming from"
        case .destination: return "the account it's going to"
        }
    }
}

/// Why a transfer could not be recorded.
enum TransferIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The amount was negative, or too large to represent.
    case unusableAmount
    /// The amount was zero, which is two rows describing nothing.
    case zeroAmount
    /// Source and destination were the same account (§4.3).
    case sameAccount
    /// One end is no longer in the app.
    case unknownAccount(TransferEnd)
    /// One end has been closed, and closed accounts take no new money (§4.7).
    case closedAccount(TransferEnd)

    /// Translates a factory refusal into what Siri says.
    /// - Parameter problem: What the factory refused to build.
    init(_ problem: TransferError) {
        switch problem {
        case .nonPositiveAmount: self = .zeroAmount
        case .sameAccount: self = .sameAccount
        }
    }

    /// What Siri says when the action fails.
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unusableAmount:
            return "That amount can't be moved. Enter a positive amount."
        case .zeroAmount:
            return "Enter an amount above zero to move."
        case .sameAccount:
            return "Choose two different accounts."
        case .unknownAccount(let end):
            return "\(end.spokenName) is no longer in Chetta Cash."
        case .closedAccount(let end):
            return "\(end.spokenName) is closed."
        }
    }
}
