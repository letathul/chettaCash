import Foundation
import Domain

/// Display names for the product sort options.
extension ProductSort {
    /// The label shown on the sort pill.
    var title: String {
        switch self {
        case .soonest: return "Soonest"
        case .newest: return "Newest"
        case .name: return "Name"
        case .merchant: return "Merchant"
        }
    }

    /// The explanatory line shown beneath ``title`` in the picker.
    var detail: String? {
        switch self {
        case .soonest: return "What expires or renews first"
        case .newest: return "Most recently purchased first"
        case .name: return "Alphabetical by product name"
        case .merchant: return "Grouped by where you bought it"
        }
    }
}

/// Display names for the product status filter.
extension ProductStatus {
    /// The label shown on the segmented control.
    var title: String {
        switch self {
        case .all: return "All"
        case .activeTrials: return "Trials"
        case .warranties: return "Warranties"
        case .subscriptions: return "Subs"
        case .expired: return "Expired"
        }
    }
}
