import Foundation

/// How this build reached the device.
///
/// Decides whether the feature-flag menu is offered at all (§7.6). Under-development
/// features are for builds someone chose to install — a Debug run or a TestFlight
/// build — not for the App Store, where the menu that would switch one on is simply
/// not reachable.
///
/// This lives in the app rather than in `Features` because the build configuration and
/// the receipt are facts about the host, not about the UI.
enum BuildChannel {
    /// Built and run from Xcode.
    case debug
    /// Installed through TestFlight.
    case testFlight
    /// Installed from the App Store.
    case appStore

    /// The channel this build is running as.
    ///
    /// The sandbox receipt is the usual TestFlight signal. The `#if DEBUG` branch runs
    /// first so the simulator, which also reports a sandbox receipt, never reaches it.
    static var current: BuildChannel {
        #if DEBUG
        return .debug
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
            ? .testFlight
            : .appStore
        #endif
    }

    /// Whether under-development features may be switched on here.
    var showsFeatureFlags: Bool { self != .appStore }
}
