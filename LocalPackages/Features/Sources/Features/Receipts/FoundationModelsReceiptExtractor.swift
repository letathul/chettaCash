import Foundation
import FoundationModels
import Domain

/// Reads a receipt with Apple's on-device language model (§9.7).
///
/// Guided generation constrains the model to a typed shape, so there is no JSON to
/// parse and nothing to go wrong in a decode. The fields come back as *text* rather
/// than numbers deliberately — see ``ReceiptModelValues``.
///
/// Nothing leaves the device, and nothing is ever committed: every field reaches the
/// form as a pre-fill the user can overwrite.
struct FoundationModelsReceiptExtractor: ReceiptExtracting {

    /// The shape the model is asked to fill in.
    @Generable
    struct ExtractedReceipt {
        /// The shop's name.
        @Guide(description: "The shop or merchant name printed at the top of the receipt.")
        var merchant: String?
        /// The final total.
        @Guide(description: """
            The final total paid, as digits with two decimal places, for example 42.10. \
            Not the subtotal, not the tax, not the change given.
            """)
        var total: String?
        /// The purchase date.
        @Guide(description: """
            The date of purchase in yyyy-MM-dd form, for example 2026-03-09. \
            Work out the day and month order from the rest of the receipt.
            """)
        var date: String?
        /// The time of purchase.
        @Guide(description: """
            The time of purchase on a 24-hour clock in HH:mm form, for example 18:42. \
            Convert a printed am/pm time yourself. Leave empty if no time is printed.
            """)
        var time: String?
        /// The shop's address or branch.
        @Guide(description: """
            The shop's street address, branch or city, printed near the top under its \
            name. Not the phone number, the website, or the till number.
            """)
        var location: String?
        /// Which category the purchase belongs to.
        @Guide(description: """
            Which category this purchase belongs to. Copy one of the categories listed \
            in the instructions exactly, or leave empty if none of them fit.
            """)
        var category: String?
    }

    /// The model to ask. Injectable so a test can force the unavailable path.
    let model: SystemLanguageModel

    /// Creates the extractor.
    /// - Parameter model: The model to ask.
    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Whether the model reports itself ready.
    ///
    /// Necessary but **not sufficient**: a model that reports `.available` can still
    /// throw when asked to generate — it does exactly that in the Simulator, where the
    /// generative assets are absent. So this gate only avoids pointless work; the
    /// fallback is what actually makes the scan safe.
    var isAvailable: Bool {
        model.availability == .available
    }

    /// Extracts what the model can read.
    /// - Parameters:
    ///   - receipt: The recognised text.
    ///   - context: The clock and the categories the form offers.
    /// - Returns: What the model extracted, or an empty result if it could not help.
    func extract(
        from receipt: RecognizedReceipt, context: ReceiptScanContext
    ) async -> ReceiptScanResult {
        guard isAvailable, !receipt.isEmpty else { return ReceiptScanResult() }
        do {
            let session = LanguageModelSession(model: model) {
                Self.instructions(categoryLabels: context.categoryLabels)
            }
            let response = try await session.respond(
                to: receipt.transcript, generating: ExtractedReceipt.self
            )
            return result(from: response.content, now: context.now)
        } catch {
            // Includes the model declining, the session being interrupted, and the
            // Simulator's missing assets. Every one of them means "ask the heuristics".
            return ReceiptScanResult()
        }
    }

    /// The session's instructions, naming the categories the form actually offers.
    ///
    /// The category list goes here rather than into a `@Guide(.anyOf:)` constraint,
    /// which needs a compile-time constant array — and this list is per-user, built from
    /// whatever ``CategoryRepository`` returns. Whatever comes back is treated as a
    /// *suggestion of words*: ``ReceiptPrefillBuilder`` matches it against the real
    /// categories and discards it if it names none of them, so an invented category can
    /// never reach the form.
    ///
    /// - Parameter categoryLabels: The labels the picker offers.
    /// - Returns: The instructions.
    static func instructions(categoryLabels: [String]) -> String {
        let base = """
            You read shop receipts. You are given the raw text of one receipt, \
            exactly as it was scanned, including any errors. Report only what the \
            receipt itself says. Leave a field empty rather than guessing at it.
            """
        guard !categoryLabels.isEmpty else { return base }
        return """
            \(base)

            The category is the one exception: judge it from what was bought. \
            Choose exactly one of these categories, copied exactly as written, or \
            leave it empty if none fit: \(categoryLabels.joined(separator: ", ")).
            """
    }

    /// Converts the model's answer into a scan result.
    ///
    /// The card's network and digits are deliberately absent: ``TenderParser`` reads
    /// those off the text directly, where a masked number is an exact pattern rather
    /// than something to be paraphrased.
    ///
    /// - Parameters:
    ///   - extracted: What the model returned.
    ///   - now: The moment used to reject implausible dates.
    /// - Returns: The result, marked as the model's.
    private func result(from extracted: ExtractedReceipt, now: Date) -> ReceiptScanResult {
        ReceiptScanResult(
            amountCents: ReceiptModelValues.cents(from: extracted.total),
            merchant: Self.cleaned(extracted.merchant),
            date: ReceiptModelValues.date(from: extracted.date, time: extracted.time, now: now),
            location: Self.cleaned(extracted.location),
            categoryLabel: Self.cleaned(extracted.category),
            source: .onDeviceModel
        )
    }

    /// Trims a model answer, treating a blank one as no answer at all.
    /// - Parameter text: The model's answer, if it gave one.
    /// - Returns: The trimmed text, or `nil` when it is empty.
    private static func cleaned(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}
