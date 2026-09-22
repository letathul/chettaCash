import SwiftUI

/// Free-form tag entry (§8.4).
///
/// Accepts any typed tag, so no separate "custom tag" flow is needed. Tags are
/// unlimited, unlike categories (§4.8).
struct TagInput<Field: Hashable>: View {
    /// The tags currently applied.
    @Binding var tags: [String]
    /// The screen's keyboard focus, shared so its Done button can release this field.
    @FocusState.Binding var focus: Field?
    /// Which field this is, in the screen's focus enum.
    let field: Field

    /// The tag being typed.
    @State private var draft = ""

    /// The view body.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        chip(tag)
                    }
                }
            }
            TextField("Add a tag", text: $draft)
                .font(Typography.rowSecondary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // Return adds the tag and leaves the field up for the next one, so the
                // label reads "return" rather than "done".
                .submitLabel(.return)
                .focused($focus, equals: field)
                .onSubmit(commit)
        }
    }

    /// Builds one removable tag chip.
    /// - Parameter tag: The tag to render.
    /// - Returns: The chip view.
    private func chip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(Typography.rowSecondary)
                .foregroundStyle(Palette.textPrimary)
            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    // Held to 10pt rather than the full 44pt target: a wider area would
                    // reach back over the tag text and delete on a tap meant for it.
                    .iconTapTarget(expandedBy: 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.segmentTrack, in: .capsule)
    }

    /// Appends the typed tag if it is new, then clears the field.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return
        }
        tags.append(trimmed)
    }
}

/// Lays subviews out in rows, wrapping when the next one will not fit.
///
/// Tag chips grow with Dynamic Type, so a fixed `HStack` would clip them (§12).
struct FlowLayout: Layout {
    /// Gap between chips, horizontally and vertically.
    var spacing: CGFloat = 6

    /// Reports the size this layout needs.
    /// - Parameters:
    ///   - proposal: The size proposed by the parent.
    ///   - subviews: The chips to lay out.
    ///   - cache: Unused.
    /// - Returns: The required size.
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = layout(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        let height = rows.map(\.height).reduce(0) { $0 + $1 + spacing }
        return CGSize(
            width: proposal.replacingUnspecifiedDimensions().width,
            height: max(0, height - spacing)
        )
    }

    /// Places each chip.
    /// - Parameters:
    ///   - bounds: The region to lay out within.
    ///   - proposal: The size proposed by the parent.
    ///   - subviews: The chips to place.
    ///   - cache: Unused.
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var rowTop = bounds.minY
        for row in layout(width: bounds.width, subviews: subviews) {
            var cursorX = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: cursorX, y: rowTop),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                cursorX += size.width + spacing
            }
            rowTop += row.height + spacing
        }
    }

    /// One row of chips and its height.
    private struct Row {
        /// Indices of the chips in this row.
        var indices: [Int] = []
        /// The tallest chip in this row.
        var height: CGFloat = 0
    }

    /// Groups chips into rows that fit the available width.
    /// - Parameters:
    ///   - width: The available width.
    ///   - subviews: The chips to group.
    /// - Returns: The rows.
    private func layout(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        var cursorX: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursorX + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
                cursorX = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            cursorX += size.width + spacing
        }
        return rows
    }
}
