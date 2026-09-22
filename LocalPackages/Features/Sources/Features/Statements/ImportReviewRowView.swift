import SwiftUI
import Domain

/// One row of the import review list (§9.7).
///
/// Its own `View` struct, and deliberately small, so SwiftUI re-evaluates only the row the
/// user touched: a statement produces dozens of these, and the list is the longest in the app.
struct ImportReviewRowView: View {
    /// The row's editable state.
    @Bindable var draft: StatementReviewDraft
    /// The ledger entry this row may duplicate, when there is one.
    let existing: Domain.Transaction?
    /// What a reader concluded about that pairing, when it said anything.
    let rationale: String?
    /// The categories the editor offers.
    let categories: [Domain.Category]
    /// The currency amounts are shown in.
    let currencyCode: String

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow
            if let badge { ImportReviewBadge(badge: badge) }
            if draft.isExpanded {
                if let existing {
                    DuplicateNotice(
                        existing: existing, rationale: rationale, currencyCode: currencyCode
                    )
                }
                ImportReviewRowEditor(draft: draft, categories: categories)
            }
        }
        .padding(.vertical, 10)
    }

    /// The always-visible line: tick, name, date, amount.
    private var summaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                draft.setTicked(!draft.isTicked)
            } label: {
                Image(systemName: draft.isTicked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(tickColor)
            }
            .buttonStyle(.plain)
            .disabled(!draft.canBeTicked)
            .iconTapTarget(expandedBy: 6)
            .accessibilityLabel(draft.isTicked ? "Do not import" : "Import")

            Button {
                draft.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(draft.dateDisplay)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(draft.amountDisplay)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(draft.isIncome ? Palette.positiveGreen : Palette.textPrimary)
                        .monospacedDigit()
                    Image(systemName: draft.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The name shown, falling back to the statement's own wording.
    private var title: String {
        draft.merchant.isEmpty ? draft.sourceText : draft.merchant
    }

    /// The tick's colour: grey when the row cannot be ticked at all.
    private var tickColor: Color {
        guard draft.canBeTicked else { return Palette.placeholder }
        return draft.isTicked ? Palette.brandPurple : Palette.textSecondary
    }

    /// What, if anything, to flag about this row.
    private var badge: ImportReviewBadge.Kind? {
        switch draft.status {
        case .ready: return nil
        case .needsAttention(let problem): return .attention(problem.explanation)
        case .duplicate(_, let reason): return .duplicate(reason.explanation)
        case .excluded(let reason):
            return .excluded(reason.explanation ?? "This line was left out.")
        }
    }
}

/// The coloured note under a row that needs one.
struct ImportReviewBadge: View {

    /// What the badge is saying.
    enum Kind {
        /// A line the reader could not turn into a row.
        case attention(String)
        /// A row the ledger may already hold.
        case duplicate(String)
        /// A row that cannot be imported at all.
        case excluded(String)
    }

    /// What the badge is saying.
    let badge: Kind

    /// The view body.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.rowSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(tint)
        .padding(.leading, 36)
    }

    /// The badge's message.
    private var message: String {
        switch badge {
        case .attention(let text), .duplicate(let text), .excluded(let text): return text
        }
    }

    /// The badge's symbol.
    private var symbol: String {
        switch badge {
        case .attention: return "exclamationmark.triangle"
        case .duplicate: return "doc.on.doc"
        case .excluded: return "minus.circle"
        }
    }

    /// The badge's colour.
    private var tint: Color {
        switch badge {
        case .attention: return Palette.attentionAmber
        case .duplicate: return Palette.brandPurple
        case .excluded: return Palette.textSecondary
        }
    }
}
