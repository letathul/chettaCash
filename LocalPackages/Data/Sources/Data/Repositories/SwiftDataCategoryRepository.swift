import Foundation
import SwiftData
import Domain

/// SwiftData-backed ``CategoryRepository``.
///
/// Categories are archived, never deleted, so past transactions keep their label
/// and stay filterable (§4.8).
@ModelActor
public actor SwiftDataCategoryRepository: CategoryRepository {

    /// Fetches the categories a picker should offer.
    ///
    /// Excludes archived categories and the two system categories, which must never
    /// appear in any picker.
    ///
    /// - Parameter context: Which picker the categories are for.
    /// - Returns: The selectable categories in sort order.
    /// - Throws: A persistence error if the fetch fails.
    public func selectableCategories(context: CategoryContext) async throws -> [Domain.Category] {
        try fetchAllCategories()
            .filter { $0.context == context }
            .filter { !$0.isArchived }
            .filter { !SystemCategoryID.isSystem($0.id) }
    }

    /// Fetches every category, including archived and system ones.
    /// - Returns: All categories in sort order.
    /// - Throws: A persistence error if the fetch fails.
    public func allCategories() async throws -> [Domain.Category] {
        try fetchAllCategories()
    }

    /// Inserts or updates a category.
    /// - Parameter category: The category to persist.
    /// - Throws: A persistence error if the write fails.
    public func save(_ category: Domain.Category) async throws {
        let target = try record(id: category.id) ?? {
            let fresh = CategoryRecord(id: category.id)
            modelContext.insert(fresh)
            return fresh
        }()
        target.apply(category)
        try modelContext.save()
    }

    /// Archives a category, hiding it from pickers while leaving history intact.
    /// - Parameter id: The category's identifier.
    /// - Throws: A persistence error if the write fails.
    public func archive(id: UUID) async throws {
        guard let target = try record(id: id) else { return }
        target.isArchived = true
        try modelContext.save()
    }

    /// Fetches every category in sort order.
    /// - Returns: All categories.
    /// - Throws: A persistence error if the fetch fails.
    private func fetchAllCategories() throws -> [Domain.Category] {
        let descriptor = FetchDescriptor<CategoryRecord>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.label)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }

    /// Fetches the stored record behind a category identifier.
    /// - Parameter id: The category's identifier.
    /// - Returns: The record, or `nil` if none matches.
    /// - Throws: A persistence error if the fetch fails.
    private func record(id: UUID) throws -> CategoryRecord? {
        var descriptor = FetchDescriptor<CategoryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
