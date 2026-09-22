import Foundation
import Testing
@testable import Domain

/// What Siri may see while the phone is locked (§15.3, §11).
@Suite("Shortcut privacy policy")
struct ShortcutPrivacyPolicyTests {

    @Test("A locked phone with the app lock on withholds the accounts")
    func hidesBehindTheLock() {
        #expect(
            ShortcutPrivacyPolicy.hidesStoredData(lockEnabled: true, protectedDataAvailable: false),
            "a picker offering Chequing ••9087 on a locked phone is the lock failing quietly"
        )
    }

    @Test("An unlocked phone shows them, lock or no lock", arguments: [true, false])
    func showsWhenUnlocked(_ lockEnabled: Bool) {
        #expect(
            ShortcutPrivacyPolicy.hidesStoredData(
                lockEnabled: lockEnabled, protectedDataAvailable: true
            ) == false
        )
    }

    @Test("A user who never turned the lock on keeps their Shortcuts working")
    func showsWhenTheLockIsOff() {
        #expect(
            ShortcutPrivacyPolicy.hidesStoredData(
                lockEnabled: false, protectedDataAvailable: false
            ) == false,
            "withholding them would enforce a preference the user never expressed"
        )
    }
}
