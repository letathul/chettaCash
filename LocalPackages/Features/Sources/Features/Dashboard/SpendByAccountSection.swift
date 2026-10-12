import SwiftUI
import Domain

/// Where this month's spending went, account by account (§7.1).
///
/// This replaces a strip of balances. A balance is only right if income is logged too;
/// spend through an account is right from the first expense. Cards also say what they
/// owe, which comes from statements and not from income.
struct SpendByAccountSection: View {
    /// The rows, largest spend first.
    let rows: [AccountSpendRowModel]

    /// The view body.
    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Spent by account").sectionLabel()
                    Spacer()
                    Text("\(Date.now, format: .dateTime.month(.wide))")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
                CardContainer(cornerRadius: 16) {
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            if row.id != rows.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            AccountSpendRow(row: row)
                        }
                    }
                }
            }
        }
    }
}

/// One account row.
struct AccountSpendRow: View {
    /// The row to draw.
    let row: AccountSpendRowModel

    /// The view body.
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.isCard ? "creditcard.fill" : "banknote.fill")
                .font(.callout)
                .foregroundStyle(row.isCard ? Palette.attentionAmber : Palette.brandPurple)
                .frame(width: 36, height: 36)
                .background(
                    row.isCard ? Palette.attentionBannerBackground : Palette.segmentTrack,
                    in: .rect(cornerRadius: 12)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(Typography.rowSecondary.weight(row.isPastDue ? .semibold : .regular))
                        .foregroundStyle(row.isPastDue ? Palette.negativeRed : Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(row.amountText)
                .moneyText(Typography.rowPrimary)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
