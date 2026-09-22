import Foundation
import SwiftData
import Domain

/// Runs ``CategorySeeder`` off the main actor.
///
/// The seed is a fetch plus a batch of inserts against a fresh context, which is precisely
/// the kind of work that must not happen on the main actor. It used to run inside
/// `AppDependencies.init`, and because an App Intent is often the *first* thing to build the
/// dependency graph on a cold background launch, the Shortcut paid for it before it did
/// anything at all.
///
/// A `@ModelActor` gives it its own context on its own executor, which is all it needed.
@ModelActor
public actor SwiftDataCategorySeeder {

    /// Inserts any missing built-in categories.
    ///
    /// Idempotent, exactly as ``CategorySeeder/seedIfNeeded(context:)`` is: running it twice
    /// leaves one of each.
    ///
    /// - Throws: A persistence error if the fetch or save fails.
    public func seedIfNeeded() throws {
        try CategorySeeder.seedIfNeeded(context: modelContext)
    }
}
