import Foundation
import Testing
@testable import Domain

/// Phase 14: scheduled backups actually come due (§9.4).
@Suite("Backup schedule")
struct BackupScheduleTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Builds a UTC date at midday.
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month.
    ///   - day: The day.
    /// - Returns: That instant.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    @Test("Backups switched off are never due")
    func offIsNeverDue() {
        #expect(BackupSchedule.isDue(
            interval: .off, lastBackup: nil, now: date(2026, 9, 12), calendar: calendar
        ) == false)
    }

    @Test("The first scheduled backup is due immediately")
    func firstBackupIsDue() {
        #expect(BackupSchedule.isDue(
            interval: .weekly, lastBackup: nil, now: date(2026, 9, 12), calendar: calendar
        ))
    }

    @Test("A weekly backup comes due a week later, not before")
    func weeklyInterval() {
        let last = date(2026, 9, 5)

        #expect(BackupSchedule.isDue(
            interval: .weekly, lastBackup: last, now: date(2026, 9, 11), calendar: calendar
        ) == false)
        #expect(BackupSchedule.isDue(
            interval: .weekly, lastBackup: last, now: date(2026, 9, 12), calendar: calendar
        ))
    }

    @Test("A monthly backup comes due a month later, not before")
    func monthlyInterval() {
        let last = date(2026, 8, 12)

        #expect(BackupSchedule.isDue(
            interval: .monthly, lastBackup: last, now: date(2026, 9, 11), calendar: calendar
        ) == false)
        #expect(BackupSchedule.isDue(
            interval: .monthly, lastBackup: last, now: date(2026, 9, 12), calendar: calendar
        ))
    }

    @Test("A long gap writes one archive, not one per missed period")
    func longGapWritesOnce() {
        // Four months away: the next foreground is due once, and once written the
        // schedule resets rather than backfilling.
        let last = date(2026, 5, 12)
        let now = date(2026, 9, 12)

        #expect(BackupSchedule.isDue(
            interval: .monthly, lastBackup: last, now: now, calendar: calendar
        ))
        #expect(BackupSchedule.isDue(
            interval: .monthly, lastBackup: now, now: now, calendar: calendar
        ) == false)
    }

    @Test("An archive's date is read back from its filename")
    func dateFromArchiveName() {
        #expect(BackupSchedule.date(
            fromArchiveName: "chetta-cash-backup-2026-09-12.zip", calendar: calendar
        ) == calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)))
    }

    @Test("An unrecognised filename yields no date", arguments: [
        "backup.zip", "chetta-cash-backup-2026-09.zip", "chetta-cash-backup-2026-09-12.txt"
    ])
    func unrecognisedNames(fileName: String) {
        #expect(BackupSchedule.date(fromArchiveName: fileName, calendar: calendar) == nil)
    }

    @Test("The name a backup is written under round-trips through the reader")
    func nameRoundTrips() {
        let when = date(2026, 12, 3)
        let name = BackupArchive.fileName(for: when, calendar: calendar)

        #expect(BackupSchedule.date(fromArchiveName: name, calendar: calendar)
                == calendar.startOfDay(for: when))
    }
}
