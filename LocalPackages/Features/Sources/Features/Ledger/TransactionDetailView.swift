import SwiftUI
import Domain

/// One transaction, read-only (§7.4, §7.8).
///
/// Tapping a row anywhere in the app opens this rather than the edit form. Browsing
/// history should not put the user one stray keystroke away from rewriting a past
/// transaction, so editing is an explicit act: the Edit button presents the same
/// ``TransactionSheet`` the Ledger's "+" does.
///
/// The transaction is re-read from the view model on every pass rather than held, so a
/// save made in that sheet is reflected here, and a delete pops the screen instead of
/// leaving it showing a row that no longer exists.
struct TransactionDetailView: View {
    /// The screen's view model.
    let model: LedgerViewModel
    /// The transaction opened, as it stood when the row was tapped.
    let transaction: Domain.Transaction

    /// Pops the screen when its transaction is deleted.
    @Environment(\.dismiss) private var dismiss
    /// The transaction whose Edit sheet is open.
    @State private var editing: Domain.Transaction?
    /// The product whose Edit sheet is open (§7.8).
    @State private var editingProduct: Domain.Product?

    /// The transaction as the store currently has it, or `nil` once it is deleted.
    private var current: Domain.Transaction? {
        model.allTransactions.first { $0.id == transaction.id }
    }

    /// The view body.
    var body: some View {
        let live = current ?? transaction
        let detail = model.detail(for: live)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(detail)
                factsCard(detail)
                if !detail.tags.isEmpty { tagsCard(detail) }
                if !detail.products.isEmpty { productsCard(detail) }
                if let receiptName = detail.receiptName { receiptCard(receiptName) }
            }
            .padding(16)
        }
        .background(Palette.appBackground)
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = live }
                    .disabled(!detail.isEditable)
            }
        }
        // The Dashboard and the search screen open this too, and either can be the
        // only tab the user has visited — without this the Ledger's model is still
        // empty, so the account, category and products all read as missing.
        .task { await model.loadIfNeeded() }
        // A delete from the Edit sheet leaves nothing to show.
        .onChange(of: current == nil) { _, isGone in
            if isGone { dismiss() }
        }
        .sheet(item: $editing) { target in
            TransactionSheet(model: model, editing: target)
        }
        .sheet(item: $editingProduct) { product in
            productSheet(product, purchase: live)
        }
    }

    /// The amount, what kind of entry it is, and the merchant.
    /// - Parameter detail: The rendered detail.
    /// - Returns: The header card.
    private func header(_ detail: TransactionDetailModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    avatar(detail)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.title)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                        Text(detail.typeLabel)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                }
                Text(detail.amountText)
                    .moneyText(Typography.headlineNumber)
                    .foregroundStyle(detail.tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let seriesName = detail.seriesName {
                    Label("Part of \(seriesName)", systemImage: "repeat")
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.brandPurple)
                }
                if !detail.isEditable {
                    Text("This account is closed, so the transaction cannot be edited.")
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// The category-tinted avatar, matching the row the user tapped.
    /// - Parameter detail: The rendered detail.
    /// - Returns: The avatar view.
    private func avatar(_ detail: TransactionDetailModel) -> some View {
        let swatch = detail.avatar.swatch
        return ZStack {
            Circle().fill(swatch.background)
            Image(systemName: detail.glyph)
                .font(.caption.weight(.bold))
                .foregroundStyle(swatch.foreground)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    /// Category, account, date and whatever else was filled in.
    /// - Parameter detail: The rendered detail.
    /// - Returns: The card.
    private func factsCard(_ detail: TransactionDetailModel) -> some View {
        CardContainer {
            VStack(spacing: 12) {
                ForEach(detail.rows) { row in
                    if row.id != detail.rows.first?.id {
                        Divider().overlay(Palette.borderSubtle)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        Text(row.value)
                            .font(Typography.rowSecondary)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    /// The transaction's tags.
    /// - Parameter detail: The rendered detail.
    /// - Returns: The card.
    private func tagsCard(_ detail: TransactionDetailModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags").sectionLabel()
                ReadOnlyTags(tags: detail.tags)
            }
        }
    }

    /// The products this purchase contained, each tappable into its own form (§7.8).
    /// - Parameter detail: The rendered detail.
    /// - Returns: The card.
    private func productsCard(_ detail: TransactionDetailModel) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Products").sectionLabel()
                ForEach(detail.products) { product in
                    if product.id != detail.products.first?.id {
                        Divider().overlay(Palette.borderSubtle)
                    }
                    Button {
                        editingProduct = product.product
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: product.glyph)
                                .font(.callout)
                                .foregroundStyle(Palette.brandPurple)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .font(Typography.rowPrimary)
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                Text(product.detail)
                                    .font(Typography.errorCaption)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .tappableSurface()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A note that a receipt is attached. Removing it belongs to the edit form.
    /// - Parameter name: The stored file's name.
    /// - Returns: The card.
    private func receiptCard(_ name: String) -> some View {
        CardContainer {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .foregroundStyle(Palette.brandPurple)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receipt")
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Text(name)
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
        }
    }

    /// The Edit Product sheet for one of this purchase's products.
    /// - Parameters:
    ///   - product: The product being edited.
    ///   - purchase: The transaction it belongs to.
    /// - Returns: The sheet.
    @ViewBuilder
    private func productSheet(
        _ product: Domain.Product,
        purchase: Domain.Transaction
    ) -> some View {
        if let productsModel = model.productsModel {
            ProductSheet(model: productsModel, purchase: purchase, editing: product)
        }
    }
}

/// The transaction's tags, read-only.
///
/// Wrapped by the shared ``FlowLayout``, which is what the tag *input* uses: chips grow
/// with Dynamic Type, so a fixed row would clip them (§12).
struct ReadOnlyTags: View {
    /// The tags to show.
    let tags: [String]

    /// The view body.
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.segmentTrack, in: .capsule)
            }
        }
    }
}
