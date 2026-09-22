import Foundation
import Testing
@testable import Domain

/// Naming the extra pages of one receipt (§9.3).
///
/// A transaction stores one receipt identifier, so a receipt too long for one
/// photograph keeps its extra pages as siblings of the first and is found again by
/// shared prefix rather than by a second database column.
@Suite("Multi-page receipt naming")
struct ReceiptPageNamingTests {

    /// Page one's identifier, as ``ReceiptNaming/fileID(date:merchant:amountCents:ownerID:)``
    /// would build it.
    private var base: String { "Receipts/2026/2026-09/2026-09-12_whole-foods_42.10_a3f9.jpg" }

    @Test("Page one is the identifier the transaction already stores")
    func pageOneIsTheBase() {
        #expect(ReceiptNaming.pageFileID(baseFileID: base, page: 1) == base)
    }

    @Test("A later page is a sibling in the same folder")
    func laterPagesAreSiblings() {
        let page2 = ReceiptNaming.pageFileID(baseFileID: base, page: 2)

        #expect(page2 == "Receipts/2026/2026-09/2026-09-12_whole-foods_42.10_a3f9-p2.jpg")
    }

    @Test("The suffix goes before the extension so the file type survives")
    func keepsTheExtension() {
        let page3 = ReceiptNaming.pageFileID(baseFileID: base, page: 3)

        #expect(page3.hasSuffix(".jpg"), "a viewer reads the type from the extension")
    }

    @Test("An identifier with no extension still pages")
    func handlesNoExtension() {
        let paged = ReceiptNaming.pageFileID(baseFileID: "Receipts/2026/2026-09/scan", page: 2)

        #expect(paged == "Receipts/2026/2026-09/scan-p2")
    }

    @Test("Every page of one receipt shares a prefix")
    func sharesAPrefix() {
        let prefix = ReceiptNaming.pagePrefix(forBaseFileID: base)

        #expect(base.hasPrefix(prefix))
        #expect(ReceiptNaming.pageFileID(baseFileID: base, page: 2).hasPrefix(prefix))
    }

    @Test("A page is recognised as belonging to its receipt")
    func recognisesItsOwnPages() {
        let page2 = ReceiptNaming.pageFileID(baseFileID: base, page: 2)

        #expect(ReceiptNaming.isPage(base, ofBaseFileID: base))
        #expect(ReceiptNaming.isPage(page2, ofBaseFileID: base))
    }

    @Test("Pages are numbered so they can be ordered", arguments: [1, 2, 3, 10])
    func readsThePageNumber(page: Int) {
        let id = ReceiptNaming.pageFileID(baseFileID: base, page: page)

        #expect(ReceiptNaming.pageNumber(of: id, ofBaseFileID: base) == page)
    }

    @Test("Page ten sorts after page two, which sorting as text would not do")
    func ordersNumericallyNotAlphabetically() {
        let page2 = ReceiptNaming.pageFileID(baseFileID: base, page: 2)
        let page10 = ReceiptNaming.pageFileID(baseFileID: base, page: 10)

        let ordered = [page10, base, page2].compactMap { id in
            ReceiptNaming.pageNumber(of: id, ofBaseFileID: base).map { (id, $0) }
        }.sorted { $0.1 < $1.1 }.map(\.0)

        #expect(ordered == [base, page2, page10])
        #expect([page10, base, page2].sorted() != ordered, "text order really is wrong here")
    }

    @Test("Another transaction's receipt is not mistaken for a page")
    func rejectsAStranger() {
        let other = "Receipts/2026/2026-09/2026-09-12_whole-foods_42.10_b7c1.jpg"

        #expect(!ReceiptNaming.isPage(other, ofBaseFileID: base), "a sibling file is not a page")
    }
}
