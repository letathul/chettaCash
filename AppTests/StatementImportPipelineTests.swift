import Foundation
import Testing
import Domain
@testable import Features

/// Reading a real PDF end to end, in the host app where PDFKit and Vision actually run.
@MainActor
@Suite("Statement file reading")
struct StatementImportPipelineTests {

    /// The clock and calendar the rows resolve against.
    private var context: StatementParseContext {
        StatementParseContext(now: Date(timeIntervalSince1970: 1_772_000_000))
    }

    @Test("A statement PDF is read through its own text layer, not recognition")
    func embeddedTextIsPreferred() async throws {
        // Text drawn into a PDF is exact, where recognition confuses 5 for S in an amount
        // column with nothing to check it against.
        let reader = StatementFileReader()

        let statement = try await reader.read(.pdfData(StatementFixture.pdfData()))

        #expect(statement.usedEmbeddedText)
        #expect(!statement.isEmpty)
    }

    @Test("Every printed transaction line is recovered with its amount")
    func rowsAreParsed() async throws {
        let reader = StatementFileReader()
        let statement = try await reader.read(.pdfData(StatementFixture.pdfData()))

        let rows = StatementTextParser.rows(from: statement, context: context)

        for expected in StatementFixture.rows {
            let match = rows.first { $0.rawDescriptor == expected.descriptor }
            #expect(match?.amountCents == expected.cents)
        }
    }

    @Test("A refund reads as income and a payment is marked to be left out")
    func creditsAreClassified() async throws {
        let reader = StatementFileReader()
        let statement = try await reader.read(.pdfData(StatementFixture.pdfData()))

        let rows = StatementTextParser.rows(from: statement, context: context)

        #expect(rows.contains { $0.rawDescriptor == "UNIQLO RETURN" && $0.kind == .refund })
        #expect(rows.contains { $0.kind == .payment })
    }

    @Test("Summary lines and headings do not become transactions")
    func headingsAreNotRows() async throws {
        let reader = StatementFileReader()
        let statement = try await reader.read(.pdfData(StatementFixture.pdfData()))

        let rows = StatementTextParser.rows(from: statement, context: context)

        // Three charges, one refund, one payment — and nothing from the four header lines.
        #expect(rows.count == 5)
    }

    @Test("The card's digits are read off the statement")
    func tenderIsRead() async throws {
        let reader = StatementFileReader()
        let statement = try await reader.read(.pdfData(StatementFixture.pdfData()))

        let tender = TenderParser.parse(statement.lines)

        #expect(tender.last4 == StatementFixture.last4)
    }

    @Test("A PDF with no text layer falls through to recognition")
    func imageOnlyPDFUsesRecognition() async throws {
        let reader = StatementFileReader()

        let statement = try? await reader.read(.pdfData(StatementFixture.imageOnlyPDFData()))

        // Either recognition found nothing legible and it threw, or it ran — but it must
        // never claim an embedded text layer it does not have.
        #expect(statement?.usedEmbeddedText != true)
    }

    @Test("A file that is not a PDF or an image is refused by name")
    func unreadableFilesAreNamed() async {
        let reader = StatementFileReader()

        await #expect(throws: StatementImportError.unreadableFile) {
            try await reader.read(.pdfData(Data("not a pdf".utf8)))
        }
    }
}
