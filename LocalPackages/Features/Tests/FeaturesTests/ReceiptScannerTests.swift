import Foundation
import Testing
import UIKit
@testable import Features
import Domain

/// The scan pipeline's fallback chain (§9.7).
///
/// The real readers are exercised in the hosted `AppTests` target, which is where
/// Vision and FoundationModels can actually run. What is checked here is the rule
/// that makes the feature safe: **the on-device model reporting itself available is
/// not a guarantee that it will answer**, so a model that throws, declines, or
/// returns nothing must hand the page to the heuristics rather than fail the scan.
@Suite("Receipt scan fallback")
@MainActor
struct ReceiptScannerTests {

    /// A recognizer that returns fixed text, or throws.
    struct FakeRecognizer: ReceiptRecognizing {
        /// The text to return.
        var receipt = RecognizedReceipt(lines: [
            RecognizedLine(text: "LOBLAWS", topFraction: 0.05),
            RecognizedLine(text: "TOTAL 42.10", topFraction: 0.8)
        ])
        /// Whether to throw instead.
        var fails = false

        func recognize(_ image: UIImage) async throws -> RecognizedReceipt {
            if fails { throw ReceiptRecognitionError.unreadableImage }
            return receipt
        }
    }

    /// An extractor that returns whatever it was given.
    struct FakeExtractor: ReceiptExtracting {
        /// The result to return.
        var result: ReceiptScanResult

        func extract(
            from receipt: RecognizedReceipt, context: ReceiptScanContext
        ) async -> ReceiptScanResult {
            result
        }
    }

    /// An extractor that reports the scanner's phase while it is running.
    ///
    /// The phase is only observable from *inside* the scan — by the time `scan` returns
    /// it is back to idle — so the fake reads it as it is asked to extract.
    struct PhaseRecordingExtractor: ReceiptExtracting {
        /// The scanner being watched.
        let scanner: @MainActor () -> ReceiptScanPhase
        /// Where to record what was seen.
        let seen: Recorder

        func extract(
            from receipt: RecognizedReceipt, context: ReceiptScanContext
        ) async -> ReceiptScanResult {
            await seen.record(scanner())
            return ReceiptScanResult()
        }
    }

    /// Collects phases seen during a scan.
    @MainActor
    final class Recorder {
        /// The phases recorded, in order.
        private(set) var phases: [ReceiptScanPhase] = []

        /// Records one phase.
        /// - Parameter phase: The phase seen.
        func record(_ phase: ReceiptScanPhase) { phases.append(phase) }
    }

    /// A one-pixel image, which is all the fakes need.
    private var image: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
    }

    @Test("The on-device model's reading is what reaches the form")
    func modelLeads() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult(
                amountCents: 4_210, merchant: "Loblaws", source: .onDeviceModel
            )),
            fallback: FakeExtractor(result: ReceiptScanResult(
                amountCents: 9_999, merchant: "LOBLAWS #1234", source: .textHeuristics
            ))
        )

        let result = await scanner.scan(image)

        #expect(result.merchant == "Loblaws")
        #expect(result.amountCents == 4_210)
        #expect(result.source == .onDeviceModel)
    }

    @Test("A model that answers with nothing hands the page to the heuristics")
    func fallsBackWhenModelSaysNothing() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: FakeExtractor(result: ReceiptScanResult(
                amountCents: 4_210, merchant: "LOBLAWS", source: .textHeuristics
            ))
        )

        let result = await scanner.scan(image)

        #expect(result.amountCents == 4_210)
        #expect(result.source == .textHeuristics)
    }

    @Test("A field the model left blank is filled by the heuristics")
    func mergesPartialReadings() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult(
                merchant: "Loblaws", source: .onDeviceModel
            )),
            fallback: FakeExtractor(result: ReceiptScanResult(
                amountCents: 4_210, merchant: "LOBLAWS #1234", source: .textHeuristics
            ))
        )

        let result = await scanner.scan(image)

        #expect(result.merchant == "Loblaws")
        #expect(result.amountCents == 4_210)
        #expect(result.source == .onDeviceModel)
    }

    @Test("A photo nothing can be read from returns empty rather than failing")
    func unreadablePhotoIsEmpty() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(fails: true),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: FakeExtractor(result: ReceiptScanResult(amountCents: 4_210))
        )

        let result = await scanner.scan(image)

        #expect(result.isEmpty, "the heuristics are never asked about text that was never read")
    }

    @Test("A blank page is not put through the readers at all")
    func blankPageIsEmpty() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(receipt: RecognizedReceipt(lines: [])),
            primary: FakeExtractor(result: ReceiptScanResult(amountCents: 1)),
            fallback: FakeExtractor(result: ReceiptScanResult(amountCents: 2))
        )

        #expect(await scanner.scan(image).isEmpty)
    }

    @Test("The real heuristics read a plainly printed receipt")
    func heuristicsReadPlainText() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: HeuristicReceiptExtractor()
        )

        let result = await scanner.scan(image)

        #expect(result.merchant == "LOBLAWS")
        #expect(result.amountCents == 4_210)
        #expect(result.source == .textHeuristics)
    }

    // MARK: - Progress

    @Test("A scan starts idle and returns to idle")
    func returnsToIdle() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: HeuristicReceiptExtractor()
        )

        #expect(scanner.phase == .idle)
        _ = await scanner.scan(image)
        #expect(scanner.phase == .idle)
    }

    @Test("A photo nothing can be read from still returns to idle")
    func unreadablePhotoReturnsToIdle() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(fails: true),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: FakeExtractor(result: ReceiptScanResult())
        )

        _ = await scanner.scan(image)

        #expect(scanner.phase == .idle, "an early return must not leave the row spinning")
    }

    @Test("The reading step is reported while the readers are working")
    func reportsUnderstandingWhileExtracting() async {
        let recorder = Recorder()
        var scanner: ReceiptScanner?
        let watcher = PhaseRecordingExtractor(
            scanner: { scanner?.phase ?? .idle }, seen: recorder
        )
        scanner = ReceiptScanner(
            recognizer: FakeRecognizer(), primary: watcher, fallback: watcher
        )

        _ = await scanner?.scan(image)

        #expect(
            recorder.phases == [.understanding, .understanding],
            "both readers run inside the step the user is told about"
        )
    }

    // MARK: - Card details

    @Test("The card's details are read even when the model leads")
    func tenderIsReadAlongsideTheModel() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(receipt: RecognizedReceipt(lines: [
                RecognizedLine(text: "LOBLAWS", topFraction: 0.05),
                RecognizedLine(text: "TOTAL 42.10", topFraction: 0.8),
                RecognizedLine(text: "VISA ************4821", topFraction: 0.9)
            ])),
            primary: FakeExtractor(result: ReceiptScanResult(
                amountCents: 4_210, merchant: "Loblaws", source: .onDeviceModel
            )),
            fallback: FakeExtractor(result: ReceiptScanResult())
        )

        let result = await scanner.scan(image)

        #expect(result.tender?.last4 == "4821", "the model never sees or overrules this")
        #expect(result.tender?.network == .visa)
        #expect(result.source == .onDeviceModel)
    }

    @Test("A receipt with no card details carries no tender")
    func noTenderWhenNoneIsPrinted() async {
        let scanner = ReceiptScanner(
            recognizer: FakeRecognizer(),
            primary: FakeExtractor(result: ReceiptScanResult()),
            fallback: HeuristicReceiptExtractor()
        )

        let result = await scanner.scan(image)

        #expect(result.tender == nil)
    }

    // MARK: - Compression

    @Test("A large photo is reduced to the stored long edge")
    func reducesLargePhoto() {
        let large = UIGraphicsImageRenderer(size: CGSize(width: 4_032, height: 3_024)).image { _ in }

        let reduced = ReceiptScanner.compressed(large)

        #expect(max(reduced.size.width, reduced.size.height) == ReceiptCompression.longEdge)
        #expect(reduced.size.height == 1_200, "the aspect ratio is kept")
    }

    @Test("A small photo is left alone rather than scaled up")
    func leavesSmallPhotoAlone() {
        let small = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { _ in }

        #expect(ReceiptScanner.compressed(small).size == small.size)
    }

    @Test("A photo encodes to storable bytes")
    func encodesToBytes() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let data = try #require(ReceiptScanner.storableData(for: photo))

        #expect(!data.isEmpty)
    }
}
