import Foundation

/// What a reminder is about (§10).
public enum ReminderKind: String, Sendable {
    /// A free trial is about to end.
    case trialEnding
    /// A warranty or expiry date is approaching.
    case warrantyExpiring
    /// A card payment is due.
    case cardPaymentDue
}

/// One local notification to schedule (§10).
public struct ReminderRequest: Identifiable, Equatable, Sendable {
    /// A deterministic identifier, so rescheduling replaces rather than duplicates.
    public let id: String
    /// What the reminder is about.
    public let kind: ReminderKind
    /// The notification's title.
    public let title: String
    /// The notification's body.
    public let body: String
    /// When it should fire.
    public let fireDate: Date

    /// Creates a request.
    /// - Parameters:
    ///   - id: A deterministic identifier.
    ///   - kind: What the reminder is about.
    ///   - title: The notification's title.
    ///   - body: The notification's body.
    ///   - fireDate: When it should fire.
    public init(id: String, kind: ReminderKind, title: String, body: String, fireDate: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

/// What reminders are derived from.
public struct ReminderInput: Sendable {
    /// Every account, closed ones included.
    public var accounts: [Account]
    /// Every product.
    public var products: [Product]
    /// The lead time used when a reminder is set to ``ReminderLeadTime/useDefault``.
    public var defaultLeadTime: ReminderLeadTime

    /// Creates the inputs.
    /// - Parameters:
    ///   - accounts: Every account.
    ///   - products: Every product.
    ///   - defaultLeadTime: The fallback lead time.
    public init(
        accounts: [Account] = [],
        products: [Product] = [],
        defaultLeadTime: ReminderLeadTime = .threeDaysBefore
    ) {
        self.accounts = accounts
        self.products = products
        self.defaultLeadTime = defaultLeadTime
    }
}

/// Computes which local notifications should exist (§10).
///
/// Pure: it decides what should be scheduled, and the caller reconciles that against
/// what iOS currently holds. Identifiers are deterministic, so a changed date
/// replaces the existing request rather than adding a second one.
public enum ReminderPlanner {

    /// The fixed lead on a card payment reminder.
    ///
    /// Not configurable — §10 is explicit that this one has no picker.
    public static let cardLeadDays = 3

    /// The hour of day reminders fire at.
    ///
    /// The underlying values are calendar dates with no time, and a notification at
    /// midnight is useless, so reminders land mid-morning local time.
    public static let fireHour = 9

    /// How many card payment reminders are scheduled ahead per card.
    ///
    /// Card due dates recur monthly, but the three-day lead can fall in the previous
    /// month, so a single repeating trigger cannot express them. Several one-shot
    /// triggers are scheduled instead and topped up on each app foreground.
    public static let cardMonthsAhead = 3

    /// The identifier prefix owned by this app's reminders.
    ///
    /// Reconciliation only ever cancels identifiers carrying this prefix, so
    /// notifications scheduled by anything else are left alone.
    public static let identifierPrefix = "chettacash.reminder."

    /// Builds every reminder that should currently be scheduled.
    /// - Parameters:
    ///   - input: Everything reminders are derived from.
    ///   - now: The moment to plan against. Reminders already past are skipped.
    ///   - calendar: The calendar to compute dates in.
    /// - Returns: The reminders, soonest first.
    public static func reminders(
        from input: ReminderInput,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ReminderRequest] {
        let productReminders = input.products.flatMap {
            reminders(for: $0, defaultLead: input.defaultLeadTime, now: now, calendar: calendar)
        }
        let cards = input.accounts.flatMap {
            cardReminders(for: $0, now: now, calendar: calendar)
        }
        return (productReminders + cards).sorted { $0.fireDate < $1.fireDate }
    }

    /// Trial and warranty reminders for one product.
    /// - Parameters:
    ///   - product: The product to plan for.
    ///   - defaultLead: The fallback lead time.
    ///   - now: The moment to plan against.
    ///   - calendar: The calendar to compute dates in.
    /// - Returns: Up to two reminders.
    static func reminders(
        for product: Product,
        defaultLead: ReminderLeadTime,
        now: Date,
        calendar: Calendar
    ) -> [ReminderRequest] {
        var results: [ReminderRequest] = []
        if product.hasTrial, let ends = product.trialEndsDate {
            let lead = product.trialReminderLeadTime == .useDefault
                ? defaultLead
                : product.trialReminderLeadTime
            if let fire = fireDate(before: ends, leadDays: lead.leadDays, now: now, calendar: calendar) {
                results.append(ReminderRequest(
                    id: "\(identifierPrefix)trial.\(product.id.uuidString)",
                    kind: .trialEnding,
                    title: "Free trial ending",
                    body: "\(product.name) stops being free on "
                        + ends.formatted(.dateTime.day().month(.wide)) + ".",
                    fireDate: fire
                ))
            }
        }
        if product.hasWarranty, let expires = product.warrantyExpiresDate {
            let lead = product.warrantyReminderLeadTime == .useDefault
                ? defaultLead
                : product.warrantyReminderLeadTime
            if let fire = fireDate(before: expires, leadDays: lead.leadDays, now: now, calendar: calendar) {
                results.append(ReminderRequest(
                    id: "\(identifierPrefix)warranty.\(product.id.uuidString)",
                    kind: .warrantyExpiring,
                    title: "Warranty expiring",
                    body: "\(product.name) is covered until "
                        + expires.formatted(.dateTime.day().month(.wide)) + ".",
                    fireDate: fire
                ))
            }
        }
        return results
    }

    /// Payment reminders for one card, at the fixed three-day lead.
    /// - Parameters:
    ///   - account: The account to plan for.
    ///   - now: The moment to plan against.
    ///   - calendar: The calendar to compute dates in.
    /// - Returns: The next few reminders, or none when this is not a reminding card.
    static func cardReminders(
        for account: Account,
        now: Date,
        calendar: Calendar
    ) -> [ReminderRequest] {
        guard account.kind == .card,
              !account.isClosed,
              account.remindBeforeDueDate,
              let dueDay = account.paymentDueDayOfMonth else { return [] }

        var results: [ReminderRequest] = []
        var cursor = now
        while results.count < cardMonthsAhead {
            guard let due = calendar.nextDate(
                after: cursor,
                matching: DateComponents(day: dueDay),
                matchingPolicy: .previousTimePreservingSmallerComponents
            ) else { break }
            cursor = due
            guard let fire = fireDate(
                before: due, leadDays: cardLeadDays, now: now, calendar: calendar
            ) else { continue }
            let stamp = due.formatted(.verbatim(
                "\(year: .defaultDigits)-\(month: .twoDigits)",
                timeZone: calendar.timeZone,
                calendar: calendar
            ))
            results.append(ReminderRequest(
                id: "\(identifierPrefix)cardDue.\(account.id.uuidString).\(stamp)",
                kind: .cardPaymentDue,
                title: "Payment due soon",
                body: "\(account.name) is due on "
                    + due.formatted(.dateTime.day().month(.wide)) + ".",
                fireDate: fire
            ))
        }
        return results
    }

    /// The moment a reminder should fire, a number of days before a date.
    /// - Parameters:
    ///   - date: The date being reminded about.
    ///   - leadDays: How many days ahead to fire, or `nil` when reminders are off.
    ///   - now: The moment to plan against.
    ///   - calendar: The calendar to compute in.
    /// - Returns: The fire moment, or `nil` when off or already past.
    static func fireDate(
        before date: Date,
        leadDays: Int?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let leadDays else { return nil }
        guard let day = calendar.date(byAdding: .day, value: -leadDays, to: date),
              let fire = calendar.date(
                  bySettingHour: fireHour, minute: 0, second: 0, of: day
              ) else { return nil }
        return fire > now ? fire : nil
    }
}
