import SwiftUI
import Domain

/// How urgently a "Needs you" row asks for attention.
enum NeedsYouLevel {
    /// Something is already late.
    case alert
    /// Something is coming up.
    case warning
    /// Worth knowing, not urgent.
    case info

    /// The row icon's tint.
    var tint: Color {
        switch self {
        case .alert: return Palette.negativeRed
        case .warning: return Palette.attentionAmber
        case .info: return Palette.brandPurple
        }
    }

    /// The row icon's backing.
    var background: Color {
        switch self {
        case .alert: return Palette.errorBannerBackground
        case .warning: return Palette.attentionBannerBackground
        case .info: return Palette.segmentTrack
        }
    }
}

/// One row in "Needs you".
struct NeedsYouRow: Identifiable {
    /// The row's identity.
    let id: String
    /// How urgent it is.
    let level: NeedsYouLevel
    /// The SF Symbol shown in the icon tile. Never the only signal: the title says it too.
    let symbol: String
    /// The headline.
    let title: String
    /// The supporting line.
    let subtitle: String
}

/// What needs the user, as a short list instead of chips on the hero card (§7.2).
///
/// Every row is text first, so the meaning survives without colour (§12). A day with
/// nothing to report still shows an explicit "Nothing due" line rather than hiding.
struct NeedsYouSection: View {
    /// What needs attention today.
    let digest: TodayDigest
    /// The display currency.
    let currencyCode: String
    /// Opens the Today sheet.
    let onOpen: () -> Void

    /// The most rows shown before "All" takes over.
    private static let rowLimit = 3

    /// The view body.
    var body: some View {
        let rows = makeRows()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Needs you").sectionLabel()
                Spacer()
                if rows.count > Self.rowLimit {
                    Button("All \(rows.count)", action: onOpen)
                        .font(Typography.rowSecondary.weight(.semibold))
                        .foregroundStyle(Palette.brandPurple)
                }
            }
            CardContainer(cornerRadius: 16) {
                if rows.isEmpty {
                    Label("Nothing due", systemImage: "checkmark.circle")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(rows.prefix(Self.rowLimit)) { row in
                            if row.id != rows.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            Button(action: onOpen) { rowView(row) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// One tappable row.
    /// - Parameter row: The row to draw.
    /// - Returns: The row view.
    private func rowView(_ row: NeedsYouRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(row.level.tint)
                .frame(width: 32, height: 32)
                .background(row.level.background, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                Text(row.subtitle)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(Typography.errorCaption.weight(.semibold))
                .foregroundStyle(Palette.placeholder)
                .accessibilityHidden(true)
        }
        .tappableSurface()
    }

    /// Turns the digest into rows, most urgent first.
    /// - Returns: The rows; empty on a quiet day.
    private func makeRows() -> [NeedsYouRow] {
        var rows: [NeedsYouRow] = []
        if !digest.missedPayments.isEmpty {
            let total = digest.missedPayments.reduce(0) { $0 + $1.outstandingCents }
            let names = digest.missedPayments.map(\.accountName).joined(separator: " · ")
            rows.append(NeedsYouRow(
                id: "missed", level: .alert, symbol: "exclamationmark.triangle.fill",
                title: "\(money(total)) past due", subtitle: "\(names) statement"
            ))
        }
        let upcoming = digest.dueSoon.filter { !$0.isOverdue }
        if let first = upcoming.first {
            rows.append(dueRow(first, count: upcoming.count))
        }
        if !digest.unassignedEntries.isEmpty {
            let count = digest.unassignedEntries.count
            rows.append(NeedsYouRow(
                id: "unassigned", level: .warning, symbol: "tray.full",
                title: count == 1 ? "1 entry needs an account" : "\(count) entries need an account",
                subtitle: "Filed entries move the right balance"
            ))
        }
        if !digest.upcomingCharges.isEmpty {
            let names = digest.upcomingCharges.prefix(2).map(\.rule.name).joined(separator: " · ")
            let count = digest.upcomingCharges.count
            rows.append(NeedsYouRow(
                id: "charging", level: .info, symbol: "arrow.triangle.2.circlepath",
                title: count == 1 ? "1 subscription charging soon" : "\(count) subscriptions charging soon",
                subtitle: names
            ))
        }
        if !digest.endingSoon.isEmpty {
            let names = digest.endingSoon.prefix(2).map(\.item.name).joined(separator: " · ")
            rows.append(NeedsYouRow(
                id: "ending", level: .info, symbol: "hourglass",
                title: "\(digest.endingSoon.count) ending soon", subtitle: names
            ))
        }
        return rows
    }

    /// The row for the nearest statement due.
    /// - Parameters:
    ///   - item: The soonest statement.
    ///   - count: How many statements are coming up in all.
    /// - Returns: The row.
    private func dueRow(_ item: DueStatementItem, count: Int) -> NeedsYouRow {
        let days = item.daysRemaining
        let when = days == 0 ? "today" : (days == 1 ? "tomorrow" : "in \(days) days")
        let title = count > 1 ? "\(count) statements due soon" : "\(item.accountName) due \(when)"
        let date = item.statement.dueDate.formatted(.dateTime.day().month(.abbreviated))
        return NeedsYouRow(
            id: "due", level: .warning, symbol: "clock",
            title: title, subtitle: "\(money(item.outstandingCents)) · \(date)"
        )
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: currencyCode)
    }
}
