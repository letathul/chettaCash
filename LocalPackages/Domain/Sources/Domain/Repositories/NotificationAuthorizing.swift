import Foundation

/// Whether the user has answered the system notification prompt (§7.10, §10).
public enum NotificationAuthorizationStatus: String, Sendable {
    /// The prompt has not been shown yet.
    case notDetermined
    /// Notifications are allowed.
    case authorized
    /// Notifications were refused, or later revoked in iOS Settings.
    case denied
}

/// Requests permission to post local notifications.
///
/// Declared here so `Features` can ask without importing `UserNotifications`, and so
/// tests can substitute a fake rather than driving a real system prompt.
///
/// Once the user answers, iOS will not show the prompt again — a Settings row wanting
/// to change this has to deep-link to iOS Settings ▸ Notifications (§7.10).
public protocol NotificationAuthorizing: Sendable {
    /// Reads the current authorization status.
    /// - Returns: What the user has already decided, if anything.
    func currentStatus() async -> NotificationAuthorizationStatus

    /// Shows the system permission prompt, if it has not been answered.
    /// - Returns: `true` when notifications are allowed afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool
}

/// Schedules and cancels local notifications (§10).
///
/// Declared here so `Features` can reconcile reminders without importing
/// `UserNotifications`, and so tests can assert on what would be scheduled.
public protocol NotificationScheduling: Sendable {
    /// The identifiers of reminders currently scheduled by this app.
    ///
    /// Only identifiers carrying ``ReminderPlanner/identifierPrefix`` are reported,
    /// so reconciliation never disturbs anything scheduled elsewhere.
    ///
    /// - Returns: The pending identifiers.
    func pendingReminderIdentifiers() async -> Set<String>

    /// Schedules reminders, replacing any with the same identifier.
    /// - Parameter reminders: The reminders to schedule.
    func schedule(_ reminders: [ReminderRequest]) async

    /// Cancels reminders by identifier.
    /// - Parameter identifiers: The identifiers to cancel.
    func cancel(identifiers: Set<String>) async
}
