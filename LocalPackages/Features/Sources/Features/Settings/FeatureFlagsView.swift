import SwiftUI
import Domain

/// Switches under-development features on and off (§7.6).
///
/// Reached from the Settings screen, and only in builds that did not come from the App
/// Store — the app decides that and passes it down as
/// ``SettingsViewModel/showsFeatureFlags``.
///
/// Each toggle writes as it is flipped rather than on dismissal, because the usual next
/// step after turning a flag on is to force-quit and relaunch.
public struct FeatureFlagsView: View {
    /// The Settings screen's view model, which holds the shared preferences.
    @State private var model: SettingsViewModel

    /// Creates the screen.
    /// - Parameter model: The Settings screen's view model.
    public init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    /// The view body.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                flagsCard
            }
            .padding(16)
        }
        .background(Palette.appBackground)
        .navigationTitle("Under development")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One toggle per flag, above a note on what turning one on means.
    private var flagsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Features").sectionLabel()
            CardContainer {
                VStack(alignment: .leading, spacing: 16) {
                    Text(
                        "These are unfinished. Anything you switch on may be incomplete, "
                            + "slow, or wrong about your money — check what it writes."
                    )
                    .font(Typography.rowSecondary)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.featureFlags, id: \.self) { flag in
                        Divider().overlay(Palette.borderSubtle)
                        row(for: flag)
                    }
                }
            }
        }
    }

    /// Builds one flag's toggle.
    /// - Parameter flag: The feature the toggle switches.
    /// - Returns: The row.
    private func row(for flag: FeatureFlag) -> some View {
        // The summary is the same in both states: it says what the feature is, which does
        // not change with the switch, rather than narrating the switch back to the user.
        let summary = flag.summary
        return ToggleRow(
            title: flag.title,
            isOn: Binding(
                get: { model.isEnabled(flag) },
                set: { model.setFeature(flag, enabled: $0) }
            )
        ) { _ in summary }
    }
}
