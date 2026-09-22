import Foundation
import FoundationModels
import Domain

/// Judges likely duplicates with Apple's on-device language model (§9.7).
///
/// The question put to the model is deliberately narrow. The card, the day and the amount
/// already match — that was settled deterministically — so the only thing left to judge is
/// whether two *names* are the same shop, which is exactly the kind of question a language
/// model is good at and a string comparison is not.
///
/// The verdict never decides anything on its own: it pre-selects the wizard's default and
/// supplies the sentence the user reads. Nothing is discarded without a tap.
struct FoundationModelsDuplicateAdjudicator: DuplicateAdjudicating {

    /// The shape the model is asked to fill in for one pair.
    @Generable
    struct Adjudication {
        /// Whether both lines describe one purchase.
        @Guide(description: """
            true if these two lines describe the same single real purchase, \
            false if they are two separate purchases that happen to cost the same.
            """)
        var isSameTransaction: Bool?
        /// Why.
        @Guide(description: """
            One short sentence a person would understand, naming both spellings. \
            For example: Blue Bottle and SQ *BLUE BOTTLE 1042 are the same coffee shop.
            """)
        var reason: String?
    }

    /// How many conflicts reach the model before the rest fall to the heuristic.
    ///
    /// One small session per pair is quick, but a pathological statement could raise
    /// hundreds — and a sheet that sits still for a minute reads as a hang.
    static let budget = 25

    /// The model to ask. Injectable so a test can force the unavailable path.
    let model: SystemLanguageModel

    /// Creates the adjudicator.
    /// - Parameter model: The model to ask.
    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Whether the model reports itself ready.
    var isAvailable: Bool { model.availability == .available }

    /// Judges each conflict, up to the budget.
    /// - Parameters:
    ///   - conflicts: The pairs to judge.
    ///   - context: What the reader needs beyond the pairs.
    /// - Returns: The verdicts, which may not cover every conflict.
    func adjudicate(
        _ conflicts: [DuplicateConflict],
        context: DuplicateAdjudicationContext
    ) async -> [DuplicateVerdict] {
        guard isAvailable else { return [] }

        var verdicts: [DuplicateVerdict] = []
        for conflict in conflicts.prefix(Self.budget) {
            guard let verdict = await judge(conflict) else { continue }
            verdicts.append(verdict)
        }
        return verdicts
    }

    /// Asks the model about one pair.
    /// - Parameter conflict: The pair to judge.
    /// - Returns: The verdict, or `nil` when the model could not answer.
    private func judge(_ conflict: DuplicateConflict) async -> DuplicateVerdict? {
        do {
            let session = LanguageModelSession(model: model) { Self.instructions }
            let response = try await session.respond(
                to: Self.question(for: conflict), generating: Adjudication.self
            )
            return Self.verdict(from: response.content, for: conflict)
        } catch {
            // Declined, interrupted, or running where the assets are absent. The caller
            // fills every gap from the heuristic.
            return nil
        }
    }

    /// The session's instructions.
    static var instructions: String {
        """
        You compare two descriptions of a card purchase and say whether they are the same \
        purchase. You are told the two only because they are already on the same card, on \
        the same day, for exactly the same amount — so the only thing you need to judge is \
        whether the two names are the same shop.

        Shops are written differently on a bank statement than by hand: a statement adds \
        payment-processor prefixes such as SQ * or TST*, branch numbers, and city names. \
        Say false only when the two names are clearly different businesses.
        """
    }

    /// The question asked about one pair.
    /// - Parameter conflict: The pair to describe.
    /// - Returns: The prompt.
    static func question(for conflict: DuplicateConflict) -> String {
        """
        Already recorded by hand: "\(conflict.existing.merchant)"
        Printed on the statement: "\(conflict.row.rawDescriptor)"
        """
    }

    /// Converts the model's answer into a verdict.
    /// - Parameters:
    ///   - adjudication: What the model returned.
    ///   - conflict: The pair it was asked about.
    /// - Returns: The verdict, or `nil` when the model gave no usable answer.
    static func verdict(
        from adjudication: Adjudication,
        for conflict: DuplicateConflict
    ) -> DuplicateVerdict? {
        guard let isSame = adjudication.isSameTransaction else { return nil }
        let reason = adjudication.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DuplicateVerdict(
            id: conflict.id,
            judgement: isSame ? .sameTransaction : .differentTransactions,
            rationale: (reason?.isEmpty == false) ? (reason ?? "") : conflict.reason.explanation,
            source: .onDeviceModel
        )
    }
}
