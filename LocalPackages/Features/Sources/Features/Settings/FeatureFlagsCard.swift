import SwiftUI

/// The way into the feature-flag menu, shown in non-App Store builds only (§7.6).
///
/// A card of its own rather than a property on ``SettingsView``, which is what the Cloud
/// backup, Security and Import statement cards already do, and what keeps that file
/// within the 300-line limit.
struct FeatureFlagsCard: View {
    /// What tapping the row does.
    let onOpen: () -> Void

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Under development").sectionLabel()
            CardContainer {
                Button(action: onOpen) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feature flags").font(Typography.rowPrimary)
                            Text("Switch on what is not finished yet")
                                .font(Typography.rowSecondary)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .tappableSurface()
            }
        }
    }
}
