import Foundation
import Testing
@testable import Domain

/// The steps a running receipt scan reports (§9.7).
///
/// The progress row is determinate, so these values are what the user actually sees move.
@Suite("Receipt scan phases")
struct ReceiptScanPhaseTests {

    @Test("Idle is not a scanning state")
    func idleIsNotScanning() {
        #expect(!ReceiptScanPhase.idle.isScanning)
        #expect(ReceiptScanPhase.idle.step == nil)
        #expect(ReceiptScanPhase.idle.message.isEmpty)
    }

    @Test("Every working phase reports itself as scanning", arguments: ReceiptScanPhase.working)
    func workingPhasesAreScanning(phase: ReceiptScanPhase) {
        #expect(phase.isScanning)
        #expect(!phase.message.isEmpty, "a step with no message would show an empty row")
    }

    @Test("Idle is the only phase that is not a working step")
    func workingExcludesOnlyIdle() {
        let working = Set(ReceiptScanPhase.working)
        let all = Set(ReceiptScanPhase.allCases)

        #expect(all.subtracting(working) == [.idle])
    }

    @Test("The steps are numbered from one, in order", arguments: [
        (ReceiptScanPhase.reading, 1),
        (ReceiptScanPhase.understanding, 2),
        (ReceiptScanPhase.matching, 3)
    ])
    func stepsAreNumberedInOrder(phase: ReceiptScanPhase, step: Int) {
        #expect(phase.step == step)
    }

    @Test("Progress rises with each step and never reaches one before the end")
    func progressRises() {
        let values = ReceiptScanPhase.working.map(\.progress)

        #expect(values == values.sorted(), "the bar must never run backwards")
        #expect(ReceiptScanPhase.reading.progress == 0)
        let last = values.last ?? 1
        #expect(last < 1, "a full bar while still working would read as finished")
    }
}
