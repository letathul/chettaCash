import Foundation
import Domain

/// Keeps scheduled notifications in step with the data they describe (§10).
///
/// Runs on app foreground and after any edit that could move a triggering date. It
/// computes the full desired set, cancels this app's reminders that are no longer
/// wanted, and re-adds the rest — which is how "cancel and reschedule whenever a
/// triggering date or lead time changes" is honoured without tracking diffs by hand.
@MainActor
public struct ReminderCoordinator {
    /// Supplies accounts.
    private let accounts: any AccountRepository
    /// Supplies Vault products.
    private let products: any ProductRepository
    /// Reports whether notifications are allowed.
    private let authorizer: any NotificationAuthorizing
    /// Schedules and cancels notifications.
    private let scheduler: any NotificationScheduling

    /// Creates the coordinator.
    /// - Parameters:
    ///   - accounts: Supplies accounts.
    ///   - products: Supplies products.
    ///   - authorizer: Reports whether notifications are allowed.
    ///   - scheduler: Schedules and cancels notifications.
    public init(
        accounts: any AccountRepository,
        products: any ProductRepository,
        authorizer: any NotificationAuthorizing,
        scheduler: any NotificationScheduling
    ) {
        self.accounts = accounts
        self.products = products
        self.authorizer = authorizer
        self.scheduler = scheduler
    }

    /// Recomputes every reminder and reconciles it against what is scheduled.
    ///
    /// Does nothing when permission was never granted or has been revoked — iOS would
    /// drop the requests anyway, and re-prompting is not an option once answered.
    ///
    /// - Parameters:
    ///   - settings: Supplies the default reminder lead time.
    ///   - now: The moment to plan against.
    /// - Returns: The reminders now scheduled.
    @discardableResult
    public func sync(settings: AppSettings, now: Date = .now) async -> [ReminderRequest] {
        guard await authorizer.currentStatus() == .authorized else { return [] }

        let input = ReminderInput(
            accounts: (try? await accounts.accounts(includeClosed: true)) ?? [],
            products: (try? await products.products()) ?? [],
            defaultLeadTime: settings.defaultReminderLeadTime
        )
        let desired = ReminderPlanner.reminders(from: input, now: now)

        // Filter by prefix here as well as in the scheduler: never cancelling a
        // notification this app did not schedule is too important to rest on one
        // implementation remembering to do it.
        let pending = await scheduler.pendingReminderIdentifiers()
            .filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        let stale = Set(pending).subtracting(desired.map(\.id))
        await scheduler.cancel(identifiers: stale)
        await scheduler.schedule(desired)
        return desired
    }
}
