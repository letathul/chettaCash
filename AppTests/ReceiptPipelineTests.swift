import Foundation
import Testing
import UIKit
import FoundationModels
@testable import Features
import Domain

/// The receipt pipeline against the real frameworks (§9.7).
///
/// Hosted by the app rather than run in the fast SPM suite, because both Vision and
/// FoundationModels need a real bundle: `bundleProxyForCurrentProcess is nil` is what
/// a hostless test bundle gets instead (finding E2).
///
/// These tests assert the **pipeline's output**, never that a particular reader
/// produced it. That is deliberate. In the Simulator `SystemLanguageModel` reports
/// itself `.available` and then throws on generation — the generative assets are not
/// installed — so a test that demanded the model's answer would fail on exactly the
/// machine this is developed on, while the shipped behaviour is correct.
@Suite("Receipt pipeline, on-device")
@MainActor
struct ReceiptPipelineTests {

    /// A moment after the fixture's printed date, so the date is plausible.
    private var now: Date {
        Date(timeIntervalSince1970: 1_789_000_000)
    }

    @Test("The on-device model's availability can be read")
    func availabilityIsReadable() {
        // Whatever it says is correct for this machine; what matters is that asking
        // is safe and that the answer is one the app knows how to handle.
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            #expect(FoundationModelsReceiptExtractor().isAvailable)
        case .unavailable(let reason):
            #expect(
                [.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady]
                    .contains(reason)
            )
            #expect(FoundationModelsReceiptExtractor().isAvailable == false)
        }
    }

    @Test("Vision reads the printed lines off a receipt image")
    func visionReadsTheImage() async throws {
        let receipt = try await VisionReceiptRecognizer().recognize(ReceiptFixture.image())

        #expect(!receipt.isEmpty)
        #expect(receipt.transcript.contains(ReceiptFixture.merchant))
        #expect(receipt.transcript.contains("22.54"))

        let top = try #require(receipt.lines.min { $0.topFraction < $1.topFraction })
        #expect(
            top.text.contains(ReceiptFixture.merchant),
            "the merchant must come back as the topmost line, which is how it is found"
        )
    }

    @Test("The whole pipeline reads merchant, total and date off a photo")
    func pipelineReadsReceipt() async throws {
        let result = await ReceiptScanner().scan(ReceiptFixture.image(), context: ReceiptScanContext(now: now))

        #expect(result.amountCents == ReceiptFixture.totalCents, "the total, not the subtotal")
        #expect(result.merchant?.contains(ReceiptFixture.merchant) == true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = try #require(result.date)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 9)
    }

    @Test("With the model out of the picture the heuristics still read the photo")
    func heuristicsAloneReadReceipt() async throws {
        let scanner = ReceiptScanner(
            primary: UnavailableExtractor(), fallback: HeuristicReceiptExtractor()
        )

        let result = await scanner.scan(ReceiptFixture.image(), context: ReceiptScanContext(now: now))

        #expect(result.amountCents == ReceiptFixture.totalCents)
        #expect(result.merchant?.contains(ReceiptFixture.merchant) == true)
        #expect(result.source == ReceiptScanSource.textHeuristics)
    }

    /// Stands in for a model that cannot answer — an ineligible device, Apple
    /// Intelligence switched off, or a generation that threw.
    struct UnavailableExtractor: ReceiptExtracting {
        /// Answers nothing, so the pipeline falls through to the next reader.
        /// - Parameters:
        ///   - receipt: The recognised text, ignored.
        ///   - context: The scan's context, ignored.
        /// - Returns: An empty result.
        func extract(
            from receipt: RecognizedReceipt,
            context: ReceiptScanContext
        ) async -> ReceiptScanResult {
            ReceiptScanResult()
        }
    }
}
