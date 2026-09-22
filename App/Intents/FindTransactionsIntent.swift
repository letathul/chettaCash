import AppIntents
import Foundation
import UIKit
import Domain

/// Lists entries from the ledger (§15.2, §15.3).
///
/// The only **read** on this path, and the only intent that needs the device unlocked. A
/// write discloses nothing; this hands back amounts, merchants and dates, which is precisely
/// what the §11 lock exists to keep from whoever picks the phone up.
///
/// It does not report a total. A spoken figure is the thing §13.1.9 decided against, and a
/// sum is a figure however it is arrived at — a Shortcut that wants one can add these up
/// itself, in a context the user chose.
struct FindTransactionsIntent: AppIntent {
    /// The action's name in Siri and the Shortcuts editor.
    static let title: LocalizedStringResource = "Find Transactions"

    /// What the action does, for the Shortcuts editor.
    static var description: IntentDescription? {
        IntentDescription(
            "Finds transactions between two dates, optionally from one account.",
            categoryName: "Ledger",
            searchKeywords: ["find", "search", "list", "transactions", "history"]
        )
    }

    /// Stays in the background: the point is not opening the app.
    static let openAppWhenRun = false

    /// The device must be unlocked (§15.3).
    ///
    /// `.requiresAuthentication` rather than `.alwaysAllowed`, which every write on this path
    /// uses. The asymmetry is the whole rule: a write reveals nothing, a read reveals
    /// everything. Not `.requiresLocalDeviceAuthentication` — that prompts for Face ID on
    /// every run, and an unlocked phone has already answered the question.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    /// How the action reads in the editor once its parameters are filled.
    static var parameterSummary: some ParameterSummary {
        Summary("Find transactions from \(\.$from) until \(\.$until)") {
            \.$account
            \.$tag
            \.$limit
        }
    }

    /// The earliest date to include.
    @Parameter(title: "From", requestValueDialog: "From which date?")
    var from: Date

    /// The latest date to include.
    @Parameter(title: "Until", requestValueDialog: "Up to which date?")
    var until: Date

    /// Restrict to one account, or leave empty for all of them.
    @Parameter(title: "Account")
    var account: AccountEntity?

    /// Restrict to entries carrying this tag.
    ///
    /// Matched case-insensitively, the same way the tag field itself works. `shortcut` finds
    /// everything ever logged from a Shortcut (§15.6).
    @Parameter(title: "Tag")
    var tag: String?

    /// The most entries to return.
    @Parameter(title: "Limit", default: 50, inclusiveRange: (1, 500))
    var limit: Int

    /// Finds the entries.
    /// - Returns: The matching entries, newest first.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TransactionEntity]> {
        let dependencies = try await AppEnvironment.shared()
        guard !ShortcutPrivacyPolicy.hidesStoredData(
            lockEnabled: dependencies.settings.appLockEnabled,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        ) else { return .result(value: []) }

        // Tolerated rather than refused: a Shortcut that computes its own dates can easily
        // hand them over the wrong way round, and the user meant the range between them.
        let range = min(from, until)...max(from, until)
        let stored = try await dependencies.transactions.transactions(accountID: nil, in: range)

        let matches = stored
            .filter { account == nil || $0.accountID == account?.id }
            .filter { matchesTag($0) }
            .prefix(limit)

        return .result(
            value: try await TransactionEntityBuilder(dependencies: dependencies)
                .entities(for: Array(matches))
        )
    }

    /// Whether an entry carries the tag that was asked for.
    /// - Parameter transaction: The entry to check.
    /// - Returns: Whether it matches, or `true` when no tag was given.
    private func matchesTag(_ transaction: Domain.Transaction) -> Bool {
        guard let wanted = tag?.trimmingCharacters(in: .whitespacesAndNewlines),
              !wanted.isEmpty else { return true }
        return transaction.tags.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
    }
}
