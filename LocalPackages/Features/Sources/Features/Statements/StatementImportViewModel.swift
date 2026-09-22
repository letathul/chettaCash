import Foundation
import Observation
import Domain

/// Drives a statement import and the review that decides what it writes (§4.2, §9.7).
///
/// **Nothing is written until the user approves it.** The import used to commit its additions
/// inside the planning step, before any screen appeared, and then offer a wizard covering only
/// the rows that collided with the ledger — so a misread amount, a charge filed as income, or
/// a line the reader dropped all reached the ledger, or failed to, unseen. Reading, planning
/// and duplicate adjudication still run up front; they now end in ``reviewDrafts``, and
/// ``approve()`` is the only thing that writes.
///
/// **The review outlives the sheet.** The drafts are model state, so dismissing the screen
/// part-way leaves the import intact and the Settings row reappears offering to finish it.
@MainActor
@Observable
public final class StatementImportViewModel {

    /// How far along the current import is.
    public var phase: StatementImportPhase { importer.phase }
    /// Which card the statement was matched to, once it has been read.
    public private(set) var accountMatch: StatementAccountMatch?
    /// The open accounts, for the picker shown when the match is ambiguous.
    public private(set) var accounts: [Domain.Account] = []
    /// The categories the review's row editors offer.
    public internal(set) var categories: [Domain.Category] = []
    /// The statement as read, held while the user confirms the card.
    public private(set) var document: StatementDocument?
    /// What the import did, once the user has approved it.
    public internal(set) var outcome: ImportOutcome?
    /// A failure to surface above the content.
    public internal(set) var errorMessage: String?
    /// Which rows the list is showing.
    public var filter: ImportReviewFilter = .all
    /// Whether the approval write is in flight.
    public internal(set) var isApproving = false

    /// Every row of the statement, in review order.
    var drafts: [StatementReviewDraft] = []
    /// How many lines the statement held, counted at the source.
    var sourceLineCount = 0
    /// What a reader concluded about each duplicate, by conflict.
    var rationales: [UUID: String] = [:]
    /// The card the import is filed against, once it is settled.
    var accountID: UUID?
    /// The plan being reviewed.
    var plan: ImportPlan?
    /// Reads the file and judges duplicates.
    let importer: StatementImporter
    /// Writes what the review approves.
    let coordinator: StatementImportCoordinator
    /// The display currency and other user preferences.
    let settings: AppSettings

    /// Whether a review is waiting to be finished.
    public var hasPendingReview: Bool { !drafts.isEmpty && outcome == nil }
    /// The label the Settings row carries when a review is waiting.
    public var resumeButtonTitle: String {
        "Finish reviewing (\(drafts.count) \(drafts.count == 1 ? "row" : "rows"))"
    }

    /// Creates the view model.
    ///
    /// Internal rather than public because ``StatementImporter`` is, like ``ReceiptScanner``:
    /// the composition root builds the coordinator and Settings builds this, so nothing
    /// outside the module ever needs to.
    ///
    /// - Parameters:
    ///   - coordinator: Writes what the review approves.
    ///   - settings: The display currency and other user preferences.
    ///   - importer: Reads the file and judges duplicates.
    init(
        coordinator: StatementImportCoordinator,
        settings: AppSettings,
        importer: StatementImporter = StatementImporter()
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.importer = importer
    }

    /// Reads a picked file and works out which card it belongs to.
    /// - Parameter source: What the user picked.
    func begin(_ source: StatementFileSource) async {
        reset()
        do {
            accounts = try await coordinator.openAccounts()
            categories = (try? await coordinator.selectableCategories()) ?? []
            let read = try await importer.read(source)
            guard !read.isEmpty || !read.unread.isEmpty else {
                errorMessage = "No transactions could be read from that statement."
                return
            }
            document = read
            accountMatch = try await coordinator.resolveAccount(for: read)
            if case .matched(let id) = accountMatch {
                await runImport(accountID: id)
            }
        } catch let failure as StatementImportError {
            errorMessage = Self.message(for: failure)
        } catch {
            errorMessage = "Could not read that statement."
        }
    }

    /// Imports against a card the user chose or confirmed.
    /// - Parameter accountID: The card to import against.
    public func confirmAccount(_ accountID: UUID) async {
        await runImport(accountID: accountID)
    }

    /// Creates the card the statement named, then imports against it.
    public func createSuggestedAccount() async {
        guard case .unknown(let proposed) = accountMatch else { return }
        do {
            try await coordinator.create(proposed)
            accounts = try await coordinator.openAccounts()
            accountMatch = .matched(proposed.id)
            await runImport(accountID: proposed.id)
        } catch {
            errorMessage = "Could not create that card."
        }
    }

    /// Clears everything from a previous import.
    func reset() {
        accountMatch = nil
        document = nil
        outcome = nil
        errorMessage = nil
        plan = nil
        drafts = []
        rationales = [:]
        sourceLineCount = 0
        accountID = nil
        categories = []
        filter = .all
        isApproving = false
    }

    /// What to tell the user about a file that could not be read.
    /// - Parameter failure: What went wrong.
    /// - Returns: The message.
    static func message(for failure: StatementImportError) -> String {
        switch failure {
        case .passwordProtected:
            return "That statement is password-protected. Open it and save an unlocked copy first."
        case .unreadableFile:
            return "That file is not a PDF, an image or a CSV this app can read."
        case .noPages:
            return "That statement has no pages."
        case .accessDenied:
            return "Could not open that file."
        case .noTextFound:
            return "No readable text was found in that statement."
        case .unreadableCSV:
            return "That export could not be read as text. Re-save it as CSV and try again."
        case .noColumnsFound:
            return "That export's columns could not be identified. "
                + "It needs a header row naming at least a date and an amount."
        }
    }
}
