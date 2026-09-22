import Foundation
import FoundationModels
import Domain

/// Reads a statement's rows with Apple's on-device language model (§9.7).
///
/// Guided generation constrains the model to a typed shape, so there is no JSON to parse.
/// Amounts and dates come back as *text* and are converted by ``ReceiptModelValues``, which
/// already refuses an implausible figure — money never reaches a `Double`.
///
/// **One session per page.** A receipt fits in a single prompt; a multi-page statement does
/// not, and asking for all of it at once either truncates the row list silently or fails
/// outright. Per-page sessions also bound the damage: a page the model chokes on costs that
/// page's rows, not the import.
///
/// Nothing leaves the device, and nothing is committed: every row reaches the ledger through
/// the planner, which the user confirms.
struct FoundationModelsStatementExtractor: StatementExtracting {

    /// The shape the model is asked to fill in for one page.
    @Generable
    struct ExtractedPage {
        /// The card's last four digits, if this page printed them.
        @Guide(description: """
            The last four digits of the card number, digits only. \
            Leave empty if this page does not show the card number.
            """)
        var last4: String?
        /// The statement's closing date, if this page printed it.
        @Guide(description: """
            The statement's closing or period-end date in yyyy-MM-dd form. \
            Leave empty if this page does not show it.
            """)
        var closingDate: String?
        /// Every transaction line on the page.
        @Guide(
            description: "Every transaction line listed on this page, in the order printed.",
            .count(0...80)
        )
        var rows: [ExtractedRow]
    }

    /// One transaction line.
    @Generable
    struct ExtractedRow {
        /// The date the line was posted.
        @Guide(description: """
            The transaction date in yyyy-MM-dd form, for example 2026-03-09. \
            Work out the day and month order from the rest of the statement.
            """)
        var date: String?
        /// The descriptor exactly as printed.
        @Guide(description: """
            The merchant descriptor exactly as the statement printed it, unchanged, \
            including any store numbers or processor prefixes.
            """)
        var descriptor: String?
        /// A readable name for the shop.
        @Guide(description: """
            An ordinary human name for the shop, with processor prefixes and store numbers \
            removed. For example SQ *BLUE BOTTLE 1042 becomes Blue Bottle. \
            Leave empty if you are not sure what the shop is.
            """)
        var merchant: String?
        /// The amount as printed.
        @Guide(description: """
            The amount as digits with two decimal places and no sign, for example 42.10.
            """)
        var amount: String?
        /// What kind of line it is.
        @Guide(description: """
            One of exactly these words: charge, refund, payment. \
            Use payment only for a payment made to the card account itself, such as \
            PAYMENT - THANK YOU. Use refund for money a shop gave back.
            """)
        var kind: String?
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
    /// Necessary but not sufficient: a model reporting `.available` still throws when asked
    /// to generate in the Simulator, where the generative assets are absent. This gate only
    /// avoids pointless work — the fallback is what makes the import safe.
    var isAvailable: Bool { model.availability == .available }

    /// Extracts what the model can read, a page at a time.
    /// - Parameters:
    ///   - statement: The recognised text.
    ///   - context: The clock and calendar.
    /// - Returns: What was extracted, or an empty document if the model could not help.
    func extract(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) async -> StatementDocument {
        guard isAvailable, !statement.isEmpty else { return StatementDocument() }

        var document = StatementDocument(source: .onDeviceModel)
        for page in statement.pages where !page.isEmpty {
            guard let extracted = await read(page) else { continue }
            merge(extracted, into: &document, context: context)
        }
        return document.rows.isEmpty ? StatementDocument() : document
    }

    /// Asks the model about one page.
    /// - Parameter page: The page's recognised text.
    /// - Returns: What the model returned, or `nil` when it could not answer.
    private func read(_ page: RecognizedReceipt) async -> ExtractedPage? {
        do {
            let session = LanguageModelSession(model: model) { Self.instructions }
            let response = try await session.respond(
                to: page.transcript, generating: ExtractedPage.self
            )
            return response.content
        } catch {
            // The model declining, the session being interrupted, a page too dense to fit,
            // and the Simulator's missing assets all mean the same thing: skip this page
            // and keep the ones that worked.
            return nil
        }
    }

    /// Folds one page's answer into the document being built.
    /// - Parameters:
    ///   - page: What the model returned for the page.
    ///   - document: The document being built.
    ///   - context: The clock and calendar.
    private func merge(
        _ page: ExtractedPage,
        into document: inout StatementDocument,
        context: StatementParseContext
    ) {
        if document.tender.last4 == nil, let last4 = Self.digits(page.last4) {
            document.tender.last4 = last4
        }
        if document.closingDate == nil {
            document.closingDate = ReceiptModelValues.date(
                from: page.closingDate, now: context.now, calendar: context.calendar
            )
        }
        document.rows.append(contentsOf: page.rows.compactMap { Self.row(from: $0, context: context) })
    }
}
