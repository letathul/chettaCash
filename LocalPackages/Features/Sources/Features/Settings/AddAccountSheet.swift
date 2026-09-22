import SwiftUI
import Domain

/// The add-account bottom sheet, scoped to one group (§7.6, §7.10).
///
/// There is no group picker: the sheet is opened from a specific group's card, so the
/// group is implied by what the user tapped rather than re-asked as a field. Moving an
/// account afterwards is the Edit sheet's job.
struct AddAccountSheet: View {
    /// The group the new account joins.
    let group: Domain.AccountGroup
    /// The position to give the new account within its group.
    let sortIndex: Int
    /// Persists the account, reporting whether it saved.
    let onSave: (Domain.Account) async -> Bool

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The viewer's current text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The editable form state, with the group already baked in.
    @State private var form: AccountFormState
    /// How tall the sheet currently sits.
    @State private var detent: PresentationDetent = .medium

    /// Creates the sheet.
    /// - Parameters:
    ///   - group: The group the new account joins.
    ///   - sortIndex: The position to give the new account within its group.
    ///   - onSave: Persists the account, reporting whether it saved.
    init(
        group: Domain.AccountGroup,
        sortIndex: Int,
        onSave: @escaping (Domain.Account) async -> Bool
    ) {
        self.group = group
        self.sortIndex = sortIndex
        self.onSave = onSave
        _form = State(initialValue: AccountFormState(groupID: group.id))
    }

    /// Which field holds the keyboard.
    @FocusState private var focusedField: AccountField?

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    context
                    CardContainer {
                        AccountFormFields(form: form, focus: $focusedField)
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneToolbar($focusedField)
            .navigationTitle("Add to \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Save lives in the toolbar, not at the bottom: at the medium detent a
                // bottom button sits behind the keyboard.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .autoFocus($focusedField, on: .name)
        .presentationDetents(detents, selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: form.kind) { _, kind in
            // A card adds three more fields, which do not fit at medium.
            if kind == .card { detent = .large }
        }
    }

    /// The detents the sheet offers.
    ///
    /// At accessibility text sizes even the bare stack overflows a medium sheet, so it
    /// opens full height rather than at a guess that would clip the name field.
    private var detents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    }

    /// The line naming the group this account is joining.
    private var context: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("In \(group.name)")
                .font(Typography.rowPrimary.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("You can move it to another group later from Edit account.")
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Validates and saves, closing the sheet only on success (§7.11).
    private func save() {
        guard let account = form.commit(sortIndex: sortIndex) else { return }
        Task {
            if await onSave(account) { dismiss() }
        }
    }
}
