import Foundation
import UserNotifications
import Domain

/// Asks iOS for permission to post local notifications (§7.10, §10).
///
/// Local only — there is no push and no server. If the user later revokes permission
/// in iOS Settings, scheduling calls silently no-op, which needs no special handling
/// beyond not prompting twice.
/// Stateless by design: `UNUserNotificationCenter` is not `Sendable`, and holding one
/// would drag that across every actor boundary this crosses. `current()` is cheap and
/// safe to call from anywhere, so it is fetched per call instead. Tests substitute a
/// fake conforming to ``NotificationAuthorizing`` rather than injecting a centre.
public struct SystemNotificationAuthorizer: NotificationAuthorizing {

    /// Creates the authorizer.
    public init() {}

    /// Reads the current authorization status.
    /// - Returns: What the user has already decided, if anything.
    public func currentStatus() async -> NotificationAuthorizationStatus {
        switch await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        default:
            return .denied
        }
    }

    /// Shows the system permission prompt, if it has not been answered.
    ///
    /// Asking again after the user has answered is a no-op at the system level, so
    /// this reports the standing decision rather than pretending to re-prompt.
    ///
    /// - Returns: `true` when notifications are allowed afterwards.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
        return granted ?? false
    }
}
