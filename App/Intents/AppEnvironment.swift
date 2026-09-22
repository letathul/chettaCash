import Foundation

/// The one dependency graph this process uses.
///
/// App Intents run **inside the app's own process**, whether or not a window is on
/// screen, so the intent and the UI must reach the same graph. Two
/// ``AppDependencies`` would mean two `ModelContainer`s over one store file, which is
/// how a SwiftData store gets corrupted — so the graph is built once here and handed
/// to whoever asks first, the scene or an intent.
@MainActor
enum AppEnvironment {
    /// The graph, once something has asked for it.
    private static var cached: AppDependencies?
    /// The work that builds and seeds it, so concurrent callers await one attempt.
    private static var preparation: Task<AppDependencies, any Error>?

    /// The dependency graph, building and seeding it on first use.
    ///
    /// Asynchronous because seeding runs off the main actor. The whole build is held in one
    /// `Task` rather than guarded by a flag: an intent and the scene can both ask at once on
    /// a cold launch, and without this each would start its own seed against the same store.
    ///
    /// A failed attempt is not cached. The next caller starts again, which matters because
    /// the usual reason for failure here — the store being unreadable while the device is
    /// still locked — goes away on its own.
    ///
    /// - Returns: The graph.
    /// - Throws: A `SwiftDataError` if the schema fails validation, or a persistence
    ///   error if seeding fails.
    static func shared() async throws -> AppDependencies {
        if let cached { return cached }
        if let preparation { return try await preparation.value }

        let task = Task<AppDependencies, any Error> {
            let dependencies = try AppDependencies()
            try await dependencies.prepare()
            return dependencies
        }
        preparation = task
        defer { preparation = nil }

        let dependencies = try await task.value
        cached = dependencies
        return dependencies
    }

    #if DEBUG
    /// Replaces the graph, so a test can run an intent against an in-memory store.
    ///
    /// The seam exists because an App Intent reaches its dependencies through this
    /// type rather than through an initialiser — there is nowhere else to inject.
    /// Debug-only: nothing should be able to swap the live store in a shipped build.
    ///
    /// - Parameter dependencies: The graph to use.
    static func replaceForTesting(with dependencies: AppDependencies) {
        preparation = nil
        cached = dependencies
    }
    #endif
}

/// Broadcast when something outside the UI changes stored data.
///
/// A Shortcut can run while the app is already foregrounded, and `scenePhase` never
/// changes in that case — so without this the Ledger would go on showing figures that
/// no longer match the database.
extension Notification.Name {
    /// Posted after an App Intent writes to the store.
    static let chettaCashDataDidChange = Notification.Name("chettaCashDataDidChange")
}
