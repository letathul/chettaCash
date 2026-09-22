import Foundation

/// Which reader produced a scan's fields (§9.7).
///
/// Kept on the result so the fallback is observable: a test can assert that an
/// unavailable model really did hand over, and the UI can say quietly where the
/// values came from.
public enum ReceiptScanSource: String, Sendable, Equatable {
    /// Apple's on-device language model read the receipt.
    case onDeviceModel
    /// The built-in text heuristics read it, because the model was unavailable,
    /// declined, or returned nothing usable.
    case textHeuristics
}

/// Recognised receipt text, in both of the shapes the extractors need.
///
/// The language model reads the whole page at once, so it wants the transcript. The
/// heuristics need to know *where* a line sat, because the merchant is identified by
/// being at the top — so they want the lines.
public struct RecognizedReceipt: Equatable, Sendable {
    /// The recognised lines, with their vertical position.
    public let lines: [RecognizedLine]
    /// The page as continuous text, reading order preserved.
    public let transcript: String

    /// Whether nothing legible was found.
    public var isEmpty: Bool {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Creates recognised text.
    /// - Parameters:
    ///   - lines: The recognised lines.
    ///   - transcript: The page as continuous text. Defaults to the lines joined.
    public init(lines: [RecognizedLine], transcript: String? = nil) {
        self.lines = lines
        self.transcript = transcript ?? lines.map(\.text).joined(separator: "\n")
    }
}

/// How far along a receipt scan is (§9.7).
///
/// A scan is not one wait but three, and the middle one — the on-device model — is by
/// far the longest. A single spinner for all of it gives no sense of whether anything is
/// happening, which on a multi-second wait reads as a hang. Naming the step makes the
/// wait legible, and makes the slow part self-explanatory.
public enum ReceiptScanPhase: String, Sendable, Equatable, CaseIterable {
    /// No scan is running.
    case idle
    /// Vision is finding the text on the photo.
    case reading
    /// A reader is working out what the text means.
    case understanding
    /// The reading is being matched to the user's accounts and categories.
    case matching

    /// The phases a running scan passes through, in order.
    public static var working: [ReceiptScanPhase] { [.reading, .understanding, .matching] }

    /// Whether a scan is in flight.
    public var isScanning: Bool { self != .idle }

    /// What to tell the user is happening.
    public var message: String {
        switch self {
        case .idle: return ""
        case .reading: return "Reading the receipt…"
        case .understanding: return "Working out what it says…"
        case .matching: return "Matching it to your accounts…"
        }
    }

    /// How far through the scan this phase is, from `0` to `1`.
    ///
    /// Reported as the *completed* fraction at the start of each step, so the bar moves
    /// when a step begins rather than sitting at zero through the longest one.
    public var progress: Double {
        guard let index = Self.working.firstIndex(of: self) else { return 0 }
        return Double(index) / Double(Self.working.count)
    }

    /// Which step this is, counting from one, or `nil` when idle.
    public var step: Int? {
        Self.working.firstIndex(of: self).map { $0 + 1 }
    }
}

/// What a reader needs to know beyond the receipt itself (§9.7).
///
/// Carries the category labels because categories are per-user: they are whatever
/// ``CategoryRepository`` returns, never a fixed list, so a reader asked to classify a
/// purchase has to be told what the choices actually are.
public struct ReceiptScanContext: Sendable {
    /// The moment used to reject implausible dates.
    public var now: Date
    /// The labels of the categories this form's picker offers.
    public var categoryLabels: [String]

    /// Creates a context.
    /// - Parameters:
    ///   - now: The moment used to reject implausible dates.
    ///   - categoryLabels: The labels the picker offers.
    public init(now: Date = .now, categoryLabels: [String] = []) {
        self.now = now
        self.categoryLabels = categoryLabels
    }
}

/// Reads a receipt's fields out of its recognised text (§9.7).
///
/// Declared in Domain, like ``NotificationAuthorizing`` and ``AppLockAuthenticating``,
/// so the framework-backed implementations live in Features and a test can substitute
/// a fake without a simulator.
public protocol ReceiptExtracting: Sendable {
    /// Extracts what it can.
    ///
    /// Never throws: a reader that cannot help returns an empty result and the
    /// caller moves on to the next one.
    ///
    /// - Parameters:
    ///   - receipt: The recognised text.
    ///   - context: What the reader needs beyond the receipt.
    /// - Returns: What could be extracted.
    func extract(
        from receipt: RecognizedReceipt, context: ReceiptScanContext
    ) async -> ReceiptScanResult
}
