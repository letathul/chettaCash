import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``ComparisonRepository``.
@ModelActor
public actor SwiftDataComparisonRepository: ComparisonRepository {

    /// Fetches comparisons in sort order.
    /// - Returns: Every saved comparison.
    /// - Throws: A persistence error if the fetch fails.
    public func comparisons() async throws -> [Domain.Comparison] {
        let descriptor = FetchDescriptor<ComparisonRecord>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    /// Inserts or updates a comparison.
    /// - Parameter comparison: The comparison to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ comparison: Domain.Comparison) async throws {
        let target = try record(id: comparison.id) ?? {
            let fresh = ComparisonRecord(id: comparison.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(comparison)
        try modelContext.save()
    }

    /// Deletes a comparison.
    /// - Parameter id: The comparison's identifier.
    /// - Throws: A persistence error if the delete fails.
    public func delete(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        modelContext.delete(target)
        try modelContext.save()
    }

    /// Fetches the stored record behind a comparison identifier.
    /// - Parameter id: The comparison's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> ComparisonRecord? {
        var descriptor = FetchDescriptor<ComparisonRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
