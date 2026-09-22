import Foundation
@testable import Features
import Domain

// Test doubles for the system services the app talks to: notification permission
// and scheduling. Kept apart from the repository fakes so each file stays within
// the 300-line limit.

/// A ``NotificationAuthorizing`` that records requests instead of prompting.
@MainActor
final class FakeNotificationAuthorizer: NotificationAuthorizing {
    /// What the next request will return.
    var grants = true
    /// The standing status before any request.
    var status: NotificationAuthorizationStatus = .notDetermined
    /// How many times the prompt was requested.
    var requestCount = 0

    nonisolated func currentStatus() async -> NotificationAuthorizationStatus {
        await MainActor.run { status }
    }

    @discardableResult
    nonisolated func requestAuthorization() async -> Bool {
        await MainActor.run {
            requestCount += 1
            status = grants ? .authorized : .denied
            return grants
        }
    }
}

/// A ``NotificationScheduling`` that records what would be scheduled.
@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    /// Reminders currently scheduled, keyed by identifier.
    var scheduled: [String: ReminderRequest] = [:]
    /// Identifiers cancelled across all calls, in order.
    var cancelled: [Set<String>] = []

    /// Reports only this app's identifiers, exactly as the real scheduler does.
    nonisolated func pendingReminderIdentifiers() async -> Set<String> {
        await MainActor.run {
            Set(scheduled.keys.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) })
        }
    }

    nonisolated func schedule(_ reminders: [ReminderRequest]) async {
        await MainActor.run {
            // Adding a request with an existing identifier replaces it, as iOS does.
            for reminder in reminders { scheduled[reminder.id] = reminder }
        }
    }

    nonisolated func cancel(identifiers: Set<String>) async {
        await MainActor.run {
            cancelled.append(identifiers)
            for id in identifiers { scheduled[id] = nil }
        }
    }
}

/// An in-memory ``ComparisonRepository``.
@MainActor
final class FakeComparisonRepository: ComparisonRepository {
    /// Stored comparisons, keyed by identifier.
    var comparisonsByID: [UUID: Domain.Comparison] = [:]

    func comparisons() async throws -> [Domain.Comparison] {
        comparisonsByID.values.sorted { ($0.sortIndex, $0.label) < ($1.sortIndex, $1.label) }
    }

    func save(_ comparison: Domain.Comparison) async throws {
        comparisonsByID[comparison.id] = comparison
    }

    func delete(id: UUID) async throws {
        comparisonsByID[id] = nil
    }
}

/// One recorded authentication request.
struct RecordedAuthentication: Equatable {
    /// Why authentication was requested.
    let reason: AppLockReason
    /// Whether the passcode fallback was refused.
    let biometricsOnly: Bool
}

/// An ``AppLockAuthenticating`` that answers without prompting.
@MainActor
final class FakeLockAuthenticator: AppLockAuthenticating {
    /// What each successive authentication returns; the last value repeats.
    var outcomes: [AppLockOutcome] = [.success]
    /// What the device reports it can authenticate with.
    var deviceAvailability = AppLockAvailability(
        biometry: .faceID, isEnrolled: true, hasPasscode: true
    )
    /// Every authentication requested, in order.
    var requests: [RecordedAuthentication] = []
    /// Runs while the prompt is "up", so a test can drive the scene churn a real
    /// system sheet causes.
    var onAuthenticate: (() -> Void)?

    /// Why authentication was requested, in order.
    var reasons: [AppLockReason] { requests.map(\.reason) }

    /// Convenience for the common "the next prompt succeeds, or does not" case.
    var grants: Bool {
        get { outcomes.first == .success }
        set { outcomes = [newValue ? .success : .failed] }
    }

    nonisolated func availability() async -> AppLockAvailability {
        await MainActor.run { deviceAvailability }
    }

    nonisolated func authenticate(
        reason: AppLockReason, biometricsOnly: Bool
    ) async -> AppLockOutcome {
        await MainActor.run {
            requests.append(RecordedAuthentication(reason: reason, biometricsOnly: biometricsOnly))
            onAuthenticate?()
            return outcomes.count > 1 ? outcomes.removeFirst() : (outcomes.first ?? .success)
        }
    }
}

/// A ``ReceiptStore`` held entirely in memory.
actor FakeReceiptStore: ReceiptStore {
    /// Stored files, keyed by identifier.
    var files: [String: Data] = [:]
    /// When set, the next upload throws it.
    var uploadFailure: (any Error)?

    var isAvailable: Bool { get async { true } }

    func upload(_ data: Data, named: String, to path: ReceiptPath) async throws -> String {
        if let uploadFailure { self.uploadFailure = nil; throw uploadFailure }
        let id = "\(path.folder)/\(named)"
        files[id] = data
        return id
    }

    func download(fileID: String) async throws -> Data {
        guard let data = files[fileID] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }

    func delete(fileID: String) async throws { files[fileID] = nil }

    func list(path: ReceiptPath) async throws -> [RemoteFile] {
        files.keys.filter { $0.hasPrefix(path.folder) }.map {
            RemoteFile(fileID: $0, name: $0, sizeBytes: files[$0]?.count ?? 0)
        }
    }

    func writeBackup(_ data: Data, named: String) async throws -> String {
        let id = "Backups/\(named)"
        files[id] = data
        return id
    }

    func listBackups() async throws -> [RemoteFile] {
        files.keys.filter { $0.hasPrefix("Backups/") }
            .sorted(by: >)
            .map { RemoteFile(fileID: $0, name: String($0.dropFirst(8)), sizeBytes: 0) }
    }

    func readBackup(fileID: String) async throws -> Data {
        try await download(fileID: fileID)
    }

    /// Queues a failure for the next upload.
    /// - Parameter error: The error to throw.
    func failNextUpload(_ error: any Error) { uploadFailure = error }
}

/// A ``BackupWriting`` that records that a backup was asked for.
final class FakeBackupWriter: BackupWriting, @unchecked Sendable {
    /// How many archives were written.
    private(set) var writeCount = 0

    func writeBackup(to store: any ReceiptStore) async throws {
        writeCount += 1
        _ = try await store.writeBackup(Data("backup".utf8), named: "test-backup.zip")
    }
}
