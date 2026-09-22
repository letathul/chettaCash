import Foundation

/// What Siri may see while the phone is locked (§15.3, §11).
///
/// Writing and reading are not the same risk, and the app lock treats them differently.
///
/// **A write reveals nothing.** Someone holding a locked phone who says "add a four pound
/// expense" learns nothing they did not already know; they have made a mess the owner can
/// delete. Demanding Face ID per coffee would cost the feature its whole point.
///
/// **A read reveals everything.** Account names, the last four digits of a card, balances
/// and history are precisely what the lock exists to hide — and Siri reads them aloud, to
/// whoever is in the room. A Shortcuts picker offering "Chequing ••9087" on a locked phone
/// is the lock failing quietly.
///
/// Stated here as a pure decision so it is one rule, tested once, rather than a condition
/// repeated at each call site and eventually got wrong at one of them.
public enum ShortcutPrivacyPolicy {

    /// Whether the app's stored data must be withheld from Siri and the Shortcuts editor.
    ///
    /// Both conditions are required. A user who has not turned the lock on has not asked for
    /// their figures to be private, and withholding them anyway would break their Shortcuts
    /// to enforce a preference they never expressed.
    ///
    /// - Parameters:
    ///   - lockEnabled: Whether the user has turned the §11 app lock on.
    ///   - protectedDataAvailable: Whether the device is unlocked right now. The system
    ///     answers this without prompting, which is what makes it usable from inside a
    ///     picker where a Face ID sheet would be absurd.
    /// - Returns: Whether to withhold it.
    public static func hidesStoredData(
        lockEnabled: Bool,
        protectedDataAvailable: Bool
    ) -> Bool {
        lockEnabled && !protectedDataAvailable
    }
}
