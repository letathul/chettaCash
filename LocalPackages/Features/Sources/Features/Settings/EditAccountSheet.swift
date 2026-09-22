import SwiftUI
import Domain

/// The Edit Account sheet (§7.9, §6.3).
///
/// A `Cancel / Title / Save` header with no back chevron. Save lives in the header
/// only — there is deliberately no full-width Save at the bottom. The destructive
/// and corrective actions are their own rows below the form.
struct EditAccountSheet: View {
    /// The account being edited.
    let account: Domain.Account
    /// The screen's view model.
    let model: SettingsViewModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The editable form state.
    @State private var form: AccountFormState
    /// Whether the close flow is showing.
    @State private var isClosing = false
    /// Whether the balance-correction flow is showing.
    @State private var isCorrecting = false
    /// The card's statements, newest first (§4.6).
    @State private var summaries: [StatementSummary] = []

    /// Creates the sheet.
    /// - Parameters:
    ///   - account: The account being edited.
    ///   - model: The screen's view model.
    init(account: Domain.Account, model: SettingsViewModel) {
        self.account = account
        self.model = model
        _form = State(initialValue: AccountFormState(editing: account))
    }

    /// Which field holds the keyboard.
    @FocusState private var focusedField: AccountField?

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if account.isClosed { closedBanner }
                    CardContainer {
                        VStack(alignment: .leading, spacing: AccountFormFields.fieldSpacing) {
                            AccountGroupField(
                                form: form,
                                groups: model.groups,
                                onAddGroup: { name in Task { await model.addGroup(named: name) } },
                                isReadOnly: account.isClosed
                            )
                            AccountFormFields(form: form, isReadOnly: account.isClosed, focus: $focusedField)
                        }
                    }
                    if account.kind == .card && !account.isClosed { statementSection }
                    actionRows
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar($focusedField)
            .task { await loadStatements() }
            // Closed accounts are entirely read-only, so there is nothing to focus (§4.7).
            .autoFocus($focusedField, on: account.isClosed ? nil : .name)
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(account.isClosed)
                }
            }
        }
        .sheet(isPresented: $isClosing) {
            CloseAccountSheet(account: account, model: model) { dismiss() }
        }
        .sheet(isPresented: $isCorrecting) {
            CorrectBalanceSheet(account: account, model: model)
        }
    }

    /// The banner shown on a closed account (§4.7).
    private var closedBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .accessibilityHidden(true)
            Text("Closed by you on \(account.closedDate ?? .now, format: .dateTime.day().month(.wide).year()).")
                .font(Typography.rowSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.attentionAmber)
        .padding(12)
        .background(Palette.attentionAmber.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    /// The corrective and lifecycle action rows.
    /// One full-width action row inside the card.
    ///
    /// The width and hit shape belong to the label: a bare `Button` is only as wide as
    /// its text, leaving the rest of the card row dead (§8.4).
    /// - Parameters:
    ///   - title: The row text.
    ///   - tint: The text colour.
    /// - Returns: The styled label.
    private func rowLabel(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(Typography.rowPrimary)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tappableSurface()
    }

    @ViewBuilder
    private var actionRows: some View {
        if account.isClosed {
            CardContainer {
                Button {
                    Task {
                        await model.reopen(account)
                        dismiss()
                    }
                } label: {
                    rowLabel("Reopen account", tint: Palette.brandPurple)
                }
                .buttonStyle(.plain)
            }
        } else {
            CardContainer {
                VStack(alignment: .leading, spacing: 14) {
                    Button { isCorrecting = true } label: {
                        rowLabel("Correct balance", tint: Palette.brandPurple)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.borderSubtle)
                    Button { isClosing = true } label: {
                        rowLabel("Close account", tint: Palette.negativeRed)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A card's current and statement balances, plus the interest prompt (§4.6).
    private var statementSection: some View {
        CardStatementSection(
            account: account,
            summaries: summaries,
            currentBalanceCents: account.cachedBalanceCents,
            currencyCode: model.settings.currencyCode,
            onResolveInterest: { statement, cents in
                Task {
                    await model.resolveInterestPrompt(for: statement, cents: cents)
                    await loadStatements()
                }
            },
            onOverride: { statement, cents in
                Task {
                    await model.overrideStatementBalance(statement, cents: cents)
                    await loadStatements()
                }
            }
        )
    }

    /// Brings the card's statements up to date and reloads the summaries.
    private func loadStatements() async {
        guard account.kind == .card else { return }
        await model.reconcileStatements(for: account)
        summaries = await model.statementSummaries(for: account)
    }

    /// Validates and saves, closing the sheet only on success (§7.11).
    private func save() {
        guard let updated = form.commit(sortIndex: account.sortIndex) else { return }
        Task {
            await model.save(updated)
            dismiss()
        }
    }
}
