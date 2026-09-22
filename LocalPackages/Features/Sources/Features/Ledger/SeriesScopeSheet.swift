import SwiftUI
import Domain

/// Asks how far an edit or delete should reach through a series (§4.5).
///
/// Both edit and delete must prompt for scope. The retroactive option carries an
/// explicit, concrete warning before proceeding — not a generic "are you sure".
struct SeriesScopeSheet: View {
    /// Whether this prompt is for a delete rather than an edit.
    let isDelete: Bool
    /// Called with the chosen scope once any warning is accepted.
    let onChoose: (SeriesScope) -> Void

    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss
    /// The scope awaiting confirmation, when it rewrites history.
    @State private var pendingScope: SeriesScope?

    /// The view body.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isDelete
                         ? "This transaction is part of a repeating series."
                         : "You are editing part of a repeating series.")
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                    ForEach(SeriesScope.allCases) { scope in
                        scopeButton(scope)
                    }
                }
                .padding(16)
            }
            .background(Palette.appBackground)
            .navigationTitle(isDelete ? "Delete Series" : "Edit Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                isDelete ? "Delete every occurrence?" : "Change your recorded history?",
                isPresented: Binding(
                    get: { pendingScope != nil },
                    set: { if !$0 { pendingScope = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingScope = nil }
                Button(isDelete ? "Delete all" : "Apply to all", role: .destructive) {
                    guard let pendingScope else { return }
                    onChoose(pendingScope)
                    dismiss()
                }
            } message: {
                Text("This will change your recorded history. "
                   + "Past balances, totals and charts will update.")
            }
        }
    }

    /// One scope option.
    /// - Parameter scope: The scope the button chooses.
    /// - Returns: The button view.
    private func scopeButton(_ scope: SeriesScope) -> some View {
        Button {
            if scope.rewritesHistory {
                pendingScope = scope
            } else {
                onChoose(scope)
                dismiss()
            }
        } label: {
            CardContainer {
                VStack(alignment: .leading, spacing: 6) {
                    Text(scope.title(isDelete: isDelete))
                        .font(Typography.rowPrimary)
                        .foregroundStyle(
                            scope.rewritesHistory ? Palette.negativeRed : Palette.textPrimary
                        )
                    Text(scope.explanation(isDelete: isDelete))
                        .font(Typography.rowSecondary)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// User-facing copy for the three series scopes (§4.5).
extension SeriesScope {
    /// The option's title.
    /// - Parameter isDelete: Whether the prompt is for a delete.
    /// - Returns: The title.
    func title(isDelete: Bool) -> String {
        switch self {
        case .thisOccurrence: return "This occurrence only"
        case .thisAndFuture: return isDelete ? "This and future" : "This and future"
        case .allIncludingPast: return "All, including past"
        }
    }

    /// What the option does, in the user's terms.
    /// - Parameter isDelete: Whether the prompt is for a delete.
    /// - Returns: The explanation.
    func explanation(isDelete: Bool) -> String {
        switch self {
        case .thisOccurrence:
            return isDelete
                ? "Removes just this one. The series keeps running."
                : "Detaches this one from the series. Future charges are unaffected."
        case .thisAndFuture:
            return isDelete
                ? "Removes this one and stops the series. Past occurrences stay."
                : "Ends the current series here and starts a new one with your changes."
        case .allIncludingPast:
            return isDelete
                ? "Removes every occurrence, including ones already recorded."
                : "Applies your changes to every occurrence, including ones already recorded."
        }
    }
}
