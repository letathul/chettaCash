import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// Every model in ``schema`` satisfies CloudKit's requirements: all properties have
/// defaults or are optional, all relationships are optional with declared inverses,
/// and `@Attribute(.unique)` appears nowhere. These are requirements, not style
/// preferences — a model missing a default fails schema validation at initialisation.
public enum ModelContainerFactory {

    /// Every persisted model type.
    public static let schema = Schema([
        AccountGroupRecord.self,
        AccountRecord.self,
        TransactionRecord.self,
        ProductRecord.self,
        RecurringRuleRecord.self,
        CardStatementRecord.self,
        StatementPaymentRecord.self,
        CategoryRecord.self,
        ComparisonRecord.self,
        MerchantCategoryRuleRecord.self
    ])

    /// Creates a container over the full schema.
    ///
    /// - Parameters:
    ///   - inMemory: When `true`, nothing is written to disk. Used by tests.
    ///   - cloudKit: Whether to sync through the CloudKit private database. Left
    ///     `false` until a signing team and CloudKit container are configured; the
    ///     schema already satisfies CloudKit's constraints either way.
    /// - Returns: The configured container.
    /// - Throws: A `SwiftDataError` if the schema fails validation.
    public static func make(inMemory: Bool = false, cloudKit: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit ? .automatic : .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
