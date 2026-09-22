import Foundation
import Testing
import Domain
@testable import Features

/// What a statement dropped into `AppTests/Fixtures` is expected to yield.
struct RealStatementExpectation: Sendable {
    /// The fixture's file name, without its extension.
    let name: String
    /// The fewest transaction rows the reader must recover.
    let minimumRows: Int
    /// How many of them are card payments.
    let payments: Int
}

/// The statements to check, when present.
///
/// Declared outside the suite because a `@Test` argument list is evaluated off the main actor.
let realStatementExpectations = [
    // A Rogers Bank Mastercard whose text layer runs rows together: pages of 7, 58 and 15.
    RealStatementExpectation(name: "RogersStatement", minimumRows: 78, payments: 2)
]

/// Locates the test bundle, which is where a dropped-in fixture is copied to.
final class RealStatementBundleMarker {}

/// Reads a real bank statement, when one has been dropped into `AppTests/Fixtures`.
///
/// **Opt-in by design.** A real statement carries a card number, an account number and an
/// address, so `AppTests/Fixtures/*.pdf` is git-ignored and these tests pass vacuously when the
/// file is absent. They exist so a statement that imports badly can be turned into a
/// reproduction in one step: drop the PDF in, set the expectations, and the failure is on the
/// fast loop.
@MainActor
@Suite("Real statement reading")
struct RealStatementTests {

    /// The clock the rows resolve against, inside the statements' own period.
    private var context: StatementParseContext {
        StatementParseContext(now: Date(timeIntervalSince1970: 1_787_000_000))
    }

    /// Reads a fixture, when it is there.
    /// - Parameter name: The file name, without its extension.
    /// - Returns: The recognised statement, or `nil` when no such fixture is bundled.
    private func read(_ name: String) async throws -> RecognizedStatement? {
        guard let url = Bundle(for: RealStatementBundleMarker.self)
            .url(forResource: name, withExtension: "pdf") else { return nil }
        return try await StatementFileReader().read(.url(url))
    }

    @Test("Every transaction line is recovered", arguments: realStatementExpectations)
    func recoversEveryRow(_ expectation: RealStatementExpectation) async throws {
        guard let statement = try await read(expectation.name) else { return }
        let rows = StatementTextParser.rows(from: statement, context: context)

        #expect(
            rows.count >= expectation.minimumRows,
            Comment(rawValue: "\(expectation.name): read \(rows.count) rows, expected at least "
                + "\(expectation.minimumRows)")
        )
        #expect(rows.count { $0.kind == .payment } == expectation.payments)
    }

    @Test("Only a line printed as a credit reads as one", arguments: realStatementExpectations)
    func signsAreFaithful(_ expectation: RealStatementExpectation) async throws {
        guard let statement = try await read(expectation.name) else { return }
        let rows = StatementTextParser.rows(from: statement, context: context)

        // Every credit on a card statement is printed with a minus, a trailing CR, or in
        // parentheses. A charge that reads as a credit is the bug this guards.
        for row in rows where row.kind != .charge {
            // Any line naming this shop, rather than one matched by amount: a statement
            // prints "4,201.00" where the row holds 420100 cents, and a shop that is charged
            // and refunded on one day has two lines either way. A descriptor that never
            // appears credit-marked anywhere on the statement is the mis-sign worth catching.
            let credited = statement.lines.contains { line in
                guard line.text.contains(row.rawDescriptor) else { return false }
                let text = line.text.trimmingCharacters(in: .whitespaces)
                return text.contains("-") || text.contains("\u{2212}") || text.contains("(")
                    || text.uppercased().hasSuffix("CR")
            }
            #expect(
                credited,
                Comment(rawValue: "read as \(row.kind) but no line for "
                    + "<\(row.rawDescriptor)> was printed as a credit")
            )
        }
    }
}
