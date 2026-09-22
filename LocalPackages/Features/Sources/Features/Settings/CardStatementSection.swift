import SwiftUI
import Domain

/// A card's statement figures on the Edit Account sheet (§4.6).
///
/// Both figures are shown: the **current balance**, which includes charges made
/// after the period closed, and the **statement balance**, which is what is actually
/// due on the due date.
struct CardStatementSection: View {
    /// The card being shown.
    let account: Domain.Account
    /// The card's statements, newest first.
    let summaries: [StatementSummary]
    /// The card's balance right now, in cents, negative when owed.
    let currentBalanceCents: Int
    /// The display currency.
    let currencyCode: String
    /// Records or dismisses the interest-and-fees prompt.
    let onResolveInterest: (Domain.CardStatement, Int?) -> Void
    /// Overrides a statement's balance.
    let onOverride: (Domain.CardStatement, Int?) -> Void

    /// The statement whose override is being edited.
    @State private var overridingStatement: Domain.CardStatement?

    /// The statement that is actually due — the newest closed one.
    ///
    /// Earlier statements are superseded rather than separately payable, so only
    /// this one is shown (§4.6).
    private var dueStatement: StatementSummary? {
        summaries.first { $0.statement.isPeriodClosed }
    }

    /// The newest closed statement awaiting an interest answer.
    private var promptingStatement: Domain.CardStatement? {
        summaries.map(\.statement).first { InterestPrompt.shouldAsk(about: $0) }
    }

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statements").sectionLabel()
            if let promptingStatement {
                InterestPromptCard(
                    accountName: account.name,
                    statement: promptingStatement,
                    currencyCode: currencyCode,
                    onResolve: onResolveInterest
                )
            }
            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    balanceRow(
                        "Current balance",
                        cents: max(0, -currentBalanceCents),
                        caption: "Everything owed right now, including charges since closing."
                    )
                    if let latest = dueStatement {
                        Divider().overlay(Palette.borderSubtle)
                        statementRow(latest)
                    } else {
                        Divider().overlay(Palette.borderSubtle)
                        Text("No statement has closed yet.")
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .sheet(item: $overridingStatement) { statement in
            StatementOverrideSheet(
                statement: statement,
                currencyCode: currencyCode,
                onSave: { cents in onOverride(statement, cents) }
            )
        }
    }

    /// A labelled money row with an explanatory caption.
    /// - Parameters:
    ///   - label: The row's label.
    ///   - cents: The amount owed.
    ///   - caption: What the figure means.
    /// - Returns: The row view.
    private func balanceRow(_ label: String, cents: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(money(cents))
                    .moneyText(Typography.rowPrimary)
                    .foregroundStyle(cents > 0 ? Palette.negativeRed : Palette.textPrimary)
            }
            Text(caption)
                .font(Typography.errorCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// The latest statement's figures and the partial-payment line.
    /// - Parameter summary: The statement to show.
    /// - Returns: The row view.
    private func statementRow(_ summary: StatementSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Statement balance")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Button("Override") { overridingStatement = summary.statement }
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.brandPurple)
            }
            Text(StatementFormatter.displayLine(for: summary, currencyCode: currencyCode))
                .font(Typography.rowSecondary)
                .foregroundStyle(summary.isSettled ? Palette.positiveGreen : Palette.textPrimary)
            if summary.statement.overrideBalanceCents != nil {
                Text("Using the figure you entered from your real statement.")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}

/// Builds the statement display lines required by §4.6.
enum StatementFormatter {

    /// The full line, such as "Statement $100.00 · $40.00 paid · $60.00 due 15 Sep".
    /// - Parameters:
    ///   - summary: The statement to describe.
    ///   - currencyCode: The display currency.
    /// - Returns: The formatted line.
    static func displayLine(for summary: StatementSummary, currencyCode: String) -> String {
        let balance = money(summary.balanceCents, currencyCode)
        let due = summary.statement.dueDate.formatted(.dateTime.day().month(.abbreviated))
        guard !summary.isSettled else {
            return "Statement \(balance) · paid in full"
        }
        guard summary.paidCents > 0 else {
            return "Statement \(balance) · \(money(summary.outstandingCents, currencyCode)) due \(due)"
        }
        return "Statement \(balance) · \(money(summary.paidCents, currencyCode)) paid · "
             + "\(money(summary.outstandingCents, currencyCode)) due \(due)"
    }

    /// A compact line for the earlier-statements list.
    /// - Parameters:
    ///   - summary: The statement to describe.
    ///   - currencyCode: The display currency.
    /// - Returns: The formatted line.
    static func compactLine(for summary: StatementSummary, currencyCode: String) -> String {
        guard !summary.isSettled else { return "Paid in full" }
        return "\(money(summary.outstandingCents, currencyCode)) of "
             + "\(money(summary.balanceCents, currencyCode)) left"
    }

    /// Formats an amount using the display currency.
    /// - Parameters:
    ///   - cents: The amount in cents.
    ///   - currencyCode: The display currency.
    /// - Returns: The formatted string.
    private static func money(_ cents: Int, _ currencyCode: String) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}
