//
//  HoldWearTests.swift
//  hold-wear-r1. (1) Clothes and species features stay drawn and attached while he is held (upside down, sideways), mid flip trick (clean and faceplant) and mid
//  throw: every worn piece (hat, pearls, shoes) and the feature (Pip's tail spikes) is shown, its anchor stays within its upright offset + 0.5 cm of the body's own
//  frame (measured in the BODY frame, so it holds along the body's up, never world up) and nothing is drawn inside the mouth keep-out.
//  (2) After a drop or a throw he is upright and standing within 1.5 s of coming to rest, with the landing squash intact and the feet attached.
//
//  Phase 2 calibrates the numbers (they print as HOLDWEAR / HOLDGETUP lines): the 0.5 cm and 1.5 s limits are the brief's.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class HoldWearTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static let hat = WearLook.partyHat, neck = WearLook.pearls, shoes = WearLook.glitterShoes
    static let speciesIDs = [0, 1]                       // Bob (no feature) and Pip (the yellow tail + spikes)
    static let speciesNames = ["Bob", "Pip"]
    static let tol: Float = 0.005                        // the upright offset + 0.5 cm

    // MARK: scene

    /// One Jelly in the shared touch rig, wearing hat + pearls (+ shoes through the feet path), with its species feature.
    @MainActor final class Scene {
        let r = TouchPlayTests.Rig()
        let sets: [WornSet]
        let looks: [WearLook]
        let features = FeatureSet()
        let feature: JellyFeature
        var probe: TouchFeetTests.Probe?
        var clockS: Float = 0

        init(species: Int) {
            looks = [HoldWearTests.hat, HoldWearTests.neck]
            feature = JellyRoster.feature(species)
            let rig = r.rig
            rig.skinner.autoBlink = false
            rig.brain.feature = feature
            rig.skinner.configureTail(MotionRig.renderMesh); rig.skinner.tailOn = feature == .spines; rig.brain.skinnerRef = rig.skinner
            rig.brain.autonomy = false; rig.brain.expr.enabled = false
            rig.brain.shoesWorn = true
            WearBody.install(MotionRig.renderMesh); SkinField.prepare(MotionRig.renderMesh)
            sets = looks.map { _ in let s = WornSet(); s.body = WearBody.shared; s.soundOn = false; return s }
            HoldWearTests.keep.append(contentsOf: sets); HoldWearTests.keep.append(features)
            features.body = WearBody.shared
            for _ in 0..<70 { step(touched: false) }
        }

        func step(touched: Bool, _ extra: (() -> Void)? = nil) {
            r.step(touched: touched, extra)
            let rig = r.rig
            rig.skinner.jelly.tick(brain: rig.brain, sim: rig.sim, dt: rig.sim.stepDt)
            for (i, l) in looks.enumerated() { sets[i].tick(id: 0, brain: rig.brain, sim: rig.sim, outfit: [l.slot: l], role: .none, hideAll: false, dt: 1.0 / 60) }
            features.tick(id: 0, brain: rig.brain, sim: rig.sim, feature: feature, worn: looks.map { $0.art }, hideAll: false, dt: 1.0 / 60)
            clockS += 1.0 / 60
        }

        func skin() -> [Float] {
            var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
            r.rig.skinner.update(x: r.rig.sim.x, index: MotionRig.renderMesh.index, into: &d)
            return d
        }

        struct Sample {
            var drawn: [Bool] = [], offset: [Float] = []         // per worn look: drawn at all, and |mean body-frame vertex - mean rest vertex| (m)
            var mouth = 0                                         // worn vertices inside the mouth keep-out ellipse (front, body frame)
            var featDrawn = true, featMean = SIMD3<Float>.zero
            var feetLeft: Float = 0
        }

        func sample(_ tag: String) -> Sample {
            var out = Sample()
            let sk = skin()
            let zc = WearBody.shared.axisZ
            for (i, look) in looks.enumerated() {
                sets[i].syncCarry(0, sim: r.rig.sim)
                guard sets[i].shown(0, look.slot) != nil, let p = WearMeshes.prepare(look, body: WearBody.shared), let c = sets[i].slot(0)?.carry else { out.drawn.append(false); out.offset.append(9); continue }
                let f = sk.withUnsafeBufferPointer { q in sets[i].frame(theme: RoomTheme(), time: 0.4) { _ in q.baseAddress } }
                let verts = f.opaque.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) }
                guard verts.count >= p.rest.count, p.rest.count > 0 else { out.drawn.append(false); out.offset.append(9); continue }
                let sxz = 1 / c.squash.squareRoot()
                let Minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / c.squash, 1 / sxz)) * simd_float3x3(c.rotation).transpose
                var mb = SIMD3<Float>.zero, mr = SIMD3<Float>.zero
                for v in 0..<p.rest.count {
                    let b = Minv * (verts[v] - c.centroid) + c.restCentroid
                    mb += b; mr += p.rest[v]
                    if b.z - zc > 0 { let ex = b.x / 0.15, ey = (b.y - 0.651) / 0.10; if ex * ex + ey * ey < 1 { out.mouth += 1 } }
                }
                out.drawn.append(true)
                out.offset.append(simd_length((mb - mr) / Float(p.rest.count)))
            }
            // the feature: shown, and where its vertices sit in the body frame
            if feature != .none {
                let fm = sk.withUnsafeBufferPointer { q in features.frame(hidden: false) { _ in q.baseAddress } }
                if features.shown(0) == nil || fm.vertices.isEmpty { out.featDrawn = false }
                else if let c = features.slot(0)?.carry {
                    let sxz = 1 / c.squash.squareRoot()
                    let Minv = simd_float3x3(diagonal: SIMD3(1 / sxz, 1 / c.squash, 1 / sxz)) * simd_float3x3(c.rotation).transpose
                    var m = SIMD3<Float>.zero
                    for v in fm.vertices { m += Minv * (SIMD3(v.pos.x, v.pos.y, v.pos.z) - c.centroid) + c.restCentroid }
                    out.featMean = m / Float(fm.vertices.count)
                }
            }
            if var p = probe { p.measure(tag); out.feetLeft = p.maxLeft; probe = p }
            return out
        }
    }

    /// Row-major rotation about z by `a` rad (the grab's `rot`).
    static func rotZ(_ a: Float) -> [Float] { [cosf(a), -sinf(a), 0, sinf(a), cosf(a), 0, 0, 0, 1] }

    // MARK: item 1

    struct Track {
        var base: [Float] = [0, 0], baseFeat = SIMD3<Float>.zero, baseSet = false
        var worst: [String: [Float]] = [:], mouth: [String: Int] = [:], undrawn: [String: Int] = [:], feat: [String: Float] = [:], feet: [String: Float] = [:], n: [String: Int] = [:]
    }

    private func record(_ t: inout Track, _ s: Scene.Sample, _ phase: String) {
        t.n[phase, default: 0] += 1
        for (i, d) in s.drawn.enumerated() where !d { t.undrawn[phase + " " + (i == 0 ? "hat" : "neck"), default: 0] += 1 }
        if !s.featDrawn { t.undrawn[phase + " feature", default: 0] += 1 }
        var w = t.worst[phase] ?? [0, 0]
        for i in 0..<2 where s.drawn.indices.contains(i) && s.drawn[i] { w[i] = max(w[i], s.offset[i]) }
        t.worst[phase] = w
        t.mouth[phase, default: 0] += s.mouth
        if t.baseSet { t.feat[phase] = max(t.feat[phase] ?? 0, simd_length(s.featMean - t.baseFeat)) }
        t.feet[phase] = max(t.feet[phase] ?? 0, s.feetLeft)
    }

    func testWornPiecesAndFeaturesStayOnHeldFlippedAndThrown() {
        for id in Self.speciesIDs {
            let sc = Scene(species: id)
            sc.probe = TouchFeetTests.Probe(sc.r)
            var t = Track()
            // upright baseline: the normal offset of each piece while he stands (the squash and sway of the idle)
            for k in 0..<90 {
                sc.step(touched: false)
                if k % 3 == 0 { let s = sc.sample("upright"); if k == 0 { t.baseFeat = s.featMean; t.baseSet = true }; record(&t, s, "upright") }
            }
            t.base = t.worst["upright"] ?? [0, 0]
            // held, turned over and swung: upside down (180 deg) and sideways (90 deg)
            let sim = sc.r.rig.sim
            let hit = sim.centroid() + SIMD3(0, 0.1, 0.5)
            sim.beginGrab(hit: hit, radius: 0.4)
            for (phase, angle) in [("held sideways", Float.pi / 2), ("held upside down", Float.pi)] {
                for k in 0..<150 {
                    let e = min(1, Float(k) / 70), a = angle * e * e * (3 - 2 * e)
                    sc.step(touched: true) {
                        sim.moveGrab(target: hit + SIMD3(0, 0.6 * e, 0), rot: Self.rotZ(a))
                        sc.r.play.heldFrame(dt: 1.0 / 60, now: sc.r.clock, grabbing: true, liftHeight: 0.6 * e, sim: sim, brain: sc.r.rig.brain, skinner: sc.r.rig.skinner)
                    }
                    if k % 3 == 0 { record(&t, sc.sample(phase), phase) }
                }
            }
            sim.endGrab()
            for _ in 0..<240 { sc.step(touched: true) { sc.r.play.heldFrame(dt: 1.0 / 60, now: sc.r.clock, grabbing: false, liftHeight: 0, sim: sim, brain: sc.r.rig.brain, skinner: sc.r.rig.skinner) } }
            for _ in 0..<120 { sc.step(touched: false) }
            // the flip trick (clean, then the faceplant), sampled while the script runs
            for (phase, fail) in [("flip", false), ("faceplant", true)] {
                sc.r.rig.brain.startFlip(sim: sim, compact: false, fail: fail)
                var k = 0
                while sc.r.rig.brain.isFlipping && k < 60 * 6 {
                    sc.step(touched: false)
                    if k % 3 == 0 { record(&t, sc.sample(phase), phase) }
                    k += 1
                }
                for _ in 0..<180 { sc.step(touched: false) }
            }
            // a throw: bounces, tumbles, then gets up
            sc.step(touched: true); sc.step(touched: true)
            sim.launch(velocity: SIMD3(0.6, 2.8, 0.2), spin: SIMD3(0, 0, -2.5))
            sc.r.play.thrown = true
            for k in 0..<(60 * 4) {
                let hold = sc.r.play.getUpFrame(dt: 1.0 / 60, now: sc.r.clock, held: false, focusSpot: GameCamera.callSpot, sim: sim, brain: sc.r.rig.brain)
                sc.step(touched: hold || k < 18)
                if k % 3 == 0 { record(&t, sc.sample("thrown"), "thrown") }
            }
            let name = Self.speciesNames[id]
            for phase in ["upright", "held sideways", "held upside down", "flip", "faceplant", "thrown"] {
                let w = t.worst[phase] ?? [9, 9]
                print("HOLDWEAR \(name) \(phase): n \(t.n[phase] ?? 0) hat offset \(w[0]) neck offset \(w[1]) (upright \(t.base)) mouth \(t.mouth[phase] ?? 0) undrawn \(t.undrawn.filter { $0.key.hasPrefix(phase) }) feature drift \(t.feat[phase] ?? 0) feet left \(t.feet[phase] ?? 0)")
                XCTAssertGreaterThan(t.n[phase] ?? 0, 3, "\(name) \(phase): sampled")
                XCTAssertTrue(t.undrawn.filter { $0.key.hasPrefix(phase) }.isEmpty, "\(name) \(phase): every worn piece and the feature stays drawn")
                XCTAssertLessThanOrEqual(w[0], t.base[0] + Self.tol, "\(name) \(phase): the hat stays on his head (body frame)")
                XCTAssertLessThanOrEqual(w[1], t.base[1] + Self.tol, "\(name) \(phase): the pearls stay round his middle (body frame)")
                XCTAssertEqual(t.mouth[phase] ?? 0, 0, "\(name) \(phase): nothing in the mouth keep-out")
                XCTAssertLessThanOrEqual(t.feet[phase] ?? 0, 0.12 * MotionRig.H, "\(name) \(phase): the shoes stay at the feet")
                if id == 1 { XCTAssertLessThan(t.feat[phase] ?? 0, 0.05, "\(name) \(phase): the tail spikes ride the body") }
            }
        }
    }

    /// The tipped-body rule is one predicate and says no for every piece and feature.
    func testNothingHidesForBodyOrientation() {
        for l in WearLook.allCases { XCTAssertFalse(WornSet.hidesWhileTipped(l), "\(l)") }
        for f in [JellyFeature.none, .spines, .wings, .daisy, .ears] { XCTAssertFalse(WornSet.hidesWhileTipped(f), "\(f)") }
    }

    // MARK: item 2

    struct DropCase { var height: Float, rot: Float, throwIt: Bool, hard: Bool }

    static func cases() -> [DropCase] {
        var s: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 33) & 0xFFFF) / 65535 }
        let rots: [Float] = [0, .pi / 2, .pi]
        return (0..<20).map { k in DropCase(height: 0.3 + 1.7 * rnd(), rot: rots[k % 3], throwIt: k % 2 == 1, hard: (k / 2) % 2 == 1) }
    }

    /// Landing squash baselines per case index from the UNMODIFIED code (phase 2 fills them in from the printed HOLDGETUP lines); nil = print only.
    static let baseSquash: [Int: Float] = [:]

    func testDropsAndThrowsAreBackOnTheirFeetWithin1_5Seconds() {
        var worstAll: Float = 0
        for (k, c) in Self.cases().enumerated() {
            let r = TouchPlayTests.Rig()
            let sim = r.rig.sim, brain = r.rig.brain, play = r.play
            var probe: TouchFeetTests.Probe? = k % 4 == 0 ? TouchFeetTests.Probe(r) : nil
            func feet(_ tag: String) { if var p = probe { p.measure(tag); probe = p } }
            r.step(touched: true); r.step(touched: true)
            let restH = sim.bounds().hi.y - sim.bounds().lo.y
            let hit = sim.centroid() + SIMD3(0, 0.1, 0.5)
            sim.beginGrab(hit: hit, radius: 0.4)
            for f in 0..<90 {
                let e = min(1, Float(f) / 45), s = e * e * (3 - 2 * e)
                r.step(touched: true) {
                    sim.moveGrab(target: hit + SIMD3(0, c.height * s, 0), rot: Self.rotZ(c.rot * s))
                    play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: c.height * s, sim: sim, brain: brain, skinner: r.rig.skinner)
                }
                if f % 5 == 0 { feet("held") }
            }
            // release: a drop (hard = pushed down) or a throw (gentle / hard flick), exactly as MelonStage.releaseGrab
            sim.endGrab()
            if c.throwIt {
                sim.launch(velocity: SIMD3(c.hard ? 0.8 : 0.4, c.hard ? 4.2 : 2.6, 0.2), spin: SIMD3(0, 0, -2.5))
                play.thrown = true
            } else if c.hard { sim.launch(velocity: SIMD3(0, -3, 0), spin: .zero) }
            var t: Float = 0, firstImpact: Float?, restAt: Float?, restRun = 0, standAt: Float?, minH = restH
            let impacts0 = play.impacts
            for f in 0..<(60 * 10) {
                let hold = play.getUpFrame(dt: 1.0 / 60, now: r.clock, held: false, focusSpot: nil, sim: sim, brain: brain)
                r.step(touched: hold || (c.throwIt && t < 0.3)) {
                    play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: false, liftHeight: 0, sim: sim, brain: brain, skinner: r.rig.skinner)
                }
                t += 1.0 / 60
                if play.impacts > impacts0, firstImpact == nil { firstImpact = t }
                if firstImpact != nil { let b = sim.bounds(); minH = min(minH, b.hi.y - b.lo.y) }
                if f % 5 == 0 { feet(c.throwIt ? "thrown" : "dropped") }
                let still = firstImpact != nil && simd_length(sim.meanVelocity()) < 0.25 && sim.minY() < 0.06
                restRun = still ? restRun + 1 : 0
                if restAt == nil, restRun >= 9 { restAt = t - 8.0 / 60 }
                let pose = sim.bodyPose(iterations: 6)
                if restAt != nil, standAt == nil, pose.tilt < 0.4, brain.activity == .idle, play.getUpPhase == .off { standAt = t }
                if standAt != nil { break }
            }
            let squash = 1 - minH / restH
            let dt = (standAt ?? 99) - (restAt ?? 0)
            worstAll = max(worstAll, dt)
            print("HOLDGETUP case \(k) height \(c.height) rot \(c.rot) \(c.throwIt ? "throw" : "drop") \(c.hard ? "hard" : "gentle"): impact at \(firstImpact ?? -1) rest at \(restAt ?? -1) standing at \(standAt ?? -1) rest->standing \(dt) s, landing squash \(squash)")
            XCTAssertNotNil(firstImpact, "case \(k): he lands")
            XCTAssertNotNil(restAt, "case \(k): he comes to rest")
            XCTAssertNotNil(standAt, "case \(k): he stands up")
            XCTAssertLessThanOrEqual(dt, 1.5, "case \(k): back on his feet within 1.5 s of coming to rest")
            XCTAssertGreaterThan(squash, 0.02, "case \(k): the landing squash is still there")
            if let b = Self.baseSquash[k] { XCTAssertEqual(squash, b, accuracy: 0.10 * b, "case \(k): landing squash within 10% of the unmodified code's") }
            if let p = probe { XCTAssertLessThanOrEqual(p.maxLeft, 0.12 * MotionRig.H, "case \(k): feet attached while held and thrown / dropped (worst at \(p.worst))") }
        }
        print("HOLDGETUP worst rest->standing \(worstAll) s")
    }
}
