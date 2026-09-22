import Foundation

/// Decides when a scheduled backup is due (§9.4).
///
/// Archives are written "on the user's schedule" — off, weekly or monthly — which
/// means a check on app foreground comparing the newest archive against the interval,
/// not a background timer. An app that has not been opened for a month writes one
/// archive when it next is, rather than backfilling four.
public enum BackupSchedule {

    /// Whether a scheduled backup is due.
    /// - Parameters:
    ///   - interval: The user's chosen interval.
    ///   - lastBackup: When the newest archive was written, if any.
    ///   - now: The moment being checked.
    ///   - calendar: The calendar to measure the interval in.
    /// - Returns: `true` when an archive should be written.
    public static func isDue(
        interval: BackupInterval,
        lastBackup: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let component = component(for: interval) else { return false }
        // Never backed up: the first scheduled run writes one.
        guard let lastBackup else { return true }
        guard let next = calendar.date(byAdding: component, value: 1, to: lastBackup) else {
            return false
        }
        return now >= next
    }

    /// The date an archive's filename encodes.
    ///
    /// Archives are named `chetta-cash-backup-YYYY-MM-DD.zip` (§9.3), so the newest
    /// one's date can be read back without storing it separately.
    ///
    /// - Parameters:
    ///   - fileName: The archive's file name.
    ///   - calendar: The calendar to build the date in.
    /// - Returns: The date, or `nil` when the name does not match.
    public static func date(
        fromArchiveName fileName: String,
        calendar: Calendar = .current
    ) -> Date? {
        let pattern = /chetta-cash-backup-(\d{4})-(\d{2})-(\d{2})\.zip/
        guard let match = fileName.wholeMatch(of: pattern),
              let year = Int(match.output.1),
              let month = Int(match.output.2),
              let day = Int(match.output.3) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The calendar component one interval spans.
    /// - Parameter interval: The chosen interval.
    /// - Returns: The component, or `nil` when backups are off.
    private static func component(for interval: BackupInterval) -> Calendar.Component? {
        switch interval {
        case .off: return nil
        case .weekly: return .weekOfYear
        case .monthly: return .month
        }
    }
}
