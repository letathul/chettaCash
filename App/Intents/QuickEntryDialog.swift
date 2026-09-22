import AppIntents
import Foundation
import Domain

/// Saying out loud what a Shortcut run actually did (§15.7).
///
/// What gets mentioned, and in what order, is ``QuickEntryReporter``'s decision and is tested
/// in the fast Domain suite; this file only turns each clause into words.
enum QuickEntryDialog {

    /// The parts of an entry the sentences are built from.
    ///
    /// Bundled rather than passed one by one, so the clause renderer keeps a short signature
    /// as the wording grows.
    struct Phrasing {
        /// The amount, already formatted in the user's currency.
        let amount: String
        /// Where it was spent or who it came from — the merchant, or the account when the
        /// merchant is bare.
        let place: String
        /// When it happened.
        let date: Date
        /// Which way the money moved, which decides the preposition.
        let type: Domain.TransactionType

        /// How the amount and the place are joined.
        ///
        /// "Logged £500 *at* Acme" is not what happened when Acme paid you.
        var joiner: String {
            switch type {
            case .income, .transferIn: return "from"
            default: return "at"
            }
        }
    }

    /// The spoken result for one run.
    /// - Parameters:
    ///   - report: What the run did beyond the obvious.
    ///   - phrasing: The parts of the entry to say.
    /// - Returns: The sentence Siri says.
    static func text(for report: QuickEntryReport, phrasing: Phrasing) -> String {
        QuickEntryReporter.clauses(for: report)
            .map { sentence(for: $0, phrasing: phrasing) }
            .joined(separator: " ")
    }

    /// One clause, as a sentence.
    /// - Parameters:
    ///   - clause: The clause to say.
    ///   - phrasing: The parts of the entry to say.
    /// - Returns: The sentence.
    private static func sentence(
        for clause: QuickEntryClause,
        phrasing: Phrasing
    ) -> String {
        let amount = phrasing.amount
        let place = phrasing.place
        switch clause {
        case .logged:
            return "Logged \(amount) \(phrasing.joiner) \(place)."
        case .alreadyLogged:
            return "\(amount) \(phrasing.joiner) \(place) is already logged, so I left it alone."
        case .createdAccount(let name):
            // Always named back. Nothing else on this path would tell the user a new account
            // now exists, and one appearing unannounced in their accounts list reads as a
            // bug rather than as what they just asked for.
            return "I made a new account for it, \(name)."
        case .parked(let doubt):
            return "I couldn't tell which account — \(reason(for: doubt)). It's waiting in Today."
        case .notYetPosted:
            return "It's dated \(dayText(phrasing.date)), so it won't move your balance until then."
        case .pinned(let label):
            return "I'll file \(place) under \(label) from now on."
        }
    }

    /// Why an entry was parked, in the middle of a sentence.
    /// - Parameter doubt: What the resolver could not settle.
    /// - Returns: The clause, lower case and without punctuation.
    private static func reason(for doubt: QuickExpenseAccountDoubt) -> String {
        switch doubt {
        case .unreadableNumber:
            return """
                that account number needs at least \
                \(QuickExpenseAccountResolver.digitCount) digits
                """
        case .ambiguousNumber(let count):
            return "\(count) accounts end in those digits"
        case .ambiguousName(let count):
            return "\(count) accounts answer to that name"
        case .unrecognisedName:
            return "no account answers to that name"
        case .unknownPickedAccount:
            return "the account this Shortcut was set to is no longer here"
        case .closedPickedAccount:
            return "that account is closed"
        case .nothingSupplied:
            return "none was given"
        }
    }

    /// A date as a day, for the spoken result.
    /// - Parameter date: The date to render.
    /// - Returns: The day, such as "3 October".
    private static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }
}
