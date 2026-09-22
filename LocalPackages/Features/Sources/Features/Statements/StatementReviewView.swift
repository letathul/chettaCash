import SwiftUI
import Domain

/// Reviewing a statement before any of it is written (§9.7).
///
/// **One screen, from picking the file to approving the rows.** The import used to be four
/// sheets in sequence, with the writing already done by the time the first of them appeared.
/// Here the reading happens in place, under a progress strip, and the rows fill in beneath it.
public struct StatementReviewView: View {
    /// The import's state.
    @Bindable var model: StatementImportViewModel
    /// Whether the "which card?" step is open.
    @State private var isChoosingAccount = false
    /// Closes the screen.
    @Environment(\.dismiss) private var dismiss

    /// Creates the screen.
    /// - Parameter model: The import's state.
    public init(model: StatementImportViewModel) {
        self.model = model
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) { model.errorMessage = nil }
                    }
                    if model.phase.isRunning {
                        StatementImportProgressCard(phase: model.phase)
                    }
                    if model.hasReview {
                        summaryCard
                        if model.canRepairUnreadLines { repairCard }
                        filterChips
                        rowsCard
                    } else if needsAccount {
                        chooseAccountCard
                    } else if !model.phase.isRunning && model.errorMessage == nil {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: "Nothing to review",
                            message: "No transaction lines were found in that statement."
                        )
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Review import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { approveBar }
            .sheet(isPresented: $isChoosingAccount) {
                StatementImportAccountStep(model: model) { isChoosingAccount = false }
            }
            .onChange(of: needsAccount, initial: true) { _, needed in
                isChoosingAccount = needed
            }
        }
    }

    /// Whether the statement's card is still an open question.
    private var needsAccount: Bool {
        switch model.accountMatch {
        case .ambiguous, .unknown, .indeterminate: return true
        case .matched, nil: return false
        }
    }

    /// Shown behind the card picker, so the screen is never blank while it is open.
    private var chooseAccountCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which card is this statement for?")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Button("Choose a card") { isChoosingAccount = true }
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.brandPurple)
            }
        }
    }

    /// The headline counts, above the list.
    private var summaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.reviewSummary.headline)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing is saved until you tap Add below.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    /// The offer to read the leftover lines with the on-device model.
    ///
    /// User-initiated rather than automatic: it costs seconds, and the rows it produces are
    /// the least certain on the screen, so the user should know they asked for them.
    private var repairCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Some lines could not be read")
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text(
                    "The on-device model can try these, and nothing leaves your phone. "
                        + "Anything it reads arrives unticked for you to check."
                )
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                Button(model.repairButtonTitle) {
                    Task { await model.repairUnreadLines() }
                }
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.brandPurple)
            }
        }
    }

    /// The filter chips, and the tick-all controls beside them.
    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ImportReviewFilter.allCases) { option in
                        SelectableChip(
                            title: option.title, isSelected: model.filter == option
                        ) {
                            model.filter = option
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            HStack(spacing: 16) {
                Button("Tick all shown") { model.setAllVisible(ticked: true) }
                Button("Untick all shown") { model.setAllVisible(ticked: false) }
            }
            .font(Typography.rowSecondary)
            .foregroundStyle(Palette.brandPurple)
        }
    }

    /// The rows themselves.
    private var rowsCard: some View {
        CardContainer {
            LazyVStack(spacing: 0) {
                ForEach(model.visibleDrafts) { draft in
                    if draft.id != model.visibleDrafts.first?.id {
                        Divider().overlay(Palette.borderSubtle)
                    }
                    ImportReviewRowView(
                        draft: draft,
                        existing: model.existingEntry(for: draft),
                        rationale: model.rationale(for: draft),
                        categories: model.categories,
                        currencyCode: model.settings.currencyCode
                    )
                }
            }
        }
    }

    /// The bar that writes the import, and the only thing on screen that does.
    private var approveBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.borderSubtle)
            Button {
                Task {
                    if await model.approve() { dismiss() }
                }
            } label: {
                HStack(spacing: 8) {
                    if model.isApproving { ProgressView().tint(.white) }
                    Text(model.approveButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.brandPurple)
            .disabled(model.tickedCount == 0 || model.isApproving)
            .padding(16)
        }
        .background(.regularMaterial)
        .opacity(model.hasReview ? 1 : 0)
    }
}

/// The progress strip shown while a statement is being read (§9.7).
struct StatementImportProgressCard: View {
    /// How far along the import is.
    let phase: StatementImportPhase

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text(phase.message)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                ProgressView(value: phase.progress)
                    .tint(Palette.brandPurple)
                Text("Everything stays on this device.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
