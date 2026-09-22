import SwiftUI
import Domain

/// The account form's group picker (§8.4).
///
/// Only the Edit Account sheet shows this. Accounts are *created* through a sheet that
/// is already scoped to one group, so the picker's job is reassignment, not choosing —
/// which is why there is no empty-group case to handle here.
struct AccountGroupField: View {
    /// The form being edited.
    @Bindable var form: AccountFormState
    /// Groups available to choose from.
    let groups: [Domain.AccountGroup]
    /// Creates a group from the inline "+ New group" chip.
    let onAddGroup: (String) -> Void
    /// Whether the field is disabled, as it is for a closed account (§4.7).
    var isReadOnly = false

    /// The view body.
    var body: some View {
        ValidatedField(label: "Group", error: form.groupError) {
            FlowLayout(spacing: 8) {
                ForEach(groups) { group in
                    SelectableChip(
                        title: group.name,
                        isSelected: form.groupID == group.id
                    ) {
                        form.groupID = group.id
                    }
                }
                if !isReadOnly {
                    InlineAddChip(
                        title: "+ New group",
                        existing: groups.map(\.name),
                        onCommit: onAddGroup
                    )
                }
            }
        }
        .disabled(isReadOnly)
    }
}
