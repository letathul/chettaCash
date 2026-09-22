import SwiftUI
import Domain

/// Step 2: create a group, then add accounts under it (§7.10).
///
/// Two phases rather than a fourth onboarding step. The group page is re-entrant —
/// "+ New group" from the list has to come back to the list — which a linear
/// ``OnboardingStep`` cannot express without rewinding the progress dots. It is also
/// a sub-screen of "add your accounts", not a peer of it.
struct OnboardingAccountsStep: View {
    /// The flow's view model.
    let model: OnboardingViewModel
    /// Moves to the next step.
    let onContinue: () -> Void
    /// Bypasses account creation entirely (§7.10).
    let onSkip: () -> Void

    /// Which phase is showing.
    @State private var phase: Phase?
    /// The group whose add-account sheet is open.
    @State private var addingTo: Domain.AccountGroup?

    /// The two phases this step moves between.
    private enum Phase {
        /// The dedicated group page.
        case group
        /// The list of groups and their accounts.
        case list
    }

    /// The view body.
    var body: some View {
        content
            .sheet(item: $addingTo) { group in
                AddAccountSheet(
                    group: group,
                    sortIndex: model.nextSortIndex(inGroup: group.id)
                ) { await model.add($0) }
            }
            // Resolved here rather than in the initialiser: `model.load()` populates
            // the groups after this view is first built.
            .onAppear { phase = phase ?? (model.groups.isEmpty ? .group : .list) }
    }

    /// The current phase.
    @ViewBuilder
    private var content: some View {
        switch phase {
        case .group, nil:
            CreateGroupView(
                existingNames: model.groups.map(\.name),
                onCreate: create(named:),
                onCancel: model.groups.isEmpty ? nil : { phase = .list }
            )
        case .list:
            OnboardingGroupsStep(
                model: model,
                onAddAccount: { addingTo = $0 },
                onNewGroup: { phase = .group },
                onContinue: onContinue,
                onSkip: onSkip
            )
        }
    }

    /// Saves the group, then opens its add-account sheet so the pair reads as one flow.
    /// - Parameter name: The group's display name.
    private func create(named name: String) {
        Task {
            guard let group = await model.addGroup(named: name) else { return }
            phase = .list
            addingTo = group
        }
    }
}
