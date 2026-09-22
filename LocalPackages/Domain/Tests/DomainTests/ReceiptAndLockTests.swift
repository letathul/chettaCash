import Foundation
import Testing
@testable import Domain

/// Phase 13 acceptance criteria for the receipt cache and the app lock (§9.3, §9.5, §11).
@Suite("Receipts and app lock")
struct ReceiptAndLockTests {

    /// A fixed UTC calendar, so results never depend on the runner's locale.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// A fixed moment.
    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12)) ?? .now
    }

    // MARK: - Naming and folders (§9.3)

    @Test("A receipt lands in a year and month folder")
    func folderLayout() {
        let path = ReceiptNaming.path(for: reference, calendar: calendar)

        #expect(path.folder == "Receipts/2026/2026-09")
        #expect(path.manifestPath == "Receipts/2026/2026-09/manifest.csv")
    }

    @Test("A filename carries the date, merchant, amount and a short identifier")
    func fileNameShape() {
        let id = UUID(uuidString: "A3F94C21-0000-0000-0000-000000000000") ?? UUID()

        let name = ReceiptNaming.fileName(
            date: reference, merchant: "Whole Foods", amountCents: 4_210,
            ownerID: id, calendar: calendar
        )

        #expect(name == "2026-09-12_whole-foods_42.10_a3f9.jpg")
    }

    @Test("A receipt's identifier is its path relative to the storage root")
    func fileIDShape() {
        let id = UUID(uuidString: "A3F94C21-0000-0000-0000-000000000000") ?? UUID()

        let fileID = ReceiptNaming.fileID(
            date: reference, merchant: "Whole Foods", amountCents: 4_210, ownerID: id
        )

        // The store uses the same relative path as its own identifier, so this one
        // value is both where the file lives and how to ask for it back.
        #expect(fileID.hasPrefix("Receipts/2026/2026-09/"))
        #expect(fileID.hasSuffix("_whole-foods_42.10_a3f9.jpg"))
    }

    @Test("A merchant name is reduced to a filename-safe slug", arguments: [
        ("Whole Foods", "whole-foods"),
        ("Smith, Jones & Co.", "smith-jones-co"),
        ("  ", "receipt"),
        ("Café/Bar", "cafe-bar")
    ])
    func merchantSlugs(input: String, expected: String) {
        #expect(ReceiptNaming.slug(input) == expected)
    }

    @Test("The manifest links a filename back to its owner, and says which kind it is")
    func manifestRow() {
        let id = UUID()

        let row = ReceiptNaming.manifestRow(
            fileName: "r.jpg", ownerID: id, ownerKind: .product
        )

        #expect(row["fileName"] == "r.jpg")
        #expect(row["ownerID"] == id.uuidString)
        // A bare UUID would not say which table to look in when rebuilding from the
        // folder, now that a product can own a receipt as well as a transaction.
        #expect(row["ownerKind"] == "product")
        #expect(ReceiptNaming.manifestColumns == ["fileName", "ownerID", "ownerKind"])
    }

    // MARK: - Cache eviction safety (§9.5)

    /// Builds a cached receipt.
    /// - Parameters:
    ///   - id: The file identifier.
    ///   - megabytes: Its size.
    ///   - ageDays: How long ago it was last read.
    ///   - state: Its upload state.
    /// - Returns: The cached receipt.
    private func cached(
        _ id: String,
        megabytes: Int,
        ageDays: Int,
        state: ReceiptUploadState = .uploaded
    ) -> CachedReceipt {
        CachedReceipt(
            fileID: id,
            sizeBytes: megabytes * 1_024 * 1_024,
            lastAccessed: reference.addingTimeInterval(Double(-ageDays) * 86_400),
            uploadState: state
        )
    }

    @Test("Only an uploaded receipt is evictable", arguments: [
        (ReceiptUploadState.uploaded, true),
        (ReceiptUploadState.pending, false),
        (ReceiptUploadState.failed, false),
        (ReceiptUploadState.none, false)
    ])
    func evictabilityByState(state: ReceiptUploadState, expected: Bool) {
        #expect(ReceiptCachePolicy.isEvictable(
            cached("a", megabytes: 1, ageDays: 1, state: state)
        ) == expected)
    }

    @Test("Clearing the cache skips a pending upload")
    func clearingSkipsPending() {
        let receipts = [
            cached("uploaded", megabytes: 10, ageDays: 5),
            cached("pending", megabytes: 10, ageDays: 1, state: .pending),
            cached("failed", megabytes: 10, ageDays: 2, state: .failed)
        ]

        let plan = ReceiptCachePolicy.clearablePlan(receipts)

        #expect(plan == ["uploaded"])
        #expect(!plan.contains("pending"), "a photo taken offline must survive a clear")
        #expect(!plan.contains("failed"))
    }

    @Test("Eviction removes the least recently read first")
    func evictionIsLeastRecentlyUsed() {
        let receipts = [
            cached("newest", megabytes: 60, ageDays: 1),
            cached("oldest", megabytes: 60, ageDays: 30),
            cached("middle", megabytes: 60, ageDays: 10)
        ]

        let plan = ReceiptCachePolicy.evictionPlan(
            receipts, capBytes: ReceiptCachePolicy.capBytes(fromMB: 100)
        )

        #expect(plan == ["oldest", "middle"], "oldest first, stopping once under the cap")
    }

    @Test("Eviction never touches a pending upload, even to reach the cap")
    func evictionSkipsPending() {
        let receipts = [
            cached("pending", megabytes: 150, ageDays: 30, state: .pending),
            cached("uploaded", megabytes: 20, ageDays: 1)
        ]

        let plan = ReceiptCachePolicy.evictionPlan(
            receipts, capBytes: ReceiptCachePolicy.capBytes(fromMB: 100)
        )

        #expect(plan == ["uploaded"])
        #expect(!plan.contains("pending"), "the cache runs over its cap rather than break this")
    }

    @Test("Nothing is evicted when the cache fits, or when the cap is unlimited")
    func noEvictionWhenUnnecessary() {
        let receipts = [cached("a", megabytes: 10, ageDays: 1)]

        #expect(ReceiptCachePolicy.evictionPlan(
            receipts, capBytes: ReceiptCachePolicy.capBytes(fromMB: 200)
        ).isEmpty)
        #expect(ReceiptCachePolicy.evictionPlan(receipts, capBytes: nil).isEmpty)
    }

    @Test("The default cap is 200 MB and unlimited is offered")
    func capOptions() {
        #expect(ReceiptCachePolicy.defaultCapMB == 200)
        #expect(ReceiptCachePolicy.selectableCapsMB.contains(nil))
        #expect(ReceiptCachePolicy.capBytes(fromMB: nil) == nil)
    }

    // MARK: - App lock (§11)

    @Test("A cold launch locks when the lock is on, and never when it is off")
    func coldLaunch() {
        #expect(AppLockPolicy.shouldLockOnLaunch(isEnabled: true))
        #expect(AppLockPolicy.shouldLockOnLaunch(isEnabled: false) == false)
    }

    @Test("Returning to the foreground locks immediately at the default grace")
    func foregroundLocksImmediately() {
        let backgrounded = reference.addingTimeInterval(-1)

        #expect(AppLockPolicy.shouldLockOnForeground(
            isEnabled: true, backgroundedAt: backgrounded, now: reference, graceSeconds: 0
        ))
    }

    @Test("A grace period forgives a short trip away")
    func gracePeriodForgivesShortTrip() {
        let backgrounded = reference.addingTimeInterval(-10)

        #expect(AppLockPolicy.shouldLockOnForeground(
            isEnabled: true, backgroundedAt: backgrounded, now: reference, graceSeconds: 30
        ) == false)
        #expect(AppLockPolicy.shouldLockOnForeground(
            isEnabled: true, backgroundedAt: backgrounded, now: reference, graceSeconds: 5
        ))
    }

    @Test("A scene that never backgrounded does not lock")
    func noBackgroundStampDoesNotLock() {
        // The authentication sheet itself drives the scene inactive. Locking on the
        // way back is what produced the endless prompt loop.
        #expect(AppLockPolicy.shouldLockOnForeground(
            isEnabled: true, backgroundedAt: nil, now: reference, graceSeconds: 0
        ) == false)
    }

    @Test("The lock never engages while switched off")
    func disabledLockNeverEngages() {
        #expect(AppLockPolicy.shouldLockOnForeground(
            isEnabled: false, backgroundedAt: nil, now: reference, graceSeconds: 0
        ) == false)
    }

    @Test("The switcher snapshot is obscured whenever the scene is not active")
    func snapshotIsObscuredWhenInactive() {
        #expect(AppLockPolicy.shouldObscureSnapshot(isEnabled: true, isActive: false))
        #expect(AppLockPolicy.shouldObscureSnapshot(isEnabled: true, isActive: true) == false)
        #expect(AppLockPolicy.shouldObscureSnapshot(isEnabled: false, isActive: false) == false)
    }

    @Test("Changing the lock setting needs authentication in both directions")
    func changingRequiresAuthentication() {
        #expect(AppLockPolicy.requiresAuthentication(toChangeFrom: true, to: false))
        #expect(AppLockPolicy.requiresAuthentication(toChangeFrom: false, to: true))
        #expect(AppLockPolicy.requiresAuthentication(toChangeFrom: true, to: true) == false)
        #expect(AppLockPolicy.requiresAuthentication(toChangeFrom: false, to: false) == false)
    }

    @Test("Only the enable prompt refuses the passcode fallback")
    func onlyEnablingIsBiometricsOnly() {
        #expect(AppLockPolicy.usesBiometricsOnly(for: .enablingLock))
        #expect(AppLockPolicy.usesBiometricsOnly(for: .disablingLock) == false)
        #expect(AppLockPolicy.usesBiometricsOnly(for: .coldLaunch) == false)
        #expect(AppLockPolicy.usesBiometricsOnly(for: .returnedToForeground) == false)
    }

    @Test("The lock may only be enabled with an enrolled biometric")
    func enablingNeedsEnrolledBiometry() {
        let enrolled = AppLockAvailability(biometry: .faceID, isEnrolled: true, hasPasscode: true)
        let unenrolled = AppLockAvailability(biometry: .faceID, isEnrolled: false, hasPasscode: true)
        let noHardware = AppLockAvailability(biometry: .none, isEnrolled: false, hasPasscode: true)

        #expect(AppLockPolicy.canEnable(enrolled))
        #expect(AppLockPolicy.canEnable(unenrolled) == false)
        #expect(AppLockPolicy.canEnable(noHardware) == false)
    }

    @Test("A device with neither biometry nor a passcode has no security to lock behind")
    func noDeviceSecurityIsDetected() {
        let bare = AppLockAvailability(biometry: .none, isEnrolled: false, hasPasscode: false)
        let passcodeOnly = AppLockAvailability(biometry: .none, isEnrolled: false, hasPasscode: true)

        #expect(bare.hasNoDeviceSecurity)
        #expect(passcodeOnly.hasNoDeviceSecurity == false)
    }
}
