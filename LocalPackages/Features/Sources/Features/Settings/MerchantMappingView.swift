import SwiftUI
import Domain

/// Maps merchants to categories, so a Shortcut files a shop the same way every time (§4.8).
///
/// A pin here beats the category a Shortcut passes: the Shortcut is built once and run
/// for months, the pin is the newer statement of intent.
public struct MerchantMappingView: View {
    /// The screen's state.
    @State private var model: MerchantMappingViewModel
    /// The merchant being typed into the add row.
    @State private var draftMerchant = ""
    /// The category chosen in the add row.
    @State private var draftCategoryID: UUID?
    /// Keyboard focus for the merchant field.
    @FocusState private var isMerchantFocused: Bool

    /// Creates the screen.
    /// - Parameter model: The screen's state.
    public init(model: MerchantMappingViewModel) {
        _model = State(initialValue: model)
    }

    /// The view body.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let errorMessage = model.errorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await model.load() }
                    }
                }
                addCard
                if !model.suggestions.isEmpty { suggestionsSection }
                mappingsSection
            }
            .padding(16)
        }
        .background(Palette.appBackground)
        .navigationTitle("Merchant categories")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    /// The merchant field and category chips that make a new pin.
    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a mapping").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merchant").sectionLabel()
                        TextField("Whole Foods", text: $draftMerchant)
                            .font(Typography.rowPrimary)
                            .textInputAutocapitalization(.words)
                            .focused($isMerchantFocused)
                    }
                    CategoryChipRow(
                        categories: model.categories,
                        categoryID: $draftCategoryID
                    ) { label in
                        Task { draftCategoryID = await model.addCategory(label: label) }
                    }
                    Button("Save mapping") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
        }
    }

    /// Whether the add row holds enough to write a pin.
    private var canSave: Bool {
        !draftMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftCategoryID != nil
    }

    /// What history already infers, one tap from becoming an instruction.
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested from your history").sectionLabel()
            CardContainer {
                VStack(spacing: 0) {
                    ForEach(Array(model.suggestions.prefix(8))) { suggestion in
                        if suggestion.id != model.suggestions.first?.id {
                            Divider().overlay(Palette.borderSubtle)
                        }
                        suggestionRow(suggestion)
                    }
                }
            }
        }
    }

    /// One suggested mapping.
    /// - Parameter suggestion: The merchant and the category history points at.
    /// - Returns: The row.
    private func suggestionRow(
        _ suggestion: MerchantMappingViewModel.Suggestion
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.merchant).font(Typography.rowPrimary)
                Text(model.category(id: suggestion.categoryID)?.label ?? "")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button("Pin") {
                Task {
                    await model.pin(
                        merchant: suggestion.merchant, categoryID: suggestion.categoryID
                    )
                }
            }
            .font(Typography.rowSecondary)
        }
        .padding(.vertical, 10)
    }

    /// The pins the user has written.
    private var mappingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your mappings").sectionLabel()
            if model.isLoading {
                CardContainer { SkeletonRow() }
            } else if model.rules.isEmpty {
                CardContainer {
                    Text("No mappings yet. Pin a merchant and every Shortcut will file it the same way.")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                CardContainer {
                    VStack(spacing: 0) {
                        ForEach(model.rules) { rule in
                            if rule.id != model.rules.first?.id {
                                Divider().overlay(Palette.borderSubtle)
                            }
                            mappingRow(rule)
                        }
                    }
                }
            }
        }
    }

    /// One stored pin.
    /// - Parameter rule: The pin to render.
    /// - Returns: The row.
    private func mappingRow(_ rule: Domain.MerchantCategoryRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName).font(Typography.rowPrimary)
                Text(model.category(id: rule.categoryID)?.label ?? "Category no longer exists")
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await model.remove(id: rule.id) }
            } label: {
                Image(systemName: "trash")
            }
            .iconTapTarget(expandedBy: 8)
            .accessibilityLabel("Remove mapping for \(rule.displayName)")
        }
        .padding(.vertical, 10)
    }

    /// Writes the pin the add row describes, then clears it.
    private func save() {
        guard let categoryID = draftCategoryID else { return }
        let merchant = draftMerchant
        Task {
            guard await model.pin(merchant: merchant, categoryID: categoryID) else { return }
            draftMerchant = ""
            draftCategoryID = nil
            isMerchantFocused = false
        }
    }
}
