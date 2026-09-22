import Foundation

/// A template that lazily generates transactions on a schedule (§4.5).
///
/// At any moment exactly one unposted occurrence exists per active rule. When
/// that occurrence posts, the next is generated immediately. There is no state
/// flag to flip: posting is purely a function of the clock.
public struct RecurringRule: Identifiable, Hashable, Sendable {
    /// Stable identifier, preserved across backup export and import.
    public let id: UUID
    /// Display name for the series, such as "Rent".
    public var name: String
    /// Magnitude of each generated occurrence, in cents.
    public var amountCents: Int
    /// The type each generated occurrence takes.
    public var type: TransactionType
    /// The category applied to each generated occurrence.
    public var categoryID: UUID?
    /// The account each occurrence is recorded against.
    public var accountID: UUID?
    /// How often the rule fires.
    public var frequency: RecurringFrequency
    /// The date of the first occurrence.
    public var startDate: Date
    /// Optional end date. Mutually exclusive with ``occurrenceLimit`` in the UI.
    public var endDate: Date?
    /// Optional cap on how many occurrences are generated in total.
    public var occurrenceLimit: Int?
    /// How many occurrences the rule has generated so far.
    public var occurrencesGenerated: Int
    /// Whether the rule still generates occurrences.
    public var isActive: Bool
    /// The product this rule bills for, if any.
    public var productID: UUID?

    /// Creates a recurring rule.
    /// - Parameters:
    ///   - id: Stable identifier. Defaults to a fresh UUID.
    ///   - name: Display name for the series.
    ///   - amountCents: Magnitude of each occurrence, in cents.
    ///   - type: The type each occurrence takes.
    ///   - categoryID: Category applied to each occurrence.
    ///   - accountID: Account each occurrence is recorded against.
    ///   - frequency: How often the rule fires.
    ///   - startDate: Date of the first occurrence.
    ///   - endDate: Optional end date.
    ///   - occurrenceLimit: Optional cap on total occurrences.
    ///   - occurrencesGenerated: How many occurrences exist so far.
    ///   - isActive: Whether the rule still generates occurrences.
    ///   - productID: The product this rule bills for.
    public init(
        id: UUID = UUID(),
        name: String = "",
        amountCents: Int = 0,
        type: TransactionType = .expense,
        categoryID: UUID? = nil,
        accountID: UUID? = nil,
        frequency: RecurringFrequency = .monthly,
        startDate: Date = .now,
        endDate: Date? = nil,
        occurrenceLimit: Int? = nil,
        occurrencesGenerated: Int = 0,
        isActive: Bool = true,
        productID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.type = type
        self.categoryID = categoryID
        self.accountID = accountID
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.occurrenceLimit = occurrenceLimit
        self.occurrencesGenerated = occurrencesGenerated
        self.isActive = isActive
        self.productID = productID
    }
}
