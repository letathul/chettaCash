import SwiftUI
import Domain

/// The dedicated "create a group" page (§7.6, §7.10).
public struct CreateGroupView: View {
    /// Names already taken, used to refuse a duplicate.
    let existingNames: [String]
    /// Called with the trimmed name once the entry is valid.
    let onCreate: (String) -> Void
    /// Backs out without creating, or `nil` where there is nothing to back out to.
    var onCancel: (() -> Void)?

    /// The name being typed.
    @State private var name = ""
    /// Whether Create has been attempted, which is what reveals validation (§7.11).
    @State private var hasAttemptedSave = false
    /// Keyboard focus state control.
    @FocusState private var isNameFocused: Bool

    /// Existing names, trimmed and lowercased, for case-insensitive duplicate checks.
    ///
    /// Built once in `init`. It was a computed property despite its comment, so it
    /// rebuilt the whole set on every body pass — which is every keystroke, because
    /// `nameError` reads it.
    private let normalizedExistingNames: Set<String>

    /// The trimmed group name.
    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name field's error, or `nil` when valid.
    private var nameError: String? {
        guard hasAttemptedSave else { return nil }
        let currentTrimmed = trimmed
        if currentTrimmed.isEmpty {
            return "Group name is required."
        }
        if normalizedExistingNames.contains(currentTrimmed.lowercased()) {
            return "You already have a group with this name."
        }
        return nil
    }

    public init(
        existingNames: [String],
        onCreate: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.existingNames = existingNames
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.normalizedExistingNames = Set(existingNames.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    /// The view body.
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    CardContainer {
                        ValidatedField(label: "Group name", error: nameError) {
                            TextField("eg: TD", text: $name)
                                .font(Typography.rowPrimary)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isNameFocused)
                                .onSubmit(create)
                        }
                    }
                    presets(GroupPresets.banks, titled: "Banks")
                    presets(GroupPresets.lifeAreas, titled: "Or a part of your life")
                }
                .padding(16)
            }
            footer
        }
        .background(Palette.appBackground)
        .scrollDismissesKeyboard(.interactively)
        .autoFocus($isNameFocused)
    }

    /// The page's title and explanation.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Create a group")
                .font(Typography.screenTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("A group is just a folder for your accounts — a bank, or a part of "
               + "your life. You'll add the accounts themselves next.")
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    /// One row of tappable name suggestions.
    private func presets(_ options: [String], titled title: String) -> some View {
        // The typed name is lowercased once, and each preset is matched against the
        // lowercased copy built with the row rather than re-lowercased per body pass.
        let currentTrimmedLower = trimmed.lowercased()
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionLabel()
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    SelectableChip(
                        title: option,
                        isSelected: currentTrimmedLower == option.lowercased()
                    ) {
                        name = option
                        isNameFocused = true
                    }
                }
            }
        }
    }

    /// The create button, and the cancel link where one applies.
    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: create) {
                Text("Create group")
                    .font(Typography.rowPrimary.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Palette.brandPurple, in: .capsule)
            }
            .buttonStyle(.plain)

            if let onCancel {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .iconTapTarget()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// Validates and reports the name, leaving persistence to the caller (§7.11).
    private func create() {
        hasAttemptedSave = true
        guard nameError == nil else { return }
        onCreate(trimmed)
    }
}

/// The name suggestions the group page offers.
private enum GroupPresets {
    static let banks = ["TD", "SCOTIA", "RBC", "HDFC", "Bank of America"]
    static let lifeAreas = ["Personal", "Work", "Family", "Cash", "Savings"]
}
