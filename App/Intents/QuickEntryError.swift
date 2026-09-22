import AppIntents
import Foundation
import Domain

/// Why a quick entry could not be recorded (§15).
///
/// Shared by every intent that records one, since they share the path that raises it.
///
/// Short, because an account that cannot be worked out no longer belongs here: the entry is
/// written and parked instead (§15.5). What is left is the input the app genuinely cannot
/// make sense of at all.
enum QuickEntryError: Error, CustomLocalizedStringResourceConvertible {
    /// The amount was negative, or too large to represent.
    case unusableAmount
    /// The category label could not be used.
    case unusableCategory(CategoryNaming.Problem)
    /// The amount, the merchant or the receipt ran past what this path accepts (§15.8).
    case beyondLimits(QuickEntryProblem)

    /// What Siri says when the action fails.
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unusableAmount:
            return "That amount can't be recorded. Enter a positive amount."
        case .unusableCategory(.containsEmoji):
            return "A category name can't contain emoji."
        case .unusableCategory(.tooLong):
            return "Keep a new category name to \(CategoryNaming.maxLength) characters or fewer."
        case .unusableCategory(.empty):
            return "That category name is empty."
        case .beyondLimits(let problem):
            return problem.localizedStringResource
        }
    }
}

/// Saying a limit out loud (§15.8).
extension QuickEntryProblem: @retroactive CustomLocalizedStringResourceConvertible {
    /// What Siri says when an entry runs past what a Shortcut may record.
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .amountTooLarge:
            return "That amount is too large to record from a Shortcut."
        case .missingMerchant:
            return "Say who it was with."
        case .merchantTooLong:
            let limit = QuickEntryLimits.maximumMerchantLength
            return "Keep the merchant name to \(limit) characters or fewer."
        case .receiptTooLarge:
            let pages = QuickEntryLimits.maximumReceiptPages
            return "That receipt is too big to attach. Keep it to \(pages) pages or fewer."
        }
    }
}
