import SwiftUI
import Domain

/// The Today section for entries a Shortcut could not file (§15.5).
///
/// Split from ``TodaySheet`` itself to keep each file within the 300-line limit.
extension TodaySheet {

    /// Entries written with no account, each with a picker to file it.
    ///
    /// Sits beside Missed payments on the attention surface rather than in a plain card.
    /// A parked entry is the only thing on this sheet that makes the app's own figures
    /// disagree — it counts toward Spend and moves no balance — so it is not a glance, it
    /// is a job.
    var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs an account").sectionLabel()
            VStack(alignment: .leading, spacing: 12) {
                unassignedExplanation
                ForEach(digest.unassignedEntries) { item in
                    Divider().overlay(Palette.attentionBannerBorder)
                    unassignedRow(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.attentionBannerBackground, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Palette.attentionBannerBorder, lineWidth: 1)
            }
        }
    }

    /// Why these entries are here, and what they are doing to the totals meanwhile.
    private var unassignedExplanation: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(Typography.rowSecondary)
            Text("A Shortcut logged these but couldn't tell which account they belong to. "
                + "They count toward your spending and move no balance until you say.")
                .font(Typography.rowSecondary)
        }
        .foregroundStyle(Palette.attentionBannerText)
    }

    /// One parked entry, with the picker that files it.
    /// - Parameter item: The entry waiting for an account.
    /// - Returns: The row view.
    private func unassignedRow(_ item: UnassignedEntryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.merchant.isEmpty ? "No merchant" : item.merchant)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Text(money(item.amountCents) + " · "
                    + item.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 8)
            assignMenu(for: item)
        }
    }

    /// The account picker for one parked entry.
    /// - Parameter item: The entry to file.
    /// - Returns: The menu view.
    private func assignMenu(for item: UnassignedEntryItem) -> some View {
        Menu {
            ForEach(model.assignableAccounts) { account in
                Button(account.name) {
                    Task { await model.assign(item, to: account.id) }
                }
            }
        } label: {
            Text("Choose")
                .font(Typography.errorCaption.weight(.semibold))
                .foregroundStyle(Palette.brandPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.brandPurple.opacity(0.12), in: .capsule)
                .fixedSize()
        }
        .accessibilityLabel("Choose an account for \(item.merchant)")
    }
}
