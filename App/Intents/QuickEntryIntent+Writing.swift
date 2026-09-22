import AppIntents
import Foundation
import UIKit
import Domain
import Features

/// Turning a quick entry's parameters into records (§15, §9.3).
///
/// Split from ``QuickEntryIntent`` itself to keep each file within the 300-line limit.
extension QuickEntryIntent {

    /// Converts the amount parameter into cents.
    ///
    /// The amount carries no currency, because the app has none to choose from: every
    /// figure renders in the one code set in Settings and nothing is ever converted
    /// (§5.1). `Double` reaches no further than this call — ``MoneyInput`` turns it
    /// into `Int` cents, which is the only form money takes anywhere else (§2).
    ///
    /// - Returns: The amount in cents.
    /// - Throws: ``QuickEntryError/unusableAmount`` when the number cannot be used.
    func centsFromAmount() throws -> Int {
        guard let cents = MoneyInput.cents(fromAmount: amount) else {
            throw QuickEntryError.unusableAmount
        }
        return cents
    }

    /// Decides everything the expense implies, before anything is written.
    /// - Parameters:
    ///   - amountCents: The amount in cents.
    ///   - accountID: The account ``resolveAccount(dependencies:)`` settled on, or `nil`
    ///     when it settled on none and the entry is being parked (§15.5).
    ///   - dependencies: The app's dependency graph.
    /// - Returns: The plan.
    /// - Throws: ``QuickEntryError/unusableCategory(_:)``,
    ///   ``QuickEntryError/beyondLimits(_:)``, or a persistence error.
    @MainActor
    func makePlan(
        amountCents: Int,
        accountID: UUID?,
        dependencies: AppDependencies
    ) async throws -> QuickExpensePlan {
        var input = QuickExpenseInput(
            amountCents: amountCents,
            merchant: merchant,
            accountID: accountID,
            date: date ?? .now,
            type: Self.entryType
        )
        input.categoryText = category
        input.tags = tags ?? []
        input.location = location
        input.memo = memo
        input.remembersCategory = rememberCategory

        let context = QuickExpenseContext(
            selectableCategories: try await dependencies.categories
                .selectableCategories(context: Self.categoryContext),
            pins: try await dependencies.merchantRules.rules()
        )
        do {
            return try QuickExpensePlanner.plan(input, in: context)
        } catch let problem as CategoryNaming.Problem {
            throw QuickEntryError.unusableCategory(problem)
        } catch let problem as QuickEntryProblem {
            throw QuickEntryError.beyondLimits(problem)
        }
    }

    /// The entry this one repeats, if a run has already recorded it (§15.6).
    ///
    /// Only the candidate's own day is fetched. ``TransactionFingerprint`` puts the day in
    /// the key, so nothing outside it can match however close the clock says it is — and the
    /// whole ledger would be a great deal to read on every coffee.
    ///
    /// - Parameters:
    ///   - candidate: The entry about to be written.
    ///   - dependencies: The app's dependency graph.
    /// - Returns: The entry already stored, or `nil` when this one is new.
    /// - Throws: A persistence error if the fetch fails.
    @MainActor
    func duplicate(
        of candidate: Domain.Transaction,
        dependencies: AppDependencies
    ) async throws -> Domain.Transaction? {
        guard !allowsDuplicate else { return nil }
        guard let range = QuickExpenseDuplicateGuard.searchRange(for: candidate) else {
            return nil
        }
        // `accountID: nil` here means *every* account, not a parked entry — the fingerprint
        // is what narrows it, and it narrows parked entries to other parked entries.
        let sameDay = try await dependencies.transactions.transactions(
            accountID: nil, in: range
        )
        return QuickExpenseDuplicateGuard.duplicate(of: candidate, among: sameDay)
    }

    /// Writes the plan, receipts included.
    ///
    /// One commit, through ``QuickEntryWriting``, rather than four repository saves. A
    /// Shortcut can imply a created card, an invented category, the entry and a merchant
    /// pin; four separate commits mean a failure at the third leaves the first two behind,
    /// in a process that is about to end with nothing on screen to explain them.
    ///
    /// The receipt identifiers still have to be on the transaction before it goes, which is
    /// why the pages are captured first — but the capture is to an in-memory cache, so
    /// nothing outlives a refused write except files the next launch evicts.
    ///
    /// - Parameters:
    ///   - plan: What to write.
    ///   - newAccount: An account to create alongside it, when the number named one that did
    ///     not exist yet.
    ///   - dependencies: The app's dependency graph.
    /// - Throws: ``QuickEntryError/beyondLimits(_:)`` when the receipt is too large, or a
    ///   persistence error if the write fails.
    @MainActor
    func commit(
        _ plan: QuickExpensePlan,
        newAccount: Domain.Account?,
        dependencies: AppDependencies
    ) async throws {
        var transaction = plan.transaction
        let storage = ReceiptStorageCoordinator(
            store: dependencies.receiptStore,
            transactions: dependencies.transactions,
            backups: dependencies.backupWriter,
            settings: dependencies.settings
        )
        let pages = try await receiptPages()
        if !pages.isEmpty {
            let ids = storage.capturePages(pages, for: transaction)
            transaction.receiptFileID = ids.first
            transaction.receiptFileName = receipts?.first?.filename
            transaction.receiptUploadState = .pending
        }

        try await dependencies.quickEntries.write(QuickEntryWrite(
            transaction: transaction,
            newAccount: newAccount,
            newCategory: plan.newCategory,
            newPin: plan.newPin
        ))

        // The upload queue is an in-memory cache, and nothing keeps this process alive
        // once the intent returns — so a receipt not flushed here is simply lost.
        if !pages.isEmpty { await storage.flushUploads() }

        // Refreshes the account options behind the parameterised phrase ("Add a Chetta Cash
        // expense to Chequing"), which the system caches. Without this a card created here
        // is unreachable by that phrase until the app is next foregrounded, since the only
        // other caller sits in the app's own `reconcile`. The *picker's* lookup does not
        // depend on it: `AccountEntityQuery.entities(matching:)` reads the live store every
        // time.
        if newAccount != nil { ChettaCashShortcuts.updateAppShortcutParameters() }
    }

    /// The bytes to store for each supplied file, in order.
    ///
    /// Photographs are reduced to the same size the in-app scanner stores, so a Shortcut
    /// cannot quietly fill the receipt cache with 12-megapixel originals. Nothing is *read*:
    /// this path attaches a receipt, it does not scan one, so no text recognition and no
    /// model runs here.
    ///
    /// Each original is released as soon as its reduced copy exists, and the running total is
    /// checked as it goes. A background intent is given very little memory, and holding every
    /// original, every decoded bitmap and every JPEG at once is how it gets killed part way
    /// through a write — which is the one outcome worse than refusing the receipt.
    ///
    /// This is a `nonisolated async` function on a non-isolated type, which under SE-0338
    /// means it does **not** inherit `commit`'s main actor: `UIImage(data:)` already runs off
    /// the main thread. Do not "fix" that by adding `@MainActor`.
    ///
    /// - Returns: The compressed bytes, one entry per usable file.
    /// - Throws: ``QuickEntryProblem/receiptTooLarge`` when there are too many pages or too
    ///   many bytes.
    func receiptPages() async throws -> [Data] {
        let files = receipts ?? []
        guard files.count <= QuickEntryLimits.maximumReceiptPages else {
            throw QuickEntryProblem.receiptTooLarge
        }

        var pages: [Data] = []
        var total = 0
        for file in files {
            guard let page = await storablePage(for: file) else { continue }
            total += page.count
            guard total <= QuickEntryLimits.maximumReceiptBytes else {
                throw QuickEntryProblem.receiptTooLarge
            }
            pages.append(page)
        }
        return pages
    }

    /// The bytes to store for one supplied file.
    ///
    /// Scoped to its own function so the original `Data` and the decoded `UIImage` both fall
    /// out of scope before the next file is read, rather than piling up for the length of the
    /// loop.
    ///
    /// - Parameter file: The file as the Shortcuts app handed it over.
    /// - Returns: The bytes to store, or `nil` when the file held nothing.
    private func storablePage(for file: IntentFile) async -> Data? {
        let data = file.data
        guard !data.isEmpty else { return nil }
        guard let image = UIImage(data: data),
              let reduced = await ReceiptCompression.storableDataOffMainActor(for: image) else {
            // A PDF, or an image this device cannot decode. Stored as it arrived rather than
            // dropped: the user asked for it to be kept.
            return data
        }
        return reduced
    }
}
