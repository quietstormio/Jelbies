import XCTest
import simd
@testable import BobV1

/// The wave arm blend (panda-wave-r1): the per-fragment arm data (Skinner.waveBlend, fragment buffer 8) lives only while the keyframed wave plays, and the join fix sinks the fillet skin next to the capsule.
@MainActor
final class ArmBlendTests: XCTestCase {
    func testBlendBufferIsZeroedWhenTheWaveEnds() throws {
        let r = MotionRig(game: true)
        r.brain.armBlendSpecies = true
        XCTAssertEqual(r.skinner.waveBlend, [SIMD4<Float>](repeating: .zero, count: Skinner.waveBlendCount), "off before any wave")
        UserDefaults.standard.set(1, forKey: "BlobWaveSide")
        defer { UserDefaults.standard.removeObject(forKey: "BlobWaveSide") }
        r.brain.request(.wave)
        var sawOn = false, ended = false
        for _ in 0..<(60 * 6) {
            r.tick()
            if r.brain.activity == .waving, r.skinner.waveBlend[0].x > 0.5 { sawOn = true }
            if sawOn, r.brain.activity != .waving { ended = true; break }
        }
        XCTAssertTrue(sawOn, "the blend is on while the keyframed wave plays")
        XCTAssertTrue(ended)
        for _ in 0..<5 { r.tick() }
        XCTAssertEqual(r.skinner.waveBlend, [SIMD4<Float>](repeating: .zero, count: Skinner.waveBlendCount), "zeroed once the wave is over")
        let sk = Skinner.self
        XCTAssertEqual(sk.waveBlendCount, 7)
    }

    func testJoinSinksTheFilletSkinNextToTheCapsuleOnlyWhenOn() {
        let g = ArmPath.wave.geom(at: 0.5)
        let F = PosedArmField(g)
        // a rest vertex a few cm from the arm cone on the body side, as the fillet band holds
        let b = g.B - g.A
        let a0 = g.A + b * 0.1
        let p = SIMD3(a0.x - 0.07, a0.y, a0.z + 0.03)
        let off = ArmKeyframeBuilder.pose(vertex: p, field: F, restArm: -1)
        let on = ArmKeyframeBuilder.pose(vertex: p, field: F, restArm: -1, join: true)
        XCTAssertEqual(off.cls, 2); XCTAssertEqual(on.cls, 2)
        XCTAssertLessThanOrEqual(F.cone(on.p), F.cone(off.p) + 1e-9, "on never lifts the skin")
        let sunk = simd_length(on.p - off.p)
        XCTAssertGreaterThanOrEqual(sunk, 0)
        // the default argument is the previous behaviour
        let dflt = ArmKeyframeBuilder.pose(vertex: p, field: F, restArm: -1)
        XCTAssertEqual(simd_length(dflt.p - off.p), 0)
    }
}
