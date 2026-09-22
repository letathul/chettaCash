import Foundation

/// How alike two merchant names are (§9.7).
///
/// Works on ``MerchantCategoryIndex/key(for:)`` slugs, so case, accents, punctuation and a
/// trailing branch number are already gone before anything is compared. One implementation
/// so the duplicate heuristic and the wizard's explanation never disagree about whether two
/// names look alike.
public enum MerchantSimilarity {

    /// How much two merchant names share, from `0` to `1`.
    ///
    /// Jaccard over the slug's hyphen-separated words: shared words over total distinct
    /// words. `SQ *BLUE BOTTLE 1042` and `Blue Bottle` share both of the latter's words out
    /// of three distinct, which is `0.67`.
    ///
    /// - Parameters:
    ///   - first: One merchant name.
    ///   - second: The other.
    /// - Returns: The overlap, or `0` when either name normalises to nothing.
    public static func overlap(_ first: String, _ second: String) -> Double {
        let left = tokens(of: first)
        let right = tokens(of: second)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let union = left.union(right)
        guard !union.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(union.count)
    }

    /// Whether two names begin with the same substantial word.
    ///
    /// Catches the case Jaccard misses: `STARBUCKS STORE 00421 SEATTLE` against `Starbucks`
    /// shares one word out of four, but the shared word is the shop.
    ///
    /// - Parameters:
    ///   - first: One merchant name.
    ///   - second: The other.
    ///   - minimumLength: How long the shared word must be to count. Short words like
    ///     `the` or `co` are shared by unrelated shops.
    /// - Returns: `true` when both begin with the same word of at least that length.
    public static func sharesLeadingToken(
        _ first: String,
        _ second: String,
        minimumLength: Int = 4
    ) -> Bool {
        guard let left = tokens(inOrder: first).first,
              let right = tokens(inOrder: second).first else { return false }
        guard left.count >= minimumLength, right.count >= minimumLength else { return false }
        return left == right || left.hasPrefix(right) || right.hasPrefix(left)
    }

    /// The distinct words of a merchant name.
    /// - Parameter merchant: The merchant name.
    /// - Returns: Its words, deduplicated.
    static func tokens(of merchant: String) -> Set<String> {
        Set(tokens(inOrder: merchant))
    }

    /// The words of a merchant name, in the order they appear.
    ///
    /// Words that are only digits are dropped: a store or terminal number is not part of
    /// the shop's name, and keeping it would make two visits to one shop look unalike.
    ///
    /// - Parameter merchant: The merchant name.
    /// - Returns: Its words.
    static func tokens(inOrder merchant: String) -> [String] {
        let key = MerchantCategoryIndex.key(for: merchant)
        guard !key.isEmpty else { return [] }
        return key
            .split(separator: "-")
            .map(String.init)
            .filter { !$0.allSatisfy(\.isNumber) }
    }
}
