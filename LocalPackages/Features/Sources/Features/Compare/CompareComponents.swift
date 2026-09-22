import SwiftUI
import Domain

/// The result banner above the two item cards (§7.5).
struct ResultBanner: View {
    /// The live outcome.
    let outcome: ComparisonOutcome
    /// The category being compared, which decides the "per" label.
    let category: UnitCategory?

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(Typography.rowPrimary)
                    .foregroundStyle(tint)
                if let detail {
                    Text(detail)
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// The banner's headline.
    private var headline: String {
        switch outcome {
        case .noResult: return "Enter both items to compare"
        case .tie: return "Both items cost the same"
        case .cheaper(let side, _, _):
            return side == .itemA ? "Item A is cheaper" : "Item B is cheaper"
        }
    }

    /// Both per-unit figures, once there are any.
    private var detail: String? {
        let suffix = category.map(UnitPrice.quotedPerLabel(for:)) ?? ""
        switch outcome {
        case .noResult:
            return "Add a price, a quantity and a unit for each."
        case .tie(let perUnitA, let perUnitB),
             .cheaper(_, let perUnitA, let perUnitB):
            return "A \(figure(perUnitA)) · B \(figure(perUnitB)) \(suffix)"
        }
    }

    /// The banner's tint — neutral until there is a result.
    private var tint: Color {
        switch outcome {
        case .noResult: return Palette.textSecondary
        case .tie: return Palette.textPrimary
        case .cheaper: return Palette.positiveGreen
        }
    }

    /// Formats a per-unit figure to two decimals.
    /// - Parameter value: The figure.
    /// - Returns: The formatted string.
    private func figure(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// One item's price, quantity and unit picker (§7.5).
struct ItemCard<UnitPickerContent: View>: View {
    /// The card's title.
    let title: String
    /// The typed price.
    @Binding var priceText: String
    /// The typed quantity.
    @Binding var quantityText: String
    /// Whether this item won the comparison.
    let isWinner: Bool
    /// Which field this card's price belongs to.
    let priceField: CompareField
    /// Which field this card's quantity belongs to.
    let quantityField: CompareField
    /// The screen's keyboard focus.
    @FocusState.Binding var focus: CompareField?
    /// The unit picker to show.
    @ViewBuilder let unitPicker: () -> UnitPickerContent

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 8)
                    if isWinner { cheaperBadge }
                }
                HStack(spacing: 12) {
                    field(
                        label: "Price", text: $priceText,
                        placeholder: "0.00", field: priceField
                    )
                    field(
                        label: "Quantity", text: $quantityText,
                        placeholder: "500", field: quantityField
                    )
                }
                unitPicker()
            }
        }
    }

    /// The green badge on the winning card.
    private var cheaperBadge: some View {
        Text("CHEAPER")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.positiveGreen, in: .capsule)
    }

    /// One labelled numeric field.
    ///
    /// No red ring and no error caption: invalid input simply yields no result (§7.5).
    ///
    /// - Parameters:
    ///   - label: The field's label.
    ///   - text: The bound text.
    ///   - placeholder: The placeholder shown when empty.
    ///   - field: Which field this is, for keyboard focus.
    /// - Returns: The field view.
    private func field(
        label: String,
        text: Binding<String>,
        placeholder: String,
        field: CompareField
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel()
            TextField(placeholder, text: text)
                .font(Typography.rowPrimary)
                .keyboardType(.decimalPad)
                .focused($focus, equals: field)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.surface, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Palette.borderSubtle, lineWidth: 1)
                }
        }
    }
}

/// Which Compare field holds the keyboard (§7.5).
///
/// All four use a `.decimalPad`, which has no return key, so the screen's Done button
/// is the only way out — and it needs to know what to release.
enum CompareField: Hashable {
    /// Item A's price.
    case priceA
    /// Item A's quantity.
    case quantityA
    /// Item B's price.
    case priceB
    /// Item B's quantity.
    case quantityB
}

/// Item A's unit picker: every unit, grouped by category (§7.5).
struct FullUnitPicker: View {
    /// The currently chosen unit.
    let selected: PackageUnit?
    /// Called when a unit is chosen.
    let onSelect: (PackageUnit) -> Void

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unit").sectionLabel()
            ForEach(UnitCategory.allCases, id: \.self) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(Typography.errorCaption)
                        .foregroundStyle(Palette.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(UnitPrice.units(in: category)) { unit in
                            UnitChip(unit: unit, isSelected: selected == unit) {
                                onSelect(unit)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Item B's unit picker, constrained to Item A's category (§7.5).
struct ConstrainedUnitPicker: View {
    /// The category Item A fixed, if any.
    let category: UnitCategory?
    /// The currently chosen unit.
    let selected: PackageUnit?
    /// Called when a unit is chosen.
    let onSelect: (PackageUnit) -> Void

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unit").sectionLabel()
            if let category {
                FlowLayout(spacing: 8) {
                    ForEach(UnitPrice.units(in: category)) { unit in
                        UnitChip(unit: unit, isSelected: selected == unit) {
                            onSelect(unit)
                        }
                    }
                }
            } else {
                Text("Choose Item A's unit first.")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.placeholder)
            }
        }
    }
}

/// One selectable unit chip.
struct UnitChip: View {
    /// The unit this chip selects.
    let unit: PackageUnit
    /// Whether it is the current selection.
    let isSelected: Bool
    /// Selects this unit.
    let onSelect: () -> Void

    /// The view body.
    var body: some View {
        Button(action: onSelect) {
            Text(unit.label)
                .font(Typography.rowSecondary)
                .foregroundStyle(isSelected ? .white : Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Palette.brandPurple : Palette.segmentTrack, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Display names for the unit categories.
extension UnitCategory {
    /// The heading shown above that category's units.
    var title: String {
        switch self {
        case .mass: return "Mass"
        case .volume: return "Volume"
        case .quantity: return "Quantity"
        }
    }
}
