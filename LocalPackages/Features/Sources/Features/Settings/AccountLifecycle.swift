import Foundation
import Domain

/// User-facing copy for the two balance-correction paths (§4.4).
extension BalanceCorrection {
    /// The option's title.
    var title: String {
        switch self {
        case .adjustment: return "Record an adjustment"
        case .openingBalance: return "Edit the opening balance"
        }
    }

    /// What the option does, in the user's terms.
    var explanation: String {
        switch self {
        case .adjustment:
            return "Adds a dated correction for drift or an unlogged charge. "
                 + "It changes your balance and Net Worth but is not counted as spending."
        case .openingBalance:
            return "Use this when the starting figure was simply wrong. "
                 + "It recomputes this account's entire history."
        }
    }
}
