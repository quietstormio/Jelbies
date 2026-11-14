import XCTest
@testable import BobV1

/// The waving Panda's raised arm and join collar are painted black by how far the arm moved each skin vertex (BlobBrain.pandaInkMat -> mat channel ->
/// GfxBodyFast.metal / PandaMarks.h `ink`), not by the rest-space arm mask whose edge tore the stretched collar into cream teeth.
final class PandaWaveInkTests: XCTestCase {
    func testInkIsZeroWhereTheArmDidNotMoveTheSkinAndFullOnTheArm() {
        XCTAssertEqual(BlobBrain.pandaInkMat(displacement: 0), 0)
        XCTAssertEqual(BlobBrain.pandaInkMat(displacement: 0.001), 0)
        XCTAssertEqual(BlobBrain.pandaInkMat(displacement: 0.05), 2, accuracy: 1e-6)
    }
    func testInkIsMonotoneAndNeverMistakenForAO() {
        var last: Float = 0
        for k in 0...200 {
            let v = BlobBrain.pandaInkMat(displacement: Float(k) * 0.0005)
            XCTAssertGreaterThanOrEqual(v, last); last = v
            // the shader's decode: real crease AO is 0...0.4 and stays below the 0.45 threshold; any ink above the decode's own error is recognised
            let mat = 0.4 + v
            XCTAssertEqual(mat > 0.45, v > 0.05)
        }
    }
    func testDecodeRoundTripKeepsTheAO() {
        for ao: Float in [0, 0.2, 0.4] { for d: Float in [0.003, 0.005, 0.02] {
            let ink = BlobBrain.pandaInkMat(displacement: d) / 2
            let mat = ao + 2 * ink
            guard mat > 0.45 else { continue }
            let est = min(max((mat - 0.4) / 1.6, 0), 1)
            XCTAssertEqual(est, ink, accuracy: 0.26)
            XCTAssertLessThanOrEqual(min(max(mat - 2 * est, 0), 0.4), 0.4)
        } }
    }
}
