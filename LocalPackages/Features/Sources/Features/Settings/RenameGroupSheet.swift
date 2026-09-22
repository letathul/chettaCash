import SwiftUI
import Domain

/// The rename-group sheet (§7.6).
///
/// The group page makes groups cheap to create, which makes a typo cheap to make too.
/// Renaming goes through the existing `AccountRepository.save(_ group:)`, so nothing
/// below the view layer changes. Groups are not deletable — §4.7's "never hard-delete"
/// stance covers accounts, and a group with history behind it is no different.
struct RenameGroupSheet: View {
    /// The group being renamed.
    let group: Domain.AccountGroup
    /// The screen's view model.
    let model: SettingsViewModel

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The name being typed.
    @State private var name: String
    /// Whether Save has been attempted, which is what reveals validation (§7.11).
    @State private var hasAttemptedSave = false

    /// Creates the sheet.
    /// - Parameters:
    ///   - group: The group being renamed.
    ///   - model: The screen's view model.
    init(group: Domain.AccountGroup, model: SettingsViewModel) {
        self.group = group
        self.model = model
        _name = State(initialValue: group.name)
    }

    /// The trimmed group name.
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name field's error, or `nil` when valid.
    private var nameError: String? {
        guard hasAttemptedSave else { return nil }
        if trimmed.isEmpty { return "Group name is required." }
        let clash = model.groups.first {
            $0.id != group.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if let clash { return "You already have a group called \(clash.name)." }
        return nil
    }

    /// Whether the name field holds the keyboard.
    @FocusState private var isNameFocused: Bool

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                CardContainer {
                    ValidatedField(label: "Group name", error: nameError) {
                        TextField("HDFC", text: $name)
                            .font(Typography.rowPrimary)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($isNameFocused)
                            .onSubmit(save)
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle("Rename group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .autoFocus($isNameFocused)
        .presentationDetents([.height(240), .large])
        .presentationDragIndicator(.visible)
    }

    /// Validates and saves, closing the sheet only on success (§7.11).
    private func save() {
        hasAttemptedSave = true
        guard nameError == nil else { return }
        Task {
            await model.rename(group, to: trimmed)
            dismiss()
        }
    }
}
