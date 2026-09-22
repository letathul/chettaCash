import SwiftUI
import Domain

/// One collapsible account group in Settings (§7.6).
///
/// Header shows the group name, its subtotal and a chevron; expanded it lists the
/// group's accounts with reorder arrows that disable at the group's boundaries.
struct GroupBlock: View {
    /// The group being shown.
    let group: Domain.AccountGroup
    /// The screen's view model.
    let model: SettingsViewModel
    /// Opens the Edit Account sheet for a row.
    let onSelect: (Domain.Account) -> Void
    /// Opens the add-account sheet scoped to this group.
    let onAddAccount: () -> Void
    /// Opens the rename sheet for this group.
    let onRename: () -> Void

    /// Whether this group is collapsed.
    private var isCollapsed: Bool { model.collapsedGroupIDs.contains(group.id) }

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !isCollapsed {
                    let accounts = model.accounts(in: group)
                    if accounts.isEmpty {
                        Text("No accounts in this group yet.")
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(accounts) { account in
                            Divider().overlay(Palette.borderSubtle)
                            AccountRow(account: account, model: model, onSelect: onSelect)
                        }
                    }
                    Divider().overlay(Palette.borderSubtle)
                    addAccountButton
                }
            }
        }
    }

    /// The only entry point to account creation, which is what implies the group (§7.6).
    private var addAccountButton: some View {
        Button(action: onAddAccount) {
            Text("+ Add account or card")
                .font(Typography.rowSecondary.weight(.semibold))
                .foregroundStyle(Palette.brandPurple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .tappableSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add an account or card to \(group.name)")
    }

    /// The group name, rename button, subtotal and collapse chevron.
    private var header: some View {
        HStack(spacing: 8) {
            collapseButton
            Button(action: onRename) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.brandPurple)
                    .frame(width: 28, height: 28)
                    .iconTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(group.name)")
        }
    }

    /// The group name, subtotal and collapse chevron.
    private var collapseButton: some View {
        Button {
            if isCollapsed {
                model.collapsedGroupIDs.remove(group.id)
            } else {
                model.collapsedGroupIDs.insert(group.id)
            }
        } label: {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Text(money(model.subtotalCents(for: group)))
                    .moneyText(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            }
            .tappableSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityHint("Double tap to \(isCollapsed ? "expand" : "collapse")")
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}

/// One account row inside a group block (§7.6).
struct AccountRow: View {
    /// The account being shown.
    let account: Domain.Account
    /// The screen's view model.
    let model: SettingsViewModel
    /// Opens the Edit Account sheet.
    let onSelect: (Domain.Account) -> Void

    /// The view body.
    var body: some View {
        HStack(spacing: 10) {
            Button {
                onSelect(account)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: account.kind == .card ? "creditcard.fill" : "banknote.fill")
                        .font(.callout)
                        .foregroundStyle(
                            account.kind == .card ? Palette.attentionAmber : Palette.brandPurple
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text(typeLabel)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(money(account.cachedBalanceCents))
                        .moneyText(Typography.rowPrimary)
                        .foregroundStyle(
                            account.cachedBalanceCents < 0 ? Palette.negativeRed : Palette.textPrimary
                        )
                }
                .tappableSurface()
            }
            .buttonStyle(.plain)

            reorderArrows
        }
    }

    /// The account's type and closed state.
    private var typeLabel: String {
        let kind = account.kind == .card ? "Card" : "Account"
        return account.isClosed ? "\(kind) · Closed" : kind
    }

    /// Up and down arrows, disabled at the group's boundaries (§7.6).
    private var reorderArrows: some View {
        VStack(spacing: 2) {
            arrow(systemName: "chevron.up", offset: -1, label: "Move \(account.name) up")
            arrow(systemName: "chevron.down", offset: 1, label: "Move \(account.name) down")
        }
    }

    /// One reorder arrow.
    /// - Parameters:
    ///   - systemName: The SF Symbol to draw.
    ///   - offset: `-1` to move up, `1` to move down.
    ///   - label: The accessibility label for this icon-only control.
    /// - Returns: The arrow button.
    private func arrow(systemName: String, offset: Int, label: String) -> some View {
        let isEnabled = model.canMove(account, by: offset)
        return Button {
            Task { await model.move(account, by: offset) }
        } label: {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(isEnabled ? Palette.brandPurple : Palette.placeholder)
                // Real width rather than an overflowing hit area: the two arrows sit 2pt
                // apart, so overlapping targets would let one steal the other's taps.
                .frame(width: 44, height: 20)
                .tappableSurface()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    /// Formats an amount using the display currency.
    /// - Parameter cents: The amount in cents.
    /// - Returns: The formatted string.
    private func money(_ cents: Int) -> String {
        CurrencyFormatter.string(fromCents: cents, currencyCode: model.settings.currencyCode)
    }
}
