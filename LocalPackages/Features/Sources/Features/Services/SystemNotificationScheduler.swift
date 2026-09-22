import Foundation
import UserNotifications
import Domain

/// Schedules local notifications with `UNCalendarNotificationTrigger` (§10).
///
/// Calendar triggers rather than time-interval ones, because every reminder here is
/// anchored to a calendar date. If the user revokes permission in iOS Settings these
/// calls silently no-op, which needs no special handling.
public struct SystemNotificationScheduler: NotificationScheduling {

    /// Creates the scheduler.
    public init() {}

    /// The identifiers of reminders currently scheduled by this app.
    /// - Returns: The pending identifiers carrying this app's prefix.
    public func pendingReminderIdentifiers() async -> Set<String> {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(
            pending.map(\.identifier)
                .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        )
    }

    /// Schedules reminders, replacing any with the same identifier.
    ///
    /// Adding a request whose identifier already exists replaces it, which is what
    /// makes "cancel and reschedule on a date change" fall out for free.
    ///
    /// - Parameter reminders: The reminders to schedule.
    public func schedule(_ reminders: [ReminderRequest]) async {
        let center = UNUserNotificationCenter.current()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate
            )
            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Cancels reminders by identifier.
    /// - Parameter identifiers: The identifiers to cancel.
    public func cancel(identifiers: Set<String>) async {
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Array(identifiers))
    }
}
