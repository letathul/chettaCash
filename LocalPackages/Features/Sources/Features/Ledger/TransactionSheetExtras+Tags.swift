import SwiftUI
import Domain

/// Tags a scan suggests but never applies (§4.8, §9.7).
///
/// Split from ``TransactionSheetExtras`` to keep each file within the 300-line limit.
extension TransactionSheet {

    /// Tags this user habitually puts on this merchant, offered as chips.
    ///
    /// Suggested rather than applied, deliberately. Tags are unlimited free text, so a
    /// scan that wrote them itself would quietly grow a vocabulary nobody chose — and
    /// silently mis-tagging a purchase is harder to notice than an untagged one. A chip
    /// costs one tap and says plainly that it came from the receipt.
    @ViewBuilder
    var tagSuggestions: some View {
        let offered = suggestedTags
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested from past purchases here")
                    .font(Typography.errorCaption)
                    .foregroundStyle(Palette.textSecondary)
                FlowLayout(spacing: 6) {
                    ForEach(offered, id: \.self) { tag in
                        SelectableChip(title: "+ \(tag)", isSelected: false) {
                            acceptTag(tag)
                        }
                        .accessibilityLabel("Add tag \(tag)")
                    }
                }
            }
        }
    }

    /// The suggestions not already on the form.
    ///
    /// Filtered case-insensitively, matching ``TagInput``'s own de-duplication, so a
    /// tag the user typed by hand does not come back as a chip.
    var suggestedTags: [String] {
        guard let scanPrefill, form.mode != .transfer else { return [] }
        let existing = Set(form.tags.map { $0.lowercased() })
        return scanPrefill.suggestedTags.filter { !existing.contains($0.lowercased()) }
    }
}
