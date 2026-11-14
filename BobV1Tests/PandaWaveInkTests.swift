import XCTest
@testable import BobV1

/// The waving Panda's raised arm and join collar are painted black by how far the arm moved each skin vertex (BlobBrain.pandaInkWeight -> pandaInkMat -> mat channel ->
/// PandaMarks.h pandaInkOfMat / pandaAOOfMat -> pandaPaint `ink`), not by the rest-space arm mask whose edge tore the stretched collar into cream teeth.
final class PandaWaveInkTests: XCTestCase {
    func testWeightIsZeroWhereTheArmDidNotMoveTheSkinAndSolidOnTheArm() {
        XCTAssertEqual(BlobBrain.pandaInkWeight(displacement: 0, covered: false), 0)
        XCTAssertEqual(BlobBrain.pandaInkWeight(displacement: 0.0005, covered: false), 0)
        XCTAssertEqual(BlobBrain.pandaInkWeight(displacement: 0.03, covered: false), 1, accuracy: 1e-6)
        XCTAssertEqual(BlobBrain.pandaInkWeight(displacement: 0, covered: true), 1)          // under the capsule: always black
    }
    func testWeightIsMonotone() {
        var last: Float = 0
        for k in 0...200 { let v = BlobBrain.pandaInkWeight(displacement: Float(k) * 0.0002, covered: false); XCTAssertGreaterThanOrEqual(v, last); last = v }
    }
    /// The mat value is NEGATIVE once there is ink (the locked fsSoftMatte then reads occ = clamp(mat / 0.4, 0, 1) = 0: never a fully occluded arm); no ink leaves the AO untouched.
    func testMatEncodingNeverReadsAsOcclusionInTheLockedShader() {
        for ao: Float in [0, 0.1, 0.2, 0.4] {
            XCTAssertEqual(BlobBrain.pandaInkMat(ao: ao, ink: 0), ao)
            XCTAssertEqual(BlobBrain.pandaInkMat(ao: ao, ink: 0.05), ao)          // below the shader's use: untouched
            for ink: Float in [0.15, 0.5, 1] {
                let mat = BlobBrain.pandaInkMat(ao: ao, ink: ink)
                XCTAssertLessThan(mat, 0)
                XCTAssertEqual(min(max(mat / 0.4, 0), 1), 0)
                // the shader's decode (PandaMarks.h): ink = -mat / 4 clamp, AO = clamp(mat + 4 ink, 0, 0.4)
                let est = min(max(-mat * 0.25, 0), 1)
                XCTAssertEqual(est, ink - ao / 4, accuracy: 1e-5)          // mat = ao - 4 ink, so -mat / 4 = ink - ao / 4 (the decode's own error is at most 0.1: below the 0.25...0.75 soft threshold's reach)
            }
        }
    }
}
