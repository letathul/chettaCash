import AppIntents

/// The actions the system offers without the user building anything (§15.2).
///
/// An `AppShortcutsProvider` is what makes the install-time suggestion work: iOS reads
/// these at install and lists them in Spotlight, Siri and the Shortcuts app straight
/// away. Nothing is donated and nothing is set up — the action is simply there.
///
/// Every phrase must contain `\(.applicationName)`; the build fails otherwise.
struct ChettaCashShortcuts: AppShortcutsProvider {
    /// The actions to surface.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense to \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Add a \(.applicationName) expense",
                "Record spending in \(.applicationName)",
                "Add a \(.applicationName) expense to \(\.$account)",
                "Record \(.applicationName) spending on \(\.$account)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "plus.circle",
            parameterPresentation: ParameterPresentation(
                for: \.$account,
                summary: Summary("Add an expense to \(\.$account)"),
                optionsCollections: {
                    OptionsCollection(AccountEntityQuery(), title: "Accounts")
                }
            )
        )
        AppShortcut(
            intent: LogIncomeIntent(),
            phrases: [
                "Log income in \(.applicationName)",
                "Record income in \(.applicationName)",
                "Add income to \(.applicationName)"
            ],
            shortTitle: "Log Income",
            systemImageName: "arrow.down.circle"
        )
    }
}
