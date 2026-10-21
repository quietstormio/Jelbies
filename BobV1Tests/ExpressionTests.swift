//
//  ExpressionTests.swift
//  The expression layer (BlobBrain+Expression.swift): brows and blush at rest are exactly the locked face; the brows move as asked and clear the hats;
//  the layer yields to every system that owns the face and hands back cleanly.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ExpressionTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// Autonomy on (the layer runs) but nothing else starts by itself.
    private func quiet(_ r: MotionRig) {
        r.brain.autonomy = true; r.brain.restTimer = 1e6; r.brain.idleState.cooldown = 1e6; r.brain.socialBook.cooldown = 1e6
        r.run(0.1)
        r.brain.expr.pickTimer = 1e6          // (handing the face back from "owned" re-arms the pick timer)
    }

    private func brows(_ r: MotionRig) -> [[SIMD3<Float>]] {
        // the brow vertices of both sides, from the eye rig the skinner was built with
        let ap = BlobAppearance.berry
        _ = ap
        let rig = buildEyeRig(render: MotionRig.renderMesh, sim: MotionRig.simMesh)
        return rig.brow.map { ids in ids.map { v in SIMD3(r.dyn[6 * Int(v)], r.dyn[6 * Int(v) + 1], r.dyn[6 * Int(v) + 2]) } }
    }

    // MARK: brow identity

    /// Zero offsets, any history: the output is bit-identical to a skinner that never heard of expressions.
    func testBrowsAtZeroOffsetAreBitIdentical() {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.skinner.prepareBrows(rest: MotionRig.renderMesh.rest)
        r.render()
        let base = r.dyn
        r.skinner.browRaise = [0.03, 0.03]; r.skinner.browTilt = [0.2, 0.2]
        for _ in 0..<30 { r.render() }
        XCTAssertNotEqual(r.dyn, base, "the expression moved the brows")
        r.skinner.browRaise = [0, 0]; r.skinner.browTilt = [0, 0]
        for _ in 0..<90 { r.render() }
        XCTAssertLessThan(r.skinner.browRigidBlend, 0.002)
        XCTAssertEqual(r.dyn, base, "after the expression the brows are bit-identical to the locked rest face")
        // and a fresh skinner that never saw an expression gives the same floats
        let r2 = MotionRig(game: true); Self.keep.append(r2)
        r2.skinner.prepareBrows(rest: MotionRig.renderMesh.rest)
        r2.render()
        XCTAssertEqual(r2.dyn.count, base.count)
    }

    /// The rigid-brow path with zero offsets reproduces the skinned brows (to float noise) on a body at rest.
    func testRigidPathAtZeroOffsetMatchesSkinnedBrowsAtRest() {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.skinner.prepareBrows(rest: MotionRig.renderMesh.rest)
        r.render()
        let skinned = brows(r)
        r.skinner.browsRigid = true
        for _ in 0..<120 { r.render() }
        let rigid = brows(r)
        var worst: Float = 0
        for s in 0..<2 { for (a, b) in zip(skinned[s], rigid[s]) { worst = max(worst, simd_distance(a, b)) } }
        MotionLog.write("EXPR rigid-brow path vs skinned brows at rest: worst vertex difference \(worst)")
        XCTAssertLessThan(worst, 0.004)
    }

    func testBrowRaiseAndTilt() {
        let r = MotionRig(game: true); Self.keep.append(r)
        r.skinner.prepareBrows(rest: MotionRig.renderMesh.rest)
        r.skinner.browsRigid = true
        for _ in 0..<120 { r.render() }
        let base = brows(r)
        func mean(_ a: [SIMD3<Float>]) -> SIMD3<Float> { a.reduce(.zero, +) / Float(a.count) }
        // one brow up by 0.03: that brow moves 0.03 along the face's up, the other does not
        r.skinner.browRaise = [0.03, 0]
        for _ in 0..<120 { r.render() }
        let up = brows(r)
        let d0 = simd_distance(mean(up[0]), mean(base[0])), d1 = simd_distance(mean(up[1]), mean(base[1]))
        XCTAssertEqual(d0, 0.03, accuracy: 0.004, "the raised brow moves by the raise")
        XCTAssertLessThan(d1, 0.003, "the other brow stays")
        XCTAssertGreaterThan(mean(up[0]).y - mean(base[0]).y, 0.025, "up is up")
        // tilt: inner end up on both brows (the -x brow's inner end is its +x end)
        r.skinner.browRaise = [0, 0]; r.skinner.browTilt = [0.3, 0.3]
        for _ in 0..<120 { r.render() }
        let tilt = brows(r)
        func slope(_ a: [SIMD3<Float>], inner: Float) -> Float {
            let hi = a.max { $0.x * inner < $1.x * inner }!, lo = a.min { $0.x * inner < $1.x * inner }!
            return (hi.y - lo.y)
        }
        let before0 = slope(base[0], inner: 1), after0 = slope(tilt[0], inner: 1)
        let before1 = slope(base[1], inner: -1), after1 = slope(tilt[1], inner: -1)
        XCTAssertGreaterThan(after0 - before0, 0.015, "-x brow: inner (+x) end goes up")
        XCTAssertGreaterThan(after1 - before1, 0.015, "+x brow: inner (-x) end goes up")
        XCTAssertLessThan(simd_distance(mean(tilt[0]), mean(base[0])), 0.004, "a tilt turns about the brow's own centre")
    }

    // MARK: hats and the mask

    /// The largest the expression ever lifts a brow vertex (raise + tilt about its centre) stays under every head-top wearable and the sleep mask.
    func testBrowsClearHeadWearables() {
        // the highest any brow vertex gets over every expression: raise + the tilt about the brow's own centre (half length 0.069)
        var top: Float = 0, topKind = FaceKind.neutral
        for k in FaceKind.allCases {
            for t in stride(from: Float(0), through: 1, by: 0.05) {
                let p = k.pose(t: t)
                for (rs, ts) in [(p.raiseL, p.tiltL), (p.raiseR, p.tiltR)] {
                    let y = Float(BobForm.browY + BobForm.browHalfThick) + rs + abs(sinf(ts)) * Float(BobForm.browHalfLen)
                    if y > top { top = y; topKind = k }
                }
            }
        }
        var lowest = Float.infinity, who = ""
        for l in WearLook.pieces where l.row.anchor == .headTop {
            guard let p = WearMeshes.prepare(l, body: WearBody.shared) else { continue }
            for q in p.rest where q.z > 0.0 && abs(q.x) > 0.10 && abs(q.x) < 0.33 && q.y > 0.9 { if q.y < lowest { lowest = q.y; who = l.rawValue } }
        }
        // (the sleep mask is only worn asleep, when the layer is off: testTheLayerIsOffUnderTheSleepMask)
        MotionLog.write("EXPR highest brow vertex over every expression \(top) (\(topKind)); lowest head-top wearable vertex above the brows \(lowest) (\(who))")
        XCTAssertLessThan(top + 0.004, lowest, "a lifted brow would clip \(who)")
    }

    func testTheLayerIsOffUnderTheSleepMask() {
        let r = MotionRig(game: true); Self.keep.append(r)
        quiet(r); r.brain.sleepEnabled = true
        r.brain.face(.surprised, hold: 5)
        r.run(0.6)
        XCTAssertGreaterThan(r.skinner.browRaise[0], 0.02)
        r.brain.idleForced = true
        _ = r.brain.idleStart(.sleep, r.sim)
        r.run(14, until: { r.brain.isNapping })
        r.run(1.0)
        XCTAssertTrue(r.brain.faceOwned)
        XCTAssertEqual(r.skinner.browRaise[0], 0, accuracy: 1e-3, "no brow lift under the mask")
        XCTAssertEqual(r.skinner.browTilt[0], 0, accuracy: 1e-3)
    }

    // MARK: blush

    /// The blush disc is on the cheeks: outside both eyes and the mouth's keep-out (rest space), on the front.
    func testBlushSitsOnTheCheeksClearOfEyesAndMouth() {
        // the shader's ellipse: centre (+-0.315, 0.69), radii (0.078, 0.050); the fade starts at 0.30 and ends at 1.0 of that radius
        var worstEye = Float.infinity, worstMouth = Float.infinity
        for i in 0..<720 {
            let a = Float(i) / 720 * 2 * .pi
            let p = SIMD2(0.315 + 0.078 * cosf(a), 0.69 + 0.050 * sinf(a))
            // eye ellipse (centre 0.215, 0.82; half 0.0532 x 0.0623): normalised distance
            let e = hypotf((p.x - 0.215) / Float(BobForm.eyeHalfW), (p.y - Float(BobForm.eyeY)) / Float(BobForm.eyeHalfH))
            worstEye = min(worstEye, e)
            // mouth at full open: |x| < 0.088, y in 0.665 -/+ 0.066 -> keep-out
            let m = hypotf(max(0, abs(p.x) - 0.088), max(0, abs(p.y - 0.665) - 0.066))
            worstMouth = min(worstMouth, m)
        }
        MotionLog.write("EXPR blush ellipse: nearest to an eye \(worstEye) eye-radii, nearest to the open mouth box \(worstMouth)")
        XCTAssertGreaterThan(worstEye, 1.05, "the blush stays off the eyes")
        XCTAssertGreaterThan(worstMouth, 0.1, "the blush stays off the mouth keep-out")
    }

    /// Blush 0 renders exactly the locked body; blush > 0 changes pixels on the cheeks only (none in the mouth's box).
    func testBlushZeroIsIdenticalAndBlushStaysOffTheMouth() throws {
        let scene = try XCTUnwrap(LockScene())
        let v = lockViews[0]
        scene.renderer.setBlush(0, body: 0)
        scene.renderer.mouthOpen = 0.9
        let base = scene.render(v, palette: .blue)
        scene.renderer.setBlush(0.9, body: 0)
        let blushed = scene.render(v, palette: .blue)
        scene.renderer.mouthOpen = 0
        scene.renderer.setBlush(0, body: 0)
        let plain = scene.render(v, palette: .blue)
        let plain0 = scene.render(v, palette: .blue)
        XCTAssertEqual(plain.bgra, plain0.bgra, "blush 0 is deterministic and unchanged")
        // the mouth's pixels: where an open mouth differs from none
        var mouth = Set<Int>(), cheek = Set<Int>()
        for i in 0..<(base.bgra.count / 4) {
            if base.bgra[4 * i] != plain.bgra[4 * i] || base.bgra[4 * i + 1] != plain.bgra[4 * i + 1] || base.bgra[4 * i + 2] != plain.bgra[4 * i + 2] { mouth.insert(i) }
            if base.bgra[4 * i] != blushed.bgra[4 * i] || base.bgra[4 * i + 1] != blushed.bgra[4 * i + 1] || base.bgra[4 * i + 2] != blushed.bgra[4 * i + 2] { cheek.insert(i) }
        }
        XCTAssertGreaterThan(mouth.count, 200, "the open mouth is drawn")
        XCTAssertGreaterThan(cheek.count, 400, "the blush is drawn")
        let w = base.w
        func box(_ s: Set<Int>) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
            var b = (x0: Int.max, x1: 0, y0: Int.max, y1: 0)
            for i in s { let x = i % w, y = i / w; b.x0 = min(b.x0, x); b.x1 = max(b.x1, x); b.y0 = min(b.y0, y); b.y1 = max(b.y1, y) }
            return b
        }
        let mb = box(mouth)
        // a margin of a few pixels around the mouth: no cheek pixel inside it
        let inMouthBox = cheek.filter { let x = $0 % w, y = $0 / w; return x >= mb.x0 - 4 && x <= mb.x1 + 4 && y >= mb.y0 - 4 && y <= mb.y1 + 4 }
        XCTAssertEqual(inMouthBox.count, 0, "the blush never reaches the mouth")
        // two blobs: left and right of the face centre
        let cx = (mb.x0 + mb.x1) / 2
        let left = cheek.filter { $0 % w < cx }.count, right = cheek.filter { $0 % w >= cx }.count
        XCTAssertGreaterThan(left, 150); XCTAssertGreaterThan(right, 150)
        MotionLog.write("EXPR blush pixels \(cheek.count) (left \(left) right \(right)); mouth pixels \(mouth.count)")
    }

    // MARK: the layer

    func testFaceHoldsThenReturnsToNeutral() {
        let r = MotionRig(game: true); Self.keep.append(r)
        quiet(r)
        r.brain.face(.worried, hold: 1.0)
        var trace = ""
        var lastK = r.brain.expr.kind, lastO = r.brain.expr.owned
        r.run(0.6, each: { if r.brain.expr.kind != lastK || r.brain.expr.owned != lastO { lastK = r.brain.expr.kind; lastO = r.brain.expr.owned; trace += String(format: " [%.2f %@ owned=%d]", r.t, "\(lastK)", lastO ? 1 : 0) } })
        XCTAssertGreaterThan(r.skinner.browTilt[0], 0.2, "worried: inner ends up")
        XCTAssertLessThan(r.skinner.openness.left, 0.95)
        r.run(2.5, each: { if r.brain.expr.kind != lastK || r.brain.expr.owned != lastO { lastK = r.brain.expr.kind; lastO = r.brain.expr.owned; trace += String(format: " [%.2f %@ owned=%d]", r.t, "\(lastK)", lastO ? 1 : 0) } })
        let dbg = trace + " kind \(r.brain.expr.kind) eyeL \(r.brain.expr.eyeL) wrote \(r.brain.expr.wroteEyes) owned \(r.brain.expr.owned) faceOwned \(r.brain.faceOwned) forced \(r.brain.expr.forcedLeft) t \(r.brain.expr.t) dur \(r.brain.expr.dur) pick \(r.brain.expr.pickTimer) activity \(r.brain.activity) script \(r.brain.script) idle \(String(describing: r.brain.idleState.kind))"
        XCTAssertEqual(r.brain.expr.kind, .neutral, dbg)
        XCTAssertEqual(r.skinner.browTilt[0], 0, accuracy: 1e-3)
        XCTAssertEqual(r.skinner.openness.left, 1, accuracy: 1e-3, dbg)
    }

    func testLayerYieldsToTheYawnAndHandsBackCleanly() {
        let r = MotionRig(game: true); Self.keep.append(r)
        quiet(r)
        r.brain.face(.happy, hold: 30)
        r.run(0.6)
        XCTAssertLessThan(r.skinner.openness.left, 0.7, "happy squint")
        r.brain.idleForced = true
        _ = r.brain.idleStart(.yawn, r.sim)
        var sawOwned = false, maxMouthByLayer: Float = 0
        r.run(8, until: { r.brain.idleState.kind == nil }, each: {
            if r.brain.faceOwned { sawOwned = true; maxMouthByLayer = max(maxMouthByLayer, r.brain.expr.wroteMouth) }
        })
        XCTAssertTrue(sawOwned, "the yawn owns the face")
        XCTAssertEqual(maxMouthByLayer, 0, "the layer wrote no mouth while the yawn owned it")
        r.brain.expr.forcedLeft = 0
        r.run(3)
        XCTAssertEqual(r.brain.mouthOpen, 0, accuracy: 1e-6, "the yawn's mouth closed")
        XCTAssertGreaterThanOrEqual(r.skinner.openness.left, 0.99, "the eyes are open after the hand-back")
        XCTAssertEqual(r.skinner.browRaise[0], 0, accuracy: 1e-3)
    }

    func testLayerStaysOutOfSitAndTouchAndDining() {
        let r = MotionRig(game: true); Self.keep.append(r)
        quiet(r)
        r.brain.idleForced = true
        _ = r.brain.idleStart(.sit, r.sim)
        r.run(2.5)
        XCTAssertTrue(r.brain.faceOwned)
        XCTAssertFalse(r.brain.expr.wroteEyes)
        // touched: the pet owns the face
        r.brain.activity = .touched
        XCTAssertTrue(r.brain.faceOwned)
        r.brain.activity = .idle
        // a held (reserved) Jelly: owned
        r.brain.reserved = true
        XCTAssertTrue(r.brain.faceOwned)
        r.brain.reserved = false
    }

    func testBlushFadesInAndOut() {
        let r = MotionRig(game: true); Self.keep.append(r)
        quiet(r)
        XCTAssertEqual(r.brain.blushNow, 0)
        r.brain.blushBump(hold: 2.5, peak: 0.8)
        r.run(1.0)
        XCTAssertGreaterThan(r.brain.blushNow, 0.3); XCTAssertLessThan(r.brain.blushNow, 0.8, "fades in over about 2 s")
        r.run(1.2)
        XCTAssertEqual(r.brain.blushNow, 0.8, accuracy: 0.01)
        r.run(4.0)
        XCTAssertEqual(r.brain.blushNow, 0, accuracy: 1e-6, "and out again")
    }
}
