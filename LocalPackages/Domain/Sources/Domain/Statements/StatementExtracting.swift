import Foundation

/// A statement's recognised text, page by page.
///
/// Kept per page rather than as one transcript because the on-device model is asked one
/// page at a time: a whole statement does not fit in one prompt, and a page that defeats
/// the model must cost only its own rows.
public struct RecognizedStatement: Equatable, Sendable {
    /// Each page's recognised text, in order.
    public var pages: [RecognizedReceipt]
    /// Whether the text came from the file's own text layer rather than from recognition.
    ///
    /// A text layer gives the exact characters; recognition can confuse `5` for `S` in an
    /// amount column, where there is no second source to check against.
    public var usedEmbeddedText: Bool

    /// Every page as continuous text.
    public var transcript: String {
        pages.map(\.transcript).joined(separator: "\n")
    }

    /// Every recognised line across every page.
    public var lines: [RecognizedLine] { pages.flatMap(\.lines) }

    /// Whether nothing legible was found.
    public var isEmpty: Bool { pages.allSatisfy(\.isEmpty) }

    /// Creates a recognised statement.
    /// - Parameters:
    ///   - pages: Each page's recognised text.
    ///   - usedEmbeddedText: Whether the text came from the file's own text layer.
    public init(pages: [RecognizedReceipt], usedEmbeddedText: Bool = false) {
        self.pages = pages
        self.usedEmbeddedText = usedEmbeddedText
    }
}

/// What a statement reader needs to know beyond the statement itself.
public struct StatementParseContext: Sendable {
    /// The moment used to reject implausible dates.
    public var now: Date
    /// The calendar dates are resolved in.
    public var calendar: Calendar
    /// Which of a numeric date's first two numbers is the month.
    ///
    /// Settled once for the whole file — see ``StatementDateOrder`` for why it cannot be
    /// decided per line.
    public var dateOrder: StatementDateOrder

    /// Creates a context.
    /// - Parameters:
    ///   - now: The moment used to reject implausible dates.
    ///   - calendar: The calendar dates are resolved in.
    ///   - dateOrder: Which number is the month. Defaults to month-first.
    public init(
        now: Date = .now,
        calendar: Calendar = .current,
        dateOrder: StatementDateOrder = .monthFirst
    ) {
        self.now = now
        self.calendar = calendar
        self.dateOrder = dateOrder
    }
}

/// Reads a statement's rows out of its recognised text (§9.7).
///
/// Declared in Domain, like ``ReceiptExtracting``, so the framework-backed implementation
/// lives in Features and a test can substitute a fake without a simulator.
public protocol StatementExtracting: Sendable {
    /// Extracts what it can.
    ///
    /// Never throws: a reader that cannot help returns an empty document and the caller
    /// moves on to the next one.
    ///
    /// - Parameters:
    ///   - statement: The recognised text.
    ///   - context: What the reader needs beyond the text.
    /// - Returns: What could be extracted.
    func extract(
        from statement: RecognizedStatement,
        context: StatementParseContext
    ) async -> StatementDocument
}

/// Merging two readers' results.
extension StatementDocument {

    /// Fills this document's gaps from another reader's.
    ///
    /// **Merged by count, not by identity.** Two readers shown the same page both report the
    /// same line, so the rows cannot simply be appended. But a statement genuinely can list
    /// the same shop twice on one day for the same amount — two transit fares, two coffees —
    /// and by content those two cases are identical. What tells them apart is *how many* times
    /// each reader saw the line: one reading each means one line read twice, two readings each
    /// means two purchases. So the merged count is the larger of the two, which keeps a real
    /// repeat and still collapses a double reading.
    ///
    /// This is the same rule ``StatementImportPlanner`` applies against the ledger, and for the
    /// same reason: a bank printing a line twice is reporting two purchases.
    ///
    /// The richer reading wins per row: a tidied merchant name from the model survives the
    /// fallback's raw descriptor.
    ///
    /// - Parameter other: The other reader's document.
    /// - Returns: The merged document.
    public func completed(with other: StatementDocument) -> StatementDocument {
        var merged = self
        merged.tender = ReceiptTender(
            last4: tender.last4 ?? other.tender.last4,
            network: tender.network ?? other.tender.network
        )
        merged.periodStart = periodStart ?? other.periodStart
        merged.closingDate = closingDate ?? other.closingDate

        let mine = counts(of: rows)
        let theirs = counts(of: other.rows)
        var appended: [String: Int] = [:]
        for row in other.rows {
            let key = Self.mergeKey(row)
            let held = (mine[key] ?? 0) + (appended[key] ?? 0)
            // Keep appending this line until the merged document holds it as often as
            // whichever reader saw it most. Beyond that, the sighting is the same line read
            // twice rather than a second purchase.
            guard held < max(mine[key] ?? 0, theirs[key] ?? 0) else { continue }
            appended[key, default: 0] += 1
            merged.rows.append(row)
        }
        merged.rows.sort { $0.date < $1.date }

        // The wider source count stands: a reader that saw more of the file saw more of it.
        // Unread lines are de-duplicated on their text, because both readers were given the
        // same page and both will have failed on the same lines.
        merged.unread = (unread + other.unread)
            .reduce(into: [UnreadLine]()) { result, line in
                let key = line.text.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !result.contains(where: {
                    $0.text.trimmingCharacters(in: .whitespaces) == key
                }) else { return }
                result.append(line)
            }
        merged.sourceLineCount = max(sourceLineCount, other.sourceLineCount)
        return merged
    }

    /// How many times each merge key appears among some rows.
    /// - Parameter rows: The rows to tally.
    /// - Returns: The count per key.
    private func counts(of rows: [StatementRow]) -> [String: Int] {
        rows.reduce(into: [:]) { tally, row in
            tally[Self.mergeKey(row), default: 0] += 1
        }
    }

    /// The key two readings of one line share.
    ///
    /// **The merchant is part of the key.** Without it, two genuinely different purchases of
    /// the same amount on the same day collapse into one before the planner ever sees them —
    /// and a card statement is full of those: two coffees, two transit fares, two trips to
    /// the same shop. One real statement carried four such pairs, and lost one of each.
    /// Normalised through ``MerchantCategoryIndex/key(for:)`` so the model's tidied name and
    /// the fallback's raw descriptor still key alike when they name the same shop.
    ///
    /// - Parameter row: The row to key.
    /// - Returns: The merge key.
    private static func mergeKey(_ row: StatementRow) -> String {
        let day = Int(row.date.timeIntervalSince1970 / 86_400)
        let merchant = MerchantCategoryIndex.key(for: row.merchant)
        return "\(day)|\(row.amountCents)|\(row.kind.rawValue)|\(merchant)"
    }
}
