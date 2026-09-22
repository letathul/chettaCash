import Foundation

/// The rules a *new* category label must satisfy (§4.8).
///
/// These apply only where a category is being **created** — the Shortcut's free-text
/// field, and the inline "+ Custom" chip. Matching an *existing* category is never
/// gated on them: a label the user made before this rule existed, or through some
/// other route, must still be findable by name.
///
/// The cap is on ``maxLength`` grapheme clusters rather than UTF-16 units, because a
/// user counting characters counts what they see. Emoji are refused rather than
/// stripped: silently turning "Coffee ☕️" into "Coffee" invents a label nobody typed,
/// and a category label is how spending is read back for years afterwards.
public enum CategoryNaming {

    /// The most characters a new category label may carry.
    public static let maxLength = 15

    /// Why a label was refused.
    public enum Problem: Error, Equatable, Sendable {
        /// Nothing was left after trimming.
        case empty
        /// The label was longer than ``maxLength``, which is the count carried here.
        case tooLong(Int)
        /// The label contained an emoji.
        case containsEmoji
    }

    /// Normalises and checks a label offered as a new category.
    ///
    /// Whitespace is trimmed and internal runs collapsed first, so `"  Food   court "`
    /// is measured as `"Food court"` rather than failing on padding the user cannot see.
    ///
    /// - Parameter raw: The label as typed.
    /// - Returns: The normalised label to store.
    /// - Throws: A ``Problem`` when the label is empty, too long, or carries an emoji.
    public static func validated(_ raw: String) throws -> String {
        let collapsed = raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { throw Problem.empty }
        guard !containsEmoji(collapsed) else { throw Problem.containsEmoji }
        let count = collapsed.count
        guard count <= maxLength else { throw Problem.tooLong(count) }
        return collapsed
    }

    /// Reports whether any character in a label is emoji.
    ///
    /// `Unicode.Scalar.Properties.isEmoji` alone is not the test: ASCII digits, `#`
    /// and `*` all report `true` because they are the bases of keycap sequences. So a
    /// scalar only counts as emoji when it either *presents* as emoji by default, or
    /// is emoji-capable **and** outside ASCII. The joiners and modifiers are listed
    /// separately because they carry no emoji property of their own, yet a label
    /// containing one is unquestionably an emoji sequence.
    ///
    /// - Parameter text: The label to test.
    /// - Returns: `true` when the label contains emoji.
    public static func containsEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isEmojiScalar)
    }

    /// Reports whether one scalar belongs to an emoji sequence.
    /// - Parameter scalar: The scalar to test.
    /// - Returns: `true` when it is emoji, a joiner, or a modifier.
    private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isEmojiPresentation { return true }
        if scalar.properties.isEmoji, scalar.value > 0x7F { return true }
        switch scalar.value {
        // Zero-width joiner, and the variation selector that forces emoji presentation.
        case 0x200D, 0xFE0F: return true
        // Regional indicators, which pair up into flags.
        case 0x1F1E6...0x1F1FF: return true
        // Skin-tone modifiers.
        case 0x1F3FB...0x1F3FF: return true
        default: return false
        }
    }
}
