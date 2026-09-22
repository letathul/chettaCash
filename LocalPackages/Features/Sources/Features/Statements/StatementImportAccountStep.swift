import SwiftUI
import Domain

/// Asks which card a statement belongs to, when it could not be settled automatically.
///
/// Reached in three cases, and the distinction matters: the statement named a card the
/// user has not set up (offer to create it), it named one that matches several (make them
/// choose — creating a fourth card here would be the wrong-balance mistake
/// ``AccountMatcher`` exists to prevent), or it named none at all (make them choose).
struct StatementImportAccountStep: View {
    /// The import waiting on an answer.
    let model: StatementImportViewModel
    /// Closes the step once a card is settled.
    let onResolved: () -> Void

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) {}
                    }
                    Text(prompt)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if case .unknown(let proposed) = model.accountMatch {
                        createCard(proposed)
                    }
                    if !choices.isEmpty {
                        Text(choicesLabel).sectionLabel()
                        CardContainer {
                            VStack(spacing: 0) {
                                ForEach(Array(choices.enumerated()), id: \.element.id) { index, account in
                                    if index > 0 { Divider().overlay(Palette.borderSubtle) }
                                    choiceRow(account)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Which card?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// What to tell the user about why they are being asked.
    private var prompt: String {
        switch model.accountMatch {
        case .unknown(let proposed):
            return "This statement is for \(proposed.name), which you have not set up yet."
        case .ambiguous:
            return "More than one of your cards matches this statement. Which one is it?"
        case .indeterminate:
            return "This statement did not say which card it is for. Which one is it?"
        case .matched, .none:
            return ""
        }
    }

    /// The accounts offered, narrowed to the matches when the statement was ambiguous.
    private var choices: [Domain.Account] {
        guard case .ambiguous(let ids) = model.accountMatch else {
            return model.accounts.filter { $0.kind == .card }
        }
        return model.accounts.filter { ids.contains($0.id) }
    }

    /// The heading above the list of accounts.
    private var choicesLabel: String {
        if case .unknown = model.accountMatch { return "Or use an existing card" }
        return "Your cards"
    }

    /// The offer to create the card the statement named.
    /// - Parameter proposed: The card that would be created.
    /// - Returns: The view.
    private func createCard(_ proposed: Domain.Account) -> some View {
        Button {
            Task {
                await model.createSuggestedAccount()
                finish()
            }
        } label: {
            CardContainer {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.title3)
                        .foregroundStyle(Palette.brandPurple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add \(proposed.name)")
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Starts at a zero balance; the imported charges build it up.")
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                }
                .tappableSurface()
            }
        }
        .buttonStyle(.plain)
    }

    /// One existing card.
    /// - Parameter account: The card offered.
    /// - Returns: The row.
    private func choiceRow(_ account: Domain.Account) -> some View {
        Button {
            Task {
                await model.confirmAccount(account.id)
                finish()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    if let last4 = account.last4 {
                        Text("•• \(last4)")
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Palette.textSecondary)
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
    }

    /// Closes the step once the import has run.
    private func finish() {
        guard model.errorMessage == nil else { return }
        dismiss()
        onResolved()
    }
}
