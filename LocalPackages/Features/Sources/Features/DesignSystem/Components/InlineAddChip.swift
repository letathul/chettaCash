import SwiftUI

/// The one inline "add new" chip, shared by custom categories and account groups (§8.4).
///
/// A dashed chip reveals a text field and a circular commit button. Submitting from
/// the keyboard or tapping the button both commit. A blank or whitespace-only entry
/// closes with no error and no addition.
///
/// Committing resolves the typed text against `existing` case-insensitively: a name
/// that already exists reports that entry's own spelling rather than creating a
/// duplicate. The caller adds the name if it is new, then selects it either way.
struct InlineAddChip: View {
    /// Chip text when collapsed, such as "+ Custom" or "+ New group".
    let title: String
    /// Entries already present, used to de-duplicate case-insensitively.
    let existing: [String]
    /// Called with the resolved name when the user commits a non-empty entry.
    let onCommit: (String) -> Void

    /// Whether the text field is showing.
    @State private var isEditing = false
    /// The name being typed.
    @State private var draft = ""
    /// Keyboard focus for the revealed field.
    @FocusState private var isFocused: Bool

    /// The view body.
    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                Button {
                    isEditing = true
                    isFocused = true
                } label: {
                    Text(title)
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
                        // The dashed border is a stroke with no fill, so the chip
                        // interior needs an explicit hit shape.
                        .tappableSurface()
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.2), value: isEditing)
    }

    /// The revealed text field and its commit button.
    private var editor: some View {
        // Trimmed once. Reading it twice inline meant two string allocations on every
        // character typed — once for the label, once for the disabled check.
        let trimmedDraft = draft.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 8) {
            TextField("Name", text: $draft)
                .font(Typography.rowSecondary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(commit)
                .frame(minWidth: 90)

            Button(action: commit) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Palette.brandPurple, in: .circle)
                    .iconTapTarget(expandedBy: 10)
            }
            .accessibilityLabel("Add \(trimmedDraft)")
            .disabled(trimmedDraft.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(Palette.brandPurple, lineWidth: 1.5) }
    }

    /// Trims, de-duplicates and reports the entry, then closes the editor.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            draft = ""
            isFocused = false
            isEditing = false
        }
        guard !trimmed.isEmpty else { return }
        let match = existing.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        onCommit(match ?? trimmed)
    }
}
