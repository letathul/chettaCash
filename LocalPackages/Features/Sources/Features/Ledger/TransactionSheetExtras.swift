import SwiftUI
import Domain

/// The transaction sheet's extras: recurring, products and tags (§7.8).
///
/// Split from ``TransactionSheet`` to keep each file within the 300-line limit.
extension TransactionSheet {
    /// Recurring and tags — hidden in transfer mode (§7.8).
    var extrasCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                RecurringFields(form: form, focus: $focusedField)
                Divider().overlay(Palette.borderSubtle)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags").sectionLabel()
                    TagInput(tags: $form.tags, focus: $focusedField, field: .tag)
                    tagSuggestions
                }
            }
        }
    }

    /// The products this purchase contained (§7.8).
    ///
    /// This is the only way a product is created: it is part of a purchase, never a
    /// thing of its own. Hidden in transfer mode, where the idea does not apply.
    ///
    /// Both the chip here and the button above the keyboard open the same Add Product
    /// form, so a product is always recorded in full rather than as a bare name.
    @ViewBuilder
    var productsCard: some View {
        if form.mode != .transfer, model.productsModel != nil {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Products").sectionLabel()
                    if form.products.isEmpty {
                        Text("Track a warranty, a free trial or a subscription for "
                            + "something in this purchase.")
                            .font(Typography.errorCaption)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(form.products) { product in
                            if product.id != form.products.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            productRow(product)
                        }
                    }
                    addProductChip
                }
            }
        }
    }

    /// One product row, tappable into its own form.
    /// - Parameter product: The product to render.
    /// - Returns: The row view.
    func productRow(_ product: Domain.Product) -> some View {
        HStack(spacing: 10) {
            Button {
                editingProduct = product
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: productGlyph(product))
                        .font(.callout)
                        .foregroundStyle(Palette.brandPurple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                            .font(Typography.rowPrimary)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(productSubtitle(product))
                            .font(Typography.errorCaption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                removeProduct(product)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.callout)
                    .foregroundStyle(Palette.negativeRed)
                    .iconTapTarget(expandedBy: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(product.name)")
        }
    }

    /// The glyph describing what a product is tracking.
    /// - Parameter product: The product to describe.
    /// - Returns: An SF Symbol name.
    private func productGlyph(_ product: Domain.Product) -> String {
        if product.hasTrial { return "hourglass" }
        if product.hasWarranty { return "checkmark.shield.fill" }
        return "shippingbox.fill"
    }

    /// What a product row says under its name.
    /// - Parameter product: The product to describe.
    /// - Returns: The subtitle.
    private func productSubtitle(_ product: Domain.Product) -> String {
        var parts: [String] = []
        if let category = model.productsModel?.category(id: product.categoryID)?.label {
            parts.append(category)
        }
        if product.hasTrial { parts.append("Free trial") }
        if product.hasWarranty { parts.append("Warranty") }
        if product.recurringRuleID != nil { parts.append("Subscription") }
        return parts.isEmpty ? "No dates tracked" : parts.joined(separator: " · ")
    }

    /// The dashed "Add Product" chip.
    private var addProductChip: some View {
        Button { isAddingProduct = true } label: {
            Text("Add Product")
                .font(Typography.rowSecondary.weight(.semibold))
                .foregroundStyle(Palette.brandPurple)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay {
                    Capsule().strokeBorder(
                        Palette.dashedAccent,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
                }
                // Dashed stroke, no fill — the chip interior needs an explicit shape.
                .tappableSurface()
        }
        .buttonStyle(.plain)
    }
}

/// Adding, editing and removing this purchase's products (§7.8).
extension TransactionSheet {

    /// The purchase a product sheet should open against.
    ///
    /// On Add the transaction has no identifier yet, so the product form is given the
    /// form's current values as a provisional purchase: the header reads correctly, and
    /// the real identifier is stamped on when the transaction is written.
    var provisionalPurchase: Domain.Transaction {
        editing ?? form.commitPreview()
    }

    /// Records a product the sheet produced.
    ///
    /// On Edit it is already persisted, so the list is refreshed from the view model.
    /// On Add it is held pending until the transaction exists.
    ///
    /// - Parameter product: The product to record.
    func recordProduct(_ product: Domain.Product) {
        if let index = form.products.firstIndex(where: { $0.id == product.id }) {
            form.products[index] = product
        } else {
            form.products.append(product)
        }
    }

    /// Removes a product from the purchase.
    ///
    /// A product already persisted is deleted; a pending one merely disappears, because
    /// nothing was written.
    ///
    /// - Parameter product: The product to remove.
    func removeProduct(_ product: Domain.Product) {
        form.products.removeAll { $0.id == product.id }
        guard editing != nil, let productsModel = model.productsModel else { return }
        Task { await productsModel.delete(product) }
    }
}
