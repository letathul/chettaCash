import Foundation

/// Recognising a Shortcut run that has already happened (§15.6).
///
/// A Siri retry, a re-tapped Shortcut and an automation firing twice all look identical to
/// the app: each builds a fresh ``Transaction`` with its own identifier, and the repository
/// upserts on that identifier, so each writes a second row. Nothing else in the app has this
/// problem — a person typing a transaction in can see the one they already typed.
///
/// The guard is deliberately narrow. Suppressing a real second purchase is a worse failure
/// than allowing a duplicate: the duplicate is visible in the Ledger and can be deleted,
/// where the suppressed purchase is money that simply never appears.
public enum QuickExpenseDuplicateGuard {

    /// How close two identical entries must be to count as one run repeated.
    ///
    /// Two minutes. Long enough to cover a Siri retry, a tap that seemed not to register and
    /// an automation that fired twice on one notification; short enough that two genuine
    /// £4.50 coffees at one shop on one afternoon are two coffees.
    public static let window: TimeInterval = 120

    /// The stored entry this one repeats, if it repeats one.
    ///
    /// Three conditions, all required:
    ///
    /// 1. **The same fingerprint.** ``TransactionFingerprint`` already means same account,
    ///    same day, same signed amount, same normalised merchant — which is its own
    ///    definition of the same purchase, and the one statement import already trusts.
    /// 2. **Within `window`.** The fingerprint's day granularity is far too coarse on its
    ///    own. ``Transaction`` carries no created-at, but a Shortcut dates an entry `.now`
    ///    unless told otherwise, so a retry is seconds away and an automation passing a fixed
    ///    timestamp matches to the second.
    /// 3. **The stored entry came from a Shortcut.** Scoped by
    ///    ``QuickExpensePlanner/originTag`` so the guard can never suppress a twin the user
    ///    typed in by hand — they meant that one, and they were watching when they did it.
    ///
    /// - Parameters:
    ///   - candidate: The entry about to be written.
    ///   - recent: The stored entries to compare against, normally the candidate's own day.
    ///   - window: How close in time two identical entries must be.
    ///   - calendar: The calendar deciding which day a date falls on.
    /// - Returns: The entry already stored, or `nil` when this one is new.
    public static func duplicate(
        of candidate: Transaction,
        among recent: [Transaction],
        window: TimeInterval = window,
        calendar: Calendar = .current
    ) -> Transaction? {
        let key = TransactionFingerprint.key(for: candidate, calendar: calendar)
        return recent.first { stored in
            stored.id != candidate.id
                && isShortcutWritten(stored)
                && abs(stored.date.timeIntervalSince(candidate.date)) <= window
                && TransactionFingerprint.key(for: stored, calendar: calendar) == key
        }
    }

    /// Whether a stored entry was written by a Shortcut.
    ///
    /// Case-insensitive, matching the tag field's own rule — someone who typed "Shortcut"
    /// into the tags parameter kept their capitalisation, and the tag still means what it
    /// says.
    ///
    /// - Parameter transaction: The entry to check.
    /// - Returns: Whether it carries the origin tag.
    public static func isShortcutWritten(_ transaction: Transaction) -> Bool {
        transaction.tags.contains {
            $0.caseInsensitiveCompare(QuickExpensePlanner.originTag) == .orderedSame
        }
    }

    /// The day a candidate's duplicate could be hiding in.
    ///
    /// The fingerprint puts the day in the key, so nothing outside the candidate's own day
    /// can match however close the clock says it is — which keeps the fetch to one day
    /// rather than the whole ledger.
    ///
    /// - Parameters:
    ///   - candidate: The entry about to be written.
    ///   - calendar: The calendar deciding day boundaries.
    /// - Returns: The range to fetch, or `nil` if the calendar cannot place the day.
    public static func searchRange(
        for candidate: Transaction,
        calendar: Calendar = .current
    ) -> ClosedRange<Date>? {
        let start = calendar.startOfDay(for: candidate.date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return start...next.addingTimeInterval(-1)
    }
}
