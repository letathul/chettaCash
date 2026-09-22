import Foundation
import Testing
@testable import Features
import Domain

/// Reading again the lines every deterministic parser failed on (§9.7).
@MainActor
@Suite("Unread line repair")
struct UnreadLineRepairTests {

    /// A fixed moment, so no test depends on the wall clock.
    private static let now = Date(timeIntervalSince1970: 1_789_000_000)

    /// Builds an import whose statement carries the given unread lines.
    /// - Parameters:
    ///   - unread: The lines no parser could read.
    ///   - repairer: What to answer with when asked.
    /// - Returns: The model, already begun.
    private func begin(
        unread: [UnreadLine],
        repairer: any UnreadLineRepairing = FakeRowRepairer()
    ) async -> StatementImportViewModel {
        let accounts = FakeAccountRepository()
        var card = Domain.Account(name: "Visa", kind: .card)
        card.last4 = "4417"
        try? await accounts.save(card)

        var document = StatementDocument(
            tender: ReceiptTender(last4: "4417"),
            rows: [
                StatementRow(
                    date: Self.now, rawDescriptor: "BLUE BOTTLE", amountCents: 675
                )
            ]
        )
        document.unread = unread
        document.sourceLineCount = 1 + unread.count

        let model = StatementImportViewModel(
            coordinator: StatementImportCoordinator(
                accounts: accounts,
                transactions: FakeTransactionRepository(accounts: accounts),
                categories: FakeCategoryRepository()
            ),
            settings: AppSettings(),
            importer: StatementImporter(
                reader: FakeStatementReader(
                    statement: RecognizedStatement(pages: [RecognizedReceipt(lines: [
                        RecognizedLine(text: "placeholder", topFraction: 0)
                    ])])
                ),
                primary: FakeStatementExtractor(document: document),
                fallback: FakeStatementExtractor(),
                adjudicator: FakeDuplicateAdjudicator(),
                backupAdjudicator: HeuristicDuplicateAdjudicator(),
                repairer: repairer
            )
        )
        await model.begin(.pdfData(Data()))
        return model
    }

    @Test("A line no parser could read is shown rather than dropped")
    func unreadLinesAreShown() async {
        let model = await begin(
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)]
        )

        #expect(model.reviewDrafts.count == 2, "the row that parsed and the line that did not")
        #expect(model.reviewSummary.needsAttention == 1)
        #expect(model.canRepairUnreadLines)
        #expect(model.repairButtonTitle.contains("1 line"))
    }

    @Test("A repaired line becomes an ordinary row, unticked")
    func repairedLineBecomesARow() async {
        let repairer = FakeRowRepairer(answers: [
            "Jul 16 HONK PARKING 3.45": StatementRow(
                date: Self.now, rawDescriptor: "HONK PARKING", amountCents: 345
            )
        ])
        let model = await begin(
            unread: [
                UnreadLine(text: "Jul 16 HONK PARKING 3.45", lineNumber: 4, problem: .noAmount)
            ],
            repairer: repairer
        )

        let repaired = await model.repairUnreadLines()

        #expect(repaired == 1)
        let draft = model.reviewDrafts.first { $0.merchant == "HONK PARKING" }
        #expect(draft?.amountCents == 345)
        #expect(draft?.isTicked == false, "a model's reading of a hard line is offered, not applied")
        #expect(model.reviewSummary.needsAttention == 0)
    }

    @Test("A repaired line keeps the statement's own wording")
    func repairKeepsTheSourceText() async {
        let repairer = FakeRowRepairer(answers: [
            "odd line": StatementRow(
                date: Self.now, rawDescriptor: "HONK PARKING", amountCents: 345
            )
        ])
        let model = await begin(
            unread: [UnreadLine(text: "odd line", lineNumber: 4, problem: .noAmount)],
            repairer: repairer
        )

        await model.repairUnreadLines()

        #expect(model.reviewDrafts.contains { $0.sourceText == "odd line" })
    }

    @Test("A repaired card payment is still refused")
    func repairedPaymentStaysExcluded() async {
        let repairer = FakeRowRepairer(answers: [
            "odd line": StatementRow(
                date: Self.now, rawDescriptor: "PAYMENT - THANK YOU",
                amountCents: 50_000, kind: .payment
            )
        ])
        let model = await begin(
            unread: [UnreadLine(text: "odd line", lineNumber: 4, problem: .noAmount)],
            repairer: repairer
        )

        await model.repairUnreadLines()

        let draft = model.reviewDrafts.first { $0.sourceText == "odd line" }
        #expect(draft?.isTicked == false)
        if case .excluded(.cardPayment) = draft?.status {} else {
            Issue.record("a card payment must stay excluded however it was read")
        }
    }

    @Test("A model that reads nothing says so and changes no row")
    func unhelpfulRepairSaysSo() async {
        let model = await begin(
            unread: [UnreadLine(text: "9.30", lineNumber: 4, problem: .noDate)]
        )

        let repaired = await model.repairUnreadLines()

        #expect(repaired == 0)
        #expect(model.errorMessage != nil)
        #expect(model.reviewSummary.needsAttention == 1, "the line is still there to type in")
    }

    @Test("With nothing unread there is nothing to offer")
    func nothingToRepair() async {
        let model = await begin(unread: [])

        #expect(model.canRepairUnreadLines == false)
        #expect(await model.repairUnreadLines() == 0)
    }
}
