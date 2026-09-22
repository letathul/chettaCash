import Foundation

/// A feature still under development, switchable from Settings in non-release builds.
///
/// A flag is a statement of intent, not of capability. Whatever a flag gates keeps its
/// own check that the app wired the repositories it needs — turning a flag on must never
/// be enough, on its own, to show a screen that cannot work.
public enum FeatureFlag: String, Codable, Sendable, CaseIterable {
    /// Reading a card statement PDF, image or CSV export into the ledger (§4.2).
    case statementScanner

    /// Every flag in the order the menu lists them, sorted by title and computed once.
    ///
    /// Sorted by title rather than left in declaration order so adding a flag does not
    /// reshuffle the rows a tester has learned the position of. A stored constant rather
    /// than a computed property because the menu reads it from a view body, where a sort
    /// on every evaluation is exactly the string work §UI-1 forbids.
    public static let menuOrder: [FeatureFlag] = allCases.sorted { $0.title < $1.title }

    /// The toggle's label in the feature-flag menu.
    public var title: String {
        switch self {
        case .statementScanner: return "Card statement scanner"
        }
    }

    /// The line beneath the toggle saying what turning it on does.
    public var summary: String {
        switch self {
        case .statementScanner:
            return "Adds Import statement to Settings, which reads a card statement PDF, "
                 + "photo or CSV export and offers its rows for review."
        }
    }

    /// Whether a build with no stored preference has this switched on.
    ///
    /// Every flag starts off. A flag that defaults on is one that has stopped being a
    /// flag and should be deleted along with its checks.
    public var isEnabledByDefault: Bool {
        switch self {
        case .statementScanner: return false
        }
    }
}
