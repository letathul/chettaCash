import SwiftUI

/// Skeleton placeholder shown while a query is still loading (§7.0).
///
/// Relevant mainly while CloudKit hydrates on first launch.
struct SkeletonRow: View {
    /// How wide the placeholder bar is, as a fraction of the available width.
    var widthFraction: CGFloat = 1

    /// Drives the shimmer.
    @State private var isAnimating = false

    /// The view body.
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Palette.segmentTrack)
            .frame(height: 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: widthFraction, anchor: .leading)
            .opacity(isAnimating ? 0.45 : 1)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
            .accessibilityHidden(true)
    }
}

/// A card of skeleton rows, for a list that has not loaded yet (§7.0).
struct SkeletonCard: View {
    /// How many placeholder rows to show.
    var rowCount: Int = 3

    /// The view body.
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<rowCount, id: \.self) { index in
                    SkeletonRow(widthFraction: index.isMultiple(of: 2) ? 0.9 : 0.65)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The first-run empty state: a query returned zero rows because nothing exists yet (§7.0).
///
/// Distinct from ``FilteredEmptyNotice``, which means the data exists but the current
/// filters exclude all of it. Keeping the two apart is a view-logic requirement, not
/// a copy preference.
struct EmptyStateView: View {
    /// SF Symbol shown above the message.
    let icon: String
    /// The headline, such as "No accounts yet".
    let title: String
    /// A sentence explaining what to do next.
    let message: String
    /// The call-to-action's label, or `nil` for no button.
    var actionTitle: String?
    /// Starts the relevant flow.
    var action: (() -> Void)?

    /// The view body.
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(Palette.brandPurple)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.rowPrimary)
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                // Styling lives inside the label: chained onto the Button it would paint
                // a capsule behind a control only as wide as its text (§8.4).
                Button(action: action) {
                    Text(actionTitle)
                        .font(Typography.rowPrimary)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Palette.brandPurple, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// The filtered-to-zero notice (§7.0).
///
/// Shown inline, in place of the rows only — it never replaces the screen with the
/// first-run empty state, because the user's filters are the reason and the screen's
/// controls must stay reachable to undo them.
struct FilteredEmptyNotice: View {
    /// The message, such as "No transactions match these filters yet."
    let message: String

    /// The view body.
    var body: some View {
        Text(message)
            .font(Typography.rowSecondary)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

/// A failure banner shown above otherwise-normal content (§7.0).
///
/// It never replaces the screen: the content stays visible and usable underneath,
/// and Retry does real work.
struct ErrorBanner: View {
    /// What went wrong, in plain words.
    let message: String
    /// Retries the failed work.
    let retry: () -> Void

    /// The view body.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.rowSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text("Retry")
                    .font(Typography.rowSecondary.weight(.semibold))
                    .iconTapTarget()
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.errorBannerText)
        .padding(12)
        .background(Palette.errorBannerBackground, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Palette.errorBannerBorder, lineWidth: 1)
        }
    }
}
