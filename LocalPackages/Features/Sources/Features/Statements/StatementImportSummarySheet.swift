import SwiftUI
import Domain

/// What the import did, shown once it finishes (§9.4).
struct StatementImportSummarySheet: View {
    /// The counts to report.
    let outcome: ImportOutcome
    /// The label of the resolve button, when conflicts are still waiting.
    let pendingTitle: String?
    /// Opens the wizard again.
    let onResolve: () -> Void

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(outcome.summary)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    CardContainer {
                        VStack(spacing: 12) {
                            row("Rows on the statement", outcome.rowsProcessed)
                            Divider().overlay(Palette.borderSubtle)
                            row("Added to your ledger", outcome.added)
                            Divider().overlay(Palette.borderSubtle)
                            row("Already recorded", outcome.exactDuplicatesSkipped)
                            if outcome.conflictsRaised > 0 {
                                Divider().overlay(Palette.borderSubtle)
                                row("Duplicates resolved", outcome.conflictsResolved)
                            }
                            if outcome.paymentsSkipped > 0 {
                                Divider().overlay(Palette.borderSubtle)
                                row("Card payments left out", outcome.paymentsSkipped)
                            }
                        }
                    }

                    if let note = outcome.paymentNote {
                        Text(note)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pendingTitle {
                        Button(action: onResolve) {
                            Text(pendingTitle)
                                .font(Typography.rowPrimary)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Palette.brandPurple, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Import finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One count.
    /// - Parameters:
    ///   - label: What is being counted.
    ///   - value: How many.
    /// - Returns: The row.
    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 8)
            Text("\(value)")
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}
