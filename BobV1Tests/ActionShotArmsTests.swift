import XCTest
import simd
@testable import BobV1

/// The Show lobby's podium picture (and every lobby picture drawn by MelonStage.renderSnapshot with a body pose) shows the arms AT REST, whatever the live Jelmiko is doing when it is taken.
/// 2026-11-17 (the owner: "Why are his arms like this"): the snapshot skinned the live body with the live arm state (walking / wave / social capsules, wave and touch skin offsets), so a Jelmiko
/// caught mid-wave or holding an arm up was photographed with one arm raised and squashed into his cheek. `Skinner.withRestArms` is the scope the snapshot skins in.
/// The picture's arm region is the arm capsules: these tests compare those vertices as skinned inside the scope with a body that never moved its arms, from the same particles, for every
/// species id (the species differ only in features that do not touch the arms), and check that the live state is put back untouched.
@MainActor
final class ActionShotArmsTests: XCTestCase {
    private static let species = Array(JellyRoster.baseNames.indices)

    /// The vertices the arms own: both arm capsules.
    private func armVertices(_ r: MotionRig) -> [Int] {
        var out: [Int] = []
        for f in r.brain.armFirstIdx { out += Array(f..<(f + ArmCapsule.vertexCount)) }
        return out
    }
    private func maxDist(_ a: [Float], _ b: [Float], _ ids: [Int]) -> Float {
        var worst: Float = 0
        for v in ids { let o = 6 * v; worst = max(worst, simd_length(SIMD3(a[o], a[o + 1], a[o + 2]) - SIMD3(b[o], b[o + 1], b[o + 2]))) }
        return worst
    }
    /// The same particles on a body that never lifted an arm (the neutral reference).
    private func reference(for r: MotionRig) -> [Float] {
        let n = MotionRig(game: true)
        n.run(0.2)
        var d = [Float](repeating: 0, count: n.dyn.count)
        n.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    private enum Leak: CaseIterable { case wave, armUp, soapHold }

    /// A rig whose arms are in a non-neutral state, as it was left (the room is paused behind the lobby).
    private func leaking(_ kind: Leak, species id: Int) -> MotionRig {
        let r = MotionRig(game: true)
        r.brain.armBlendSpecies = true
        switch kind {
        case .wave:
            UserDefaults.standard.set(id % 2 == 0 ? 1 : -1, forKey: "BlobWaveSide")
            r.brain.request(.wave)
            for _ in 0..<(60 * 6) { r.tick(); r.render(); if r.brain.activity == .waving, r.skinner.waveBlend[0].x > 0.5, r.skinner.waveBlend[0].w > 0.99 { break } }
            UserDefaults.standard.removeObject(forKey: "BlobWaveSide")
        case .armUp:          // one arm raised to the cheek, one low
            _ = r.brain.poseArmsForSnapshot(SnapshotArmPose(el: [1.15, 0.15], sa: [0.1, 0.45], out: 0.06, yaw: 0, leanDeg: 0, title: "t"), sim: r.sim, skinner: r.skinner)
            r.render()
        case .soapHold:       // a hand-held pose of the same capsule path (a bar of soap held out)
            _ = r.brain.poseArmsForSnapshot(SnapshotArmPose(el: [0.9, 0.2], sa: [0.3, 0.1], out: 0.04, yaw: 0, leanDeg: 0, title: "t"), sim: r.sim, skinner: r.skinner)
            r.render()
        }
        return r
    }

    func testPodiumArmsAreAtRestWhateverTheLiveArmsDo() {
        for id in Self.species {
            for kind in Leak.allCases {
                let r = leaking(kind, species: id)
                let ids = armVertices(r)
                XCTAssertEqual(ids.count, 2 * ArmCapsule.vertexCount)
                let ref = reference(for: r)
                var leaked = [Float](repeating: 0, count: r.dyn.count)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &leaked)
                var scoped = [Float](repeating: 0, count: r.dyn.count)
                r.skinner.withRestArms { r.skinner.withNeutralFace { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &scoped) } }
                let before = maxDist(leaked, ref, ids), after = maxDist(scoped, ref, ids)
                XCTAssertGreaterThan(before, 0.02, "species \(id) \(kind): the live state really does move the arms (else this test proves nothing)")
                XCTAssertLessThan(after, 0.002, "species \(id) \(kind): the picture's arms equal the neutral ones (off by \(after))")
                // left / right arm silhouettes: each arm's height equals the neutral arm's (so the two mirror each other as they do at rest)
                func height(_ d: [Float], _ side: Int) -> Float {
                    let f = r.brain.armFirstIdx[side]; var lo = Float.infinity, hi = -Float.infinity
                    for v in f..<(f + ArmCapsule.vertexCount) { lo = min(lo, d[6 * v + 1]); hi = max(hi, d[6 * v + 1]) }
                    return hi - lo
                }
                XCTAssertEqual(height(scoped, 0), height(ref, 0), accuracy: 0.003, "species \(id) \(kind): left arm height")
                XCTAssertEqual(height(scoped, 1), height(ref, 1), accuracy: 0.003, "species \(id) \(kind): right arm height")
                // the live arm state is put back exactly
                var again = [Float](repeating: 0, count: r.dyn.count)
                r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &again)
                XCTAssertLessThan(maxDist(again, leaked, ids), 1e-5, "species \(id) \(kind): the live arms come back after the picture")
            }
        }
    }

    /// Every wear change bumps `store.revision`, which is in the picture cache's key and in the action shot's `.task(id:)`: the podium picture is drawn again right after Dress up / take off,
    /// and after `wear` moves a copy from another Jelmiko.
    func testEveryWearChangeInvalidatesThePictureKey() {
        let d = UserDefaults(suiteName: "preview.always.\(UUID())")!
        let store = StoreBook(wallet: DropsWallet(persists: false), persists: false, defaults: d)
        let shoes = WearLook.looks(.feet).first!, hat = WearLook.looks(.head).first!
        store.grant(StoreCatalog.item(wearing: shoes)?.id ?? ""); store.grant(StoreCatalog.item(wearing: hat)?.id ?? "")
        var rev = store.revision
        func bumped(_ what: String, _ f: () -> Void) { f(); XCTAssertGreaterThan(store.revision, rev, what); rev = store.revision }
        bumped("shoes on") { XCTAssertTrue(store.wear(shoes, on: 0)) }
        bumped("hat on") { XCTAssertTrue(store.wear(hat, on: 0)) }
        bumped("the one copy of the shoes moves to another Jelmiko") { _ = store.wear(shoes, on: 1) }
        XCTAssertEqual(store.worn(1, .feet), shoes)
        bumped("shoes off") { store.takeOff(.feet, from: 1) }
        XCTAssertNil(store.worn(1, .feet))
    }

    // MARK: the whole body: a clean front-facing stand whatever the live sim is doing

    private enum Live: CaseIterable { case lyingAsleep, leaningEating, midStep, held }

    /// A rig whose body is in a non-neutral state: tipped onto its back (asleep), leaning and turned (eating), walking (a foot up, feet beans out), or lifted and tilted (held).
    private func liveBody(_ kind: Live) -> MotionRig {
        let r = MotionRig(game: true)
        r.brain.armBlendSpecies = true
        func turn(_ q: simd_quatf, lift: Float) {
            let c = r.sim.bodyPose(iterations: 3).centroid
            for i in 0..<r.sim.n {
                let p = SIMD3<Float>(r.sim.x[3 * i], r.sim.x[3 * i + 1], r.sim.x[3 * i + 2])
                let o = c + q.act(p - c) + SIMD3<Float>(0, lift, 0)
                r.sim.x[3 * i] = o.x; r.sim.x[3 * i + 1] = o.y; r.sim.x[3 * i + 2] = o.z
            }
            r.sim.invalidatePose()
        }
        switch kind {
        case .lyingAsleep: turn(simd_quatf(angle: -Float.pi / 2, axis: SIMD3(1, 0, 0)), lift: 0)
        case .leaningEating: turn(simd_quatf(angle: 0.5, axis: simd_normalize(SIMD3<Float>(0.3, 0, 1))) * simd_quatf(angle: 1.1, axis: SIMD3(0, 1, 0)), lift: 0)
        case .midStep:
            let p = r.sim.bodyPose(iterations: 3).centroid
            r.brain.script = .walk(target: SIMD2(p.x - 2, p.z + 0.4), then: .none); r.brain.activity = .walking; r.brain.scriptT = 0
            r.run(0.9)
        case .held: turn(simd_quatf(angle: 0.35, axis: SIMD3(0, 0, 1)), lift: 0.5)
        }
        r.render()
        return r
    }

    private func bodyExtent(_ d: [Float], upTo n: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        for v in 0..<n { let p = SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]); lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }

    /// The picture's skin, from the rest stand the stage builds (RestStand + withRestArms + withNeutralFace), equals the skin of a body that never moved: arms, feet and the body's extent.
    func testThePictureIsACleanStandWhateverTheLiveBodyDoes() {
        for kind in Live.allCases {
            for id in Self.species {
                let r = liveBody(kind)
                let n = MotionRig(game: true)
                n.run(0.2)
                let c0 = r.sim.bodyPose(iterations: 3).centroid
                let xz = SIMD2<Float>(c0.x, c0.z)
                let liveX = r.sim.x
                let restore = RestStand.enter(sim: r.sim, skinner: r.skinner, xz: xz)
                var pic = [Float](repeating: 0, count: r.dyn.count)
                r.skinner.withRestArms { r.skinner.withNeutralFace { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &pic) } }
                // the same pose through the same scope on a body that never moved (the reference stand)
                let restoreN = RestStand.enter(sim: n.sim, skinner: n.skinner, xz: xz)
                var ref = [Float](repeating: 0, count: n.dyn.count)
                n.skinner.withRestArms { n.skinner.withNeutralFace { n.skinner.update(x: n.sim.x, index: MotionRig.renderMesh.index, into: &ref) } }
                restoreN()
                var ids = armVertices(r)
                for f in r.brain.beanFirstIdx { ids += Array(f..<(f + FootBean.vertexCount)) }
                let off = maxDist(pic, ref, ids)
                XCTAssertLessThan(off, 0.003, "species \(id) \(kind): the arms and feet of the picture are the neutral ones (off by \(off))")
                let a = bodyExtent(pic, upTo: r.brain.armFirstIdx[0]), b = bodyExtent(ref, upTo: n.brain.armFirstIdx[0])
                XCTAssertLessThan(simd_length(a.0 - b.0) + simd_length(a.1 - b.1), 0.006, "species \(id) \(kind): the body stands where and how the rest stand does")
                restore()
                XCTAssertEqual(r.sim.x, liveX, "species \(id) \(kind): the live particles come back exactly")
            }
        }
    }

    /// A Park friend drawn on a borrowed body keeps his species signature (the key carries it, so a yellow friend's spikes and a lavender friend's wings are drawn and cached apart from a plain one).
    func testBorrowedPictureKeyCarriesTheSignature() {
        let plain = HeadPortraitKey(jelly: 0, colour: .yellow, wear: nil)
        let spiky = HeadPortraitKey(jelly: 0, colour: .yellow, wear: nil, feature: .spines)
        let winged = HeadPortraitKey(jelly: 0, colour: .lavender, wear: nil, feature: .wings)
        XCTAssertNotEqual(plain, spiky)
        XCTAssertNotEqual(spiky, winged)
        XCTAssertTrue(spiky.borrowed)
        XCTAssertEqual(spiky.feature, .spines)
    }

    func testRestHandFramesIgnoreTheLiveArm() {
        let r = leaking(.armUp, species: 1)
        let rest = GameCare.armFrames(brain: r.brain, sim: r.sim, rest: true)
        let n = MotionRig(game: true)
        n.run(0.2)
        let neutral = GameCare.armFrames(brain: n.brain, sim: r.sim, rest: true)
        for s in 0..<2 {
            XCTAssertEqual(rest[s].out, 0, accuracy: 1e-5, "side \(s): the hand band sits on the rest nub")
            XCTAssertLessThan(simd_length(rest[s].b - neutral[s].b), 1e-4, "side \(s): the same rest arm as a body that never moved it")
        }
    }
}
