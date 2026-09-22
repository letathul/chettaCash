import SwiftUI
import Domain

/// The unit-price comparison screen (§7.5).
///
/// Reached via More ▸ Compare Prices. Validation here fails silently to "no result
/// yet" — deliberately unlike the add sheets, which show red rings.
public struct CompareView: View {
    /// The screen's view model.
    @State private var model: CompareViewModel
    /// Which field holds the keyboard.
    @FocusState private var focusedField: CompareField?

    /// Creates the screen.
    /// - Parameter model: The screen's view model.
    public init(model: CompareViewModel) {
        _model = State(initialValue: model)
    }

    /// The view body.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await model.load() }
                    }
                }
                if model.isLoading {
                    SkeletonCard(rowCount: 2)
                    SkeletonCard(rowCount: 3)
                } else {
                    historyStrip
                    ResultBanner(outcome: model.outcome, category: model.constrainedCategory)
                    itemACard
                    itemBCard
                }
            }
            .padding(16)
        }
        .background(Palette.appBackground)
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneToolbar($focusedField)
        .navigationTitle("Compare Prices")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .autoFocus($focusedField, on: .priceA)
        // Debounced: each of these fields used to persist to SwiftData *and* re-read the
        // whole comparisons table on every character. `.task(id:)` cancels the pending
        // write when the next keystroke arrives, so only the pause is paid for.
        .task(id: fieldSignature) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.commitFields()
        }
    }

    /// The four typed fields, so a change in any one restarts the debounce.
    private var fieldSignature: String {
        "\(model.priceAText)|\(model.quantityAText)|\(model.priceBText)|\(model.quantityBText)"
    }

    /// The horizontally scrolling strip of saved comparisons.
    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").sectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.comparisons) { comparison in
                        historyChip(comparison)
                    }
                    Button {
                        Task { await model.addComparison() }
                    } label: {
                        Text("+ New")
                            .font(Typography.rowSecondary.weight(.semibold))
                            .foregroundStyle(Palette.brandPurple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        Palette.dashedAccent,
                                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                    )
                            }
                            .tappableSurface()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// One history chip: label, status, and a remove control hidden at one remaining.
    /// - Parameter comparison: The comparison the chip represents.
    /// - Returns: The chip view.
    private func historyChip(_ comparison: Domain.Comparison) -> some View {
        let isSelected = model.selected?.id == comparison.id
        return HStack(spacing: 8) {
            Button {
                model.select(comparison.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comparison.label)
                        .font(Typography.rowSecondary.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                    Text(model.statusLabel(for: comparison))
                        .font(Typography.errorCaption)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : Palette.textSecondary)
                }
                // The chip paints its padding and capsule on the outer HStack, outside
                // this button, so claim that ring back as hit area.
                .iconTapTarget(expandedBy: 8)
            }
            .buttonStyle(.plain)

            // Hidden when only one remains: the last comparison can never be deleted.
            if model.canRemove(comparison.id) {
                Button {
                    Task { await model.remove(comparison.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Palette.textSecondary)
                        .iconTapTarget(expandedBy: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(comparison.label)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? Palette.brandPurple : Palette.surface,
            in: .rect(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.clear : Palette.borderSubtle, lineWidth: 1)
        }
    }

    /// Item A: price, quantity and the full unit picker.
    private var itemACard: some View {
        ItemCard(
            title: "Item A",
            priceText: $model.priceAText,
            quantityText: $model.quantityAText,
            isWinner: model.outcome.winner == .itemA,
            priceField: .priceA,
            quantityField: .quantityA,
            focus: $focusedField,
            unitPicker: {
                FullUnitPicker(selected: model.unitA, onSelect: { unit in
                    Task { await model.selectUnitA(unit) }
                })
            }
        )
    }

    /// Item B: price, quantity and a unit picker constrained to Item A's category.
    private var itemBCard: some View {
        ItemCard(
            title: "Item B",
            priceText: $model.priceBText,
            quantityText: $model.quantityBText,
            isWinner: model.outcome.winner == .itemB,
            priceField: .priceB,
            quantityField: .quantityB,
            focus: $focusedField,
            unitPicker: {
                ConstrainedUnitPicker(
                    category: model.constrainedCategory,
                    selected: model.unitB,
                    onSelect: { unit in Task { await model.selectUnitB(unit) } }
                )
            }
        )
    }
}

/// The More tab (§6.2).
///
/// A list screen with one row today. It deliberately does **not** hard-route straight
/// to Compare: the tab exists to leave room for future utilities, and routing it
/// directly would need a redesign to add a second one.
public struct MoreView: View {
    /// The Compare screen's view model.
    private let compareModel: CompareViewModel

    /// Creates the screen.
    /// - Parameter compareModel: The Compare screen's view model.
    public init(compareModel: CompareViewModel) {
        self.compareModel = compareModel
    }

    /// The view body.
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    NavigationLink {
                        CompareView(model: compareModel)
                    } label: {
                        CardContainer {
                            HStack(spacing: 12) {
                                Image(systemName: "scalemass")
                                    .font(.title3)
                                    .foregroundStyle(Palette.brandPurple)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Compare Prices")
                                        .font(Typography.rowPrimary)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text("Work out the better value per 100 g or 100 mL.")
                                        .font(Typography.rowSecondary)
                                        .foregroundStyle(Palette.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.textSecondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("More")
        }
    }
}
