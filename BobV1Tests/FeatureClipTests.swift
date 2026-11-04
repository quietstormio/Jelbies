//
//  FeatureClipTests.swift
//  2026-11-02 (the user's phone photo, r1055): Teddy and Pearl lay side by side and sank a third into each other; Pearl's wing was inside Teddy, Teddy's arm inside Pearl.
//  1. Lying pairs: two Jelbies that lie down (lieDown / flop) next to each other first make the room a flat body needs (BlobBrain+LieClear): the lying bodies just touch.
//  2. FeatureClip: whatever a feature / limb draws is never inside ANOTHER Jelbie's fitted egg by more than 1 cm (wings, Pip's tail + spikes, Teddy's ears + pom, arms).
//  The bodies themselves are not pushed (they were once, and looked deformed): the contact squish / boop sounds stay (RoomSFXCountTests, SocialTests).
//

import XCTest
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class FeatureClipTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let tol: Float = 0.01

    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        FeatureClip.enabled = true; LieClearTuning.enabled = true; ContactField.reset(); ContactField.enabled = true
    }
    override func tearDown() {
        FeatureClip.enabled = true; LieClearTuning.enabled = true; FeatureClip.eggs = []; AudioHub.requestTap = nil; ContactField.reset(); ContactField.enabled = true
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// Several Jelbies in the social lab, each with his feature set, skinned like the stage does (the clip pass included).
    @MainActor final class Duo {
        let lab: SocialTests.Lab
        let feats: [FeatureSet]
        let feature: [JellyFeature]
        var dyn: [UnsafeMutablePointer<Float>] = []
        let nVerts = MotionRig.renderMesh.vertexCount
        var eggLimit = 0
        nonisolated deinit {}
        init(positions: [SIMD2<Float>], features: [JellyFeature], seed: UInt64 = 5, quiet: Bool = true) {
            lab = SocialTests.Lab(n: positions.count, positions: positions, quiet: quiet, seed: seed)
            feature = features
            WearBody.install(MotionRig.renderMesh)
            let rmc = MotionRig.renderMesh
            ContactField.configure(eggLimit: rmc.armCapsule?.firstVertex.min() ?? rmc.vertexCount, tail: rmc.armCapsule.flatMap { $0.tailFirst >= 0 ? $0.tailFirst..<($0.tailFirst + TailBean.vertexCount) : nil })
            var fs: [FeatureSet] = []
            for (i, r) in lab.rigs.enumerated() {
                r.skinner.autoBlink = false
                r.brain.feature = features[i]
                r.brain.skinnerRef = r.skinner
                r.skinner.configureTail(MotionRig.renderMesh)
                r.skinner.configureTeddy(MotionRig.renderMesh)
                let f = FeatureSet(); f.body = WearBody.shared
                if features[i] == .wings { f.setWingTint(i, WhiteWing.wingTint) }
                fs.append(f)
                dyn.append(UnsafeMutablePointer<Float>.allocate(capacity: nVerts * 6))
                dyn[i].initialize(repeating: 0, count: nVerts * 6)
            }
            feats = fs
            eggLimit = MotionRig.renderMesh.armCapsule?.firstVertex.min() ?? nVerts
            FeatureSetKeep.keep(self)
            for i in 0..<positions.count { tickFeature(i) }
        }
        /// Put the bodies exactly here (the lab's own settling spreads a close pair apart first), at rest, the room's peer snapshot updated.
        func place(_ pos: [SIMD2<Float>]) {
            for (i, r) in lab.rigs.enumerated() {
                r.brain.abortScript(r.sim, r.skinner)
                r.sim.teleport(toXZ: pos[i])
                for _ in 0..<120 { r.sim.step() }
                r.brain.currentPose(r.sim)
            }
            lab.aside = [Float](repeating: 1e9, count: lab.aside.count)          // (no step-aside: the pair stays where it was put)
            lab.snapshot = lab.rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: false) }
        }
        func tickFeature(_ i: Int, dt: Float = 1.0 / 60) {
            let r = lab.rigs[i]
            feats[i].tick(id: i, brain: r.brain, sim: r.sim, feature: feature[i], worn: [], hideAll: false, dt: dt)
        }
        /// true = skin every body every tick (the contact profiles are fresh, as in the stage), false = only when a test asks.
        var live = false
        /// Hook called every tick (the haptic tests advance their fake clock here).
        var onTick: (() -> Void)?
        func tick() {
            onTick?()
            lab.tick(watching: false)
            for (i, r) in lab.rigs.enumerated() { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt); tickFeature(i) }
            if live { _ = skinAll() }
        }
        /// The skin jobs of every rig as the stage builds them (root = the floor position the room steers).
        func jobs() -> [JellyParallel.SkinJob] {
            lab.rigs.enumerated().map { JellyParallel.SkinJob(skinner: $1.skinner, sim: $1.sim, dst: dyn[$0], id: $0, root: GameCare.floorPos($1.brain, $1.sim)) }
        }
        /// Skin every body in parallel with its contact profile (JellyParallel.skin), the stage's clip pass, then every feature mesh (which fills the feature profiles).
        /// Returns each body's feature vertices in the world.
        func skinAll() -> [[SIMD3<Float>]] {
            let js = jobs()
            JellyParallel.skin(js, index: MotionRig.renderMesh.index)
            FeatureClip.apply(jobs: js)
            if FeatureClip.eggs.count != lab.rigs.count || !FeatureClip.enabled { FeatureClip.eggs = js.map { ClipEgg(sim: $0.sim) } }
            var out: [[SIMD3<Float>]] = []
            for (i, r) in lab.rigs.enumerated() {
                feats[i].syncCarry(i, sim: r.sim)
                let m = feats[i].frame { [dyn] id in UnsafePointer(dyn[id]) }
                out.append(m.vertices.map { SIMD3($0.pos.x, $0.pos.y, $0.pos.z) })
            }
            return out
        }
        func egg(_ i: Int) -> ClipEgg { FeatureClip.eggs[i] ?? ClipEgg(sim: lab.rigs[i].sim) }
        /// Deepest drawn vertex of body i's egg part inside body j's fitted egg (+ = inside, in rest units).
        func bodyPenetration(_ i: Int, into j: Int) -> Float {
            let e = egg(j)
            var worst: Float = -1
            for v in 0..<eggLimit {
                let p = SIMD3(dyn[i][6 * v], dyn[i][6 * v + 1], dyn[i][6 * v + 2])
                if simd_distance(p, e.centroid) > e.radius { continue }
                worst = max(worst, e.depth(p))
            }
            return worst
        }
        /// Deepest vertex of `pts` (body i's feature / limb vertices, as drawn) inside another body's egg, counting only the vertices that are free of body i in the UNCLIPPED frame `raw`
        /// (outside his own egg by more than 1 cm there): the join with the owner is where the clip lets go. `raw` nil = judge `pts` itself.
        func penetration(_ pts: [SIMD3<Float>], owner i: Int, raw: [SIMD3<Float>]? = nil) -> Float {
            var worst: Float = -1
            for (k, p) in pts.enumerated() {
                if egg(i).depth((raw ?? pts)[k]) > -0.01 { continue }
                for j in 0..<lab.rigs.count where j != i {
                    let e = egg(j)
                    if simd_distance(p, e.centroid) > e.radius { continue }
                    worst = max(worst, e.depth(p))
                }
            }
            return worst
        }
        /// The drawn arm / tail / ear blocks of body i, as points.
        func limbPoints(_ i: Int) -> [SIMD3<Float>] {
            let sk = lab.rigs[i].skinner
            var r: [Range<Int>] = []
            if sk.armCapsulesActive { for s in 0..<2 { r.append(sk.armFirst[s]..<(sk.armFirst[s] + ArmCapsule.vertexCount)) } }
            if sk.tailOn, sk.tailFirst >= 0 { r.append(sk.tailFirst..<(sk.tailFirst + TailBean.vertexCount)) }
            if sk.teddyOn, sk.teddyFirst >= 0 { r.append(sk.teddyFirst..<(sk.teddyFirst + TeddyBean.vertexCount)) }
            return r.flatMap { $0.map { SIMD3(dyn[i][6 * $0], dyn[i][6 * $0 + 1], dyn[i][6 * $0 + 2]) } }
        }
        /// Penetration (+ sunk in, - apart) of the DRAWN skins of body i and j (SkinGap), measured on freshly skinned streams.
        func bodyGap(_ i: Int, _ j: Int) -> Float { -truthGap(i, j) }
        /// The ground-truth gap of the two drawn bodies (the translation gap of the full projected triangle meshes, the tail block left out like the profile does), on freshly skinned streams.
        func truthGap(_ i: Int, _ j: Int) -> Float {
            let rm = MotionRig.renderMesh
            for k in [i, j] { let r = lab.rigs[k]; r.skinner.update(x: r.sim.x, index: rm.index, into: dyn[k]) }
            let tail = ContactField.tailLo..<ContactField.tailHi
            var idx: [UInt32] = []
            idx.reserveCapacity(rm.index.count)
            var t = 0
            while t + 2 < rm.index.count { if !(tail.contains(Int(rm.index[t])) || tail.contains(Int(rm.index[t + 1])) || tail.contains(Int(rm.index[t + 2]))) { idx.append(contentsOf: rm.index[t..<(t + 3)]) }; t += 3 }
            return ContactProfileTests.truthGap(UnsafePointer(dyn[i]), UnsafePointer(dyn[j]), count: rm.vertexCount, index: idx, rootA: GameCare.floorPos(lab.rigs[i].brain, lab.rigs[i].sim), rootB: GameCare.floorPos(lab.rigs[j].brain, lab.rigs[j].sim))
        }
        func skinGap(_ i: Int, _ j: Int) -> Float {
            for k in [i, j] { let r = lab.rigs[k]; r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: dyn[k]) }
            return SkinGap.gap(UnsafePointer(dyn[i]), UnsafePointer(dyn[j]), limit: eggLimit)
        }
    }
    enum FeatureSetKeep { static func keep(_ d: Duo) { FeatureClipTests.keep.append(d); FeatureClipTests.keep.append(d.lab) } }

    struct Stats { var lo = Float.infinity, worst: Float = -1, body: Float = -1, feature: Float = -1, limb: Float = -1, minDist = Float.infinity }

    /// Run `frames` ticks of a Duo; sample the metrics each `every` frames from `from`.
    private func run(_ d: Duo, frames: Int, from: Int = 0, every: Int = 3) -> Stats {
        var s = Stats()
        for f in 0..<frames {
            d.tick()
            guard f >= from, f % every == 0 else { continue }
            let feat = d.skinAll()
            let n = d.lab.rigs.count
            for i in 0..<n {
                s.feature = max(s.feature, d.penetration(feat[i], owner: i))
                s.limb = max(s.limb, d.penetration(d.limbPoints(i), owner: i))
                for j in (i + 1)..<max(i + 1, n) { s.body = max(s.body, d.bodyGap(i, j)) }
            }
            if n > 1 { s.minDist = min(s.minDist, simd_distance(d.lab.rigs[0].brain.position, d.lab.rigs[1].brain.position)) }
        }
        return s
    }

    // MARK: the photo case

    /// Teddy (id 0, ears) and Pearl (id 1, wings) both lie down, 1.1 apart: before the fix they sank into each other by about a third.
    /// Teddy (id 0, ears) and Pearl (id 1, wings) both lie down side by side, the second a body-width-ish away, tipped into each other or not.
    /// BEFORE (placement fix + clip off) they sink into each other; AFTER they just touch and nothing of either is inside the other.
    func testLyingPairTeddyPearl() {
        var report: [String] = []
        for after in [false, true] {
            FeatureClip.enabled = after; LieClearTuning.enabled = after
            for gap: Float in [1.0, 1.2, 1.4] {
              for signs in [(-1, 1), (1, -1)] as [(Float, Float)] {
                let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings])
                d.place([SIMD2(-gap / 2, 0.6), SIMD2(gap / 2, 0.6)])
                d.live = after          // (the contact profiles, fresh every tick, as in the stage)
                let ra = d.lab.rigs[0], rb = d.lab.rigs[1]
                ra.brain.idleForced = true; rb.brain.idleForced = true
                let a = ra.brain.idleStart(.lieDown, ra.sim), b = rb.brain.idleStart(.lieDown, rb.sim)
                if !after { ra.brain.idleState.sign = signs.0; rb.brain.idleState.sign = signs.1 }          // (after: the brains choose their side themselves)
                var s = Stats(), both = 0
                for f in 0..<(60 * 6) {
                    d.tick()
                    guard d.lab.rigs.allSatisfy({ $0.brain.idleState.kind == .lieDown && $0.brain.idleState.phase == 2 }) else { continue }
                    both += 1
                    guard f % 3 == 0 else { continue }
                    let on = FeatureClip.enabled
                    FeatureClip.enabled = false
                    let rawF = d.skinAll(), rawL = (0..<2).map { d.limbPoints($0) }
                    FeatureClip.enabled = on
                    let feat = d.skinAll()
                    for i in 0..<2 { s.feature = max(s.feature, d.penetration(feat[i], owner: i, raw: rawF[i])); s.limb = max(s.limb, d.penetration(d.limbPoints(i), owner: i, raw: rawL[i])) }
                    if both > 130, f % 12 == 0 { let g = d.bodyGap(0, 1); s.body = max(s.body, g); s.lo = min(s.lo, g) }          // (settled: after the snuggle's measurements)
                    if f % 12 == 0 { s.worst = max(s.worst, d.bodyGap(0, 1)) }
                }
                let line = "FEATCLIP lie \(after ? "AFTER" : "BEFORE") roots \(gap) signs \(signs) started \(a)/\(b) lying frames \(both) body pen settled \(s.body) ever \(s.worst) feature pen \(s.feature) limb pen \(s.limb) roots now \(simd_distance(ra.brain.position, rb.brain.position))"
                report.append(line); MotionLog.write(line)
                if after {
                    XCTAssertTrue(a && b); XCTAssertGreaterThan(both, 60, "both lie down")
                    XCTAssertLessThanOrEqual(s.worst, 0.05, "never sunk in"); XCTAssertLessThanOrEqual(s.body, 0.015, "the lying bodies do not sink into each other: \(line)")
                    XCTAssertLessThanOrEqual(s.feature, Self.tol, "no wing vertex inside the other body: \(line)")
                    XCTAssertLessThanOrEqual(s.limb, Self.tol, "no arm / ear vertex inside the other body: \(line)")
                    XCTAssertGreaterThan(s.lo, -0.01, "they snuggle: drawn skins touch (gap -1.5..+1 cm): \(line)")
                }
            }
          }
        }
        XCTAssertTrue(report.contains { $0.contains("BEFORE") && ($0.contains("body pen 0.") || $0.contains("limb pen 0.")) }, "the rig reproduces the photo (before the fix a pair sinks in)")
    }

    /// A time series of the lying pair's gap: the profile's, the mesh truth's, the settle's goal (debug; logs only).
    func testLyingSeries() {
        let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings], seed: 5)
        d.place([SIMD2(-0.6, 0.6), SIMD2(0.6, 0.6)])
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        a.brain.idleForced = true; b.brain.idleForced = true
        _ = a.brain.idleStart(.lieDown, a.sim); _ = b.brain.idleStart(.lieDown, b.sim)
        a.brain.idleState.hold = 60; b.brain.idleState.hold = 60
        for f in 0..<420 {
            d.tick()
            if f % 15 == 0 { MotionLog.write(String(format: "LYINGSERIES f%3d phases %d/%d profile gap %.4f truth gap %.4f roots %.3f", f, a.brain.idleState.phase, b.brain.idleState.phase, ContactField.gap(0, 1) ?? 9, -d.bodyGap(0, 1), simd_distance(a.brain.position, b.brain.position))) }
        }
    }

    /// From far apart: one lies down, then the other lies down 2.0 away - he scoots over to just touch (surface gap 0-5 cm, never inside).
    func testSnuggleFromFar() {
        for dist: Float in [1.8, 2.2] {
            let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.ears, .wings])
            d.place([SIMD2(-dist / 2, 0.6), SIMD2(dist / 2, 0.6)])
            d.live = true
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            a.brain.idleForced = true; b.brain.idleForced = true
            XCTAssertTrue(a.brain.idleStart(.lieDown, a.sim)); a.brain.idleState.hold = 60
            for _ in 0..<120 { d.tick() }
            d.lab.snapshot = d.lab.rigs.map { (pos: GameCare.floorPos($0.brain, $0.sim), walking: false) }
            XCTAssertTrue(b.brain.idleStart(.lieDown, b.sim)); b.brain.idleState.hold = 60
            var s = Stats(), both = 0
            for f in 0..<(60 * 7) {
                d.tick()
                guard d.lab.rigs.allSatisfy({ $0.brain.idleState.kind == .lieDown && $0.brain.idleState.phase == 2 }) else { continue }
                both += 1
                guard f % 3 == 0 else { continue }
                if both > 120, f % 12 == 0 { _ = d.skinAll(); let g = d.bodyGap(0, 1); s.body = max(s.body, g); s.lo = min(s.lo, g) }
            }
            let line = "FEATCLIP snuggle from \(dist): lying frames \(both) settled body pen max \(s.body) min \(s.lo) roots \(simd_distance(a.brain.position, b.brain.position))"
            MotionLog.write(line)
            XCTAssertGreaterThan(both, 30, line)
            XCTAssertLessThanOrEqual(s.body, 0.015, line)
            XCTAssertGreaterThan(s.lo, -0.01, "snug: \(line)")
        }
    }

    /// Wings fold up against the owner's back when a neighbour's skin is within their (open) reach, and open again when he leaves (the contact fold, FeatureSet.wingFoldWant):
    /// the neighbour goes round him and settles to touching (ContactSettle on the gap WITH the features: the owner stays put). Wherever the open wings would touch him they fold, and he
    /// stops at the folded wing (the wing lies between them, never inside him); wherever they would not, they stay open and the bodies touch.
    func testWingsFoldNextToANeighbourAndSpringBack() {
        let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.wings, .none], seed: 5)
        d.live = true
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        func openClear() -> Float { ContactField.clearance(of: d.feats[0].openWingPoints(0), ownerRoot: ContactField.root(0), against: 1) ?? 9 }
        func fold() -> Float { d.feats[0].slot(0)?.fold ?? -1 }
        var conflicts = 0, rows: [String] = []
        for k in 0..<12 {
            let ang = Float(k) * (.pi / 6)
            let u = SIMD2<Float>(sinf(ang), cosf(ang))
            d.place([SIMD2(0, 0.6), SIMD2(0, 0.6) + u * 1.6])          // (first apart, to read the touching distance along this direction)
            for _ in 0..<4 { d.tick() }
            let touchR = 1.6 - (ContactField.gap(0, 1) ?? 0.2) + 0.04
            d.place([SIMD2(0, 0.6), SIMD2(0, 0.6) + u * touchR])          // (then 4 cm short of touching: the settle closes in)
            var bodyLo: Float = 9, featLo: Float = 9
            for f in 0..<90 {
                d.tick()
                ContactSettle.step(a.brain, b.brain, target: 0, anchoredA: true, features: true)
                if f >= 60 { bodyLo = min(bodyLo, ContactField.gap(0, 1) ?? 9); featLo = min(featLo, ContactField.gap(0, 1, features: true) ?? 9) }
            }
            let f = fold(), oc = openClear()
            let fc = ContactField.clearance(of: ContactField.featurePoints(0), ownerRoot: ContactField.root(0), against: 1) ?? 9
            rows.append(String(format: "%3d deg: open wings %.3f from his skin, fold %.2f, folded wings %.3f, body gap %.4f, gap with features %.4f", k * 30, oc, f, fc, bodyLo, featLo))
            XCTAssertGreaterThanOrEqual(bodyLo, -0.01, "never inside his body: \(rows.last!)")
            XCTAssertGreaterThanOrEqual(featLo, -0.01, "never inside the (folded) wings: \(rows.last!)")
            if oc < 0.02 {
                conflicts += 1
                XCTAssertGreaterThan(f, 0.7, "wings that would touch him fold: \(rows.last!)")
                XCTAssertGreaterThanOrEqual(fc, -0.012, "the folded wings are not inside him (he stops at them): \(rows.last!)")
                XCTAssertLessThanOrEqual(bodyLo, 0.06, "and the folded wing between them is thin: the bodies are within 6 cm: \(rows.last!)")
                let feat = d.skinAll()
                XCTAssertLessThanOrEqual(d.penetration(feat[0], owner: 0, raw: feat[0]), Self.tol, "what the fold leaves is clipped: nothing drawn inside his egg: \(rows.last!)")
            }
            if oc > 0.12 {
                XCTAssertLessThan(f, 0.1, "wings that are clear stay open: \(rows.last!)")
                XCTAssertLessThanOrEqual(bodyLo, 0.012, "and the bodies touch: \(rows.last!)")
            }
            d.place([SIMD2(0, 0.6), SIMD2(3, 0.6)])          // (away between the angles: open again)
            for _ in 0..<45 { d.tick() }
            XCTAssertLessThan(fold(), 0.05, "springs back when he leaves (\(k * 30) deg)")
        }
        for r in rows { MotionLog.write("FEATCLIP wingfold " + r) }
        XCTAssertGreaterThan(conflicts, 0, "the ring puts him in the wings' reach somewhere")
    }

    /// Diagnostic (WINGFOLD_SWEEP=1): how far the wings stick out of their owner's own body footprint for each folded pose (flap, spread).
    func testZWingFoldPoseSweep() throws {
        guard ProcessInfo.processInfo.environment["WINGFOLD_SWEEP"] == "1" else { throw XCTSkip("WINGFOLD_SWEEP not set") }
        defer { FeatureTuning.forceFold = nil; FeatureTuning.foldFlap = nil; FeatureTuning.foldSpread = -15 }
        for pose in ["standing", "lying"] {
            for flap: Float in [-40, -20, 0, 20, 40, 60, 75] {
                for spread: Float in [-40, -20, 0, 20, 40] {
                    let d = Duo(positions: [SIMD2(0, 0.6)], features: [.wings], seed: 5)
                    let r = d.lab.rigs[0]
                    FeatureTuning.forceFold = 1; FeatureTuning.foldFlap = flap; FeatureTuning.foldSpread = spread
                    if pose == "lying" { r.brain.idleForced = true; _ = r.brain.idleStart(.lieDown, r.sim); r.brain.idleState.hold = 60; for _ in 0..<150 { d.tick() } } else { for _ in 0..<30 { d.tick() } }
                    _ = d.skinAll()
                    var worst: Float = -9, worstDeg = 0
                    for p in ContactField.featurePoints(0) {
                        let L = simd_length(p); guard L > 1e-3 else { continue }
                        let o = L - (ContactField.ext(0, p / L) ?? 0)
                        if o > worst { worst = o; worstDeg = Int(atan2f(p.x, p.y) * 180 / .pi) }
                    }
                    MotionLog.write(String(format: "WINGSWEEP %@ flap %3.0f spread %3.0f: wings out of his own footprint by %.3f (at %d deg, %d pts)", pose, flap, spread, worst, worstDeg, ContactField.featurePoints(0).count))
                }
            }
        }
    }

    // MARK: every feature against a neighbour

    /// The owner (id 0) wears `feature`; a plain neighbour (id 1) is put at every angle round him at several distances, nothing else moves. The deepest feature / limb vertex inside the neighbour's egg, clip off and on.
    private func sweep(_ feature: JellyFeature, owner second: JellyFeature = .none, dists: [Float] = [0.55, 0.75, 0.95, 1.15]) -> (off: Float, on: Float, offLimb: Float, onLimb: Float) {
        var off: Float = -1, on: Float = -1, offLimb: Float = -1, onLimb: Float = -1
        let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [feature, second])
        for r in dists {
            for k in 0..<12 {
                let a = Float(k) * (.pi / 6)
                d.place([SIMD2(0, 0.6), SIMD2(0, 0.6) + SIMD2(sinf(a), cosf(a)) * r])
                for _ in 0..<4 { d.tick() }
                FeatureClip.enabled = false
                let rawF = d.skinAll(), rawL = (0..<2).map { d.limbPoints($0) }
                FeatureClip.enabled = true
                let f = d.skinAll(), lim = (0..<2).map { d.limbPoints($0) }
                for i in 0..<2 {
                    off = max(off, d.penetration(rawF[i], owner: i)); offLimb = max(offLimb, d.penetration(rawL[i], owner: i))
                    on = max(on, d.penetration(f[i], owner: i, raw: rawF[i])); onLimb = max(onLimb, d.penetration(lim[i], owner: i, raw: rawL[i]))
                }
            }
        }
        FeatureClip.enabled = true
        return (off, on, offLimb, onLimb)
    }

    func testWingsNeverInsideANeighbour() {
        let r = sweep(.wings)
        MotionLog.write("FEATCLIP wings sweep: feature pen off \(r.off) on \(r.on); limb pen off \(r.offLimb) on \(r.onLimb)")
        XCTAssertGreaterThan(r.off, Self.tol, "the sweep does put a wing inside the neighbour (else it proves nothing)")
        XCTAssertLessThanOrEqual(r.on, Self.tol); XCTAssertLessThanOrEqual(r.onLimb, Self.tol)
    }
    func testPipTailAndSpikesNeverInsideANeighbour() {
        let r = sweep(.spines)
        MotionLog.write("FEATCLIP pip sweep: feature pen off \(r.off) on \(r.on); limb(tail) pen off \(r.offLimb) on \(r.onLimb)")
        XCTAssertGreaterThan(max(r.off, r.offLimb), Self.tol, "the sweep does put the tail / a spike inside the neighbour")
        XCTAssertLessThanOrEqual(r.on, Self.tol); XCTAssertLessThanOrEqual(r.onLimb, Self.tol)
    }
    func testTeddyEarsAndArmsNeverInsideANeighbour() {
        let r = sweep(.ears, dists: [0.5, 0.7, 0.9, 1.1])
        MotionLog.write("FEATCLIP teddy sweep: feature pen off \(r.off) on \(r.on); limb(ears, arms) pen off \(r.offLimb) on \(r.onLimb)")
        XCTAssertGreaterThan(max(r.off, r.offLimb), Self.tol)
        XCTAssertLessThanOrEqual(r.on, Self.tol); XCTAssertLessThanOrEqual(r.onLimb, Self.tol)
    }
    func testMossDaisyNeverInsideANeighbour() {
        let r = sweep(.daisy)
        MotionLog.write("FEATCLIP daisy sweep: feature pen off \(r.off) on \(r.on); limb pen off \(r.offLimb) on \(r.onLimb)")
        XCTAssertLessThanOrEqual(r.on, Self.tol); XCTAssertLessThanOrEqual(r.onLimb, Self.tol)
    }
    /// Lavender (wings) and Pearl (wings) side by side in a hug-close pose: wings against wings and wings against the other body.
    func testTwoWingedJelbiesNeverInsideEachOther() {
        let r = sweep(.wings, owner: .wings, dists: [0.55, 0.75, 0.95])
        MotionLog.write("FEATCLIP wings x wings sweep: feature pen off \(r.off) on \(r.on); limb pen off \(r.offLimb) on \(r.onLimb)")
        XCTAssertLessThanOrEqual(r.on, Self.tol); XCTAssertLessThanOrEqual(r.onLimb, Self.tol)
    }

    /// A flop next to a friend makes the room first too, and a lie-down with nowhere to go does not start.
    func testFlopAndLieDownMakeRoomOrStayUp() {
        let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [.none, .none])
        d.place([SIMD2(-0.5, 0.6), SIMD2(0.5, 0.6)])
        let a = d.lab.rigs[0], b = d.lab.rigs[1]
        for r in d.lab.rigs { r.brain.idleForced = true }
        XCTAssertTrue(a.brain.idleStart(.flop, a.sim), "he can flop: there is room to his left")
        XCTAssertTrue(a.brain.isWalkScript, "he first walks away to the spot a flat body needs")
        for _ in 0..<(60 * 5) { d.tick() }
        XCTAssertGreaterThanOrEqual(simd_distance(a.brain.position, b.brain.position), BlobBrain.standWidth * (BlobBrain.lieSpreadMax + 1) / 2 - 0.05)
        // nowhere to go: boxed in on a tiny floor -> declines
        LieClearTuning.enabled = true
        let tight = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6), SIMD2(0, 2.4)], features: [.none, .none, .none])
        tight.place([SIMD2(0, 0.6), SIMD2(0.35, 0.6), SIMD2(-0.35, 0.6)])
        let t = tight.lab.rigs[0]
        t.brain.idleForced = true
        let tightSpot = t.brain.lieSpot(from: t.brain.position, yaw: 0)
        XCTAssertTrue(tightSpot == nil || simd_distance(tightSpot!, t.brain.position) > 0.1, "boxed in: he walks out or stays up (never lies down in place)")
    }

    /// The feature clip is a render-side pass only: the bodies, their steering and their sounds do not change. The same boop social with the clip off and on ends with the same
    /// events and the same sound requests (and it does boop).
    func testContactSoundsAndSocialsUnchanged() {
        var counts: [String: Int] = [:]
        AudioHub.requestTap = { counts[$0, default: 0] += 1 }
        var results: [(boops: Int, counts: [String: Int])] = []
        for enabled in [false, true] {
            FeatureClip.enabled = enabled; counts = [:]
            let d = Duo(positions: SocialTests.starts, features: [.ears, .wings, .spines], seed: 3, quiet: true)
            let a = d.lab.rigs[0], b = d.lab.rigs[1]
            XCTAssertTrue(a.brain.socialStart(.boop, with: b.brain, a.sim))
            for _ in 0..<(60 * 25) { d.tick(); _ = d.skinAll() }
            let boops = d.lab.events[0].filter { if case .boop = $0 { return true }; return false }.count
            results.append((boops, counts))
            MotionLog.write("FEATCLIP sounds clip \(enabled): boop events \(boops) requests \(counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            XCTAssertGreaterThan(boops, 0, "the boop social boops (clip \(enabled))")
        }
        XCTAssertEqual(results[0].boops, results[1].boops)
        XCTAssertEqual(results[0].counts, results[1].counts, "the same sound requests with the clip on")
    }

    /// Cost of the whole clip pass (the stage's apply on the arms / tail / ears + the features' frames) for 4 bodies: standing as close as the room allows (a huddle, 1.4 apart) and pressed (0.8 apart, the worst case: every wing / ear / arm vertex is in a neighbour).
    func testClipPassCost() {
        for (name, pos, limit) in [("huddle 1.4 apart", [SIMD2<Float>(-0.7, 0.2), SIMD2(0.7, 0.2), SIMD2(-0.7, 1.6), SIMD2(0.7, 1.6)], 0.2),
                                   ("pressed 0.8 apart", [SIMD2<Float>(-0.4, 0.5), SIMD2(0.4, 0.5), SIMD2(0, 1.2), SIMD2(0, -0.1)], 1.0)] as [(String, [SIMD2<Float>], Double)] {
            let d = Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6), SIMD2(0, 2.4), SIMD2(0, -1)], features: [.ears, .wings, .spines, .daisy])
            d.place(pos)
            for _ in 0..<4 { d.tick() }
            for i in 0..<4 { d.lab.rigs[i].skinner.update(x: d.lab.rigs[i].sim.x, index: MotionRig.renderMesh.index, into: d.dyn[i]) }
            var jobs: [JellyParallel.SkinJob] = []
            for i in 0..<4 { jobs.append(JellyParallel.SkinJob(skinner: d.lab.rigs[i].skinner, sim: d.lab.rigs[i].sim, dst: d.dyn[i], id: i)) }
            for i in 0..<4 { d.feats[i].syncCarry(i, sim: d.lab.rigs[i].sim) }
            let n = 200
            var tApply = 0.0, tFrame = 0.0, tFrameOff = 0.0
            for _ in 0..<n {
                let t0 = CACurrentMediaTime()
                FeatureClip.apply(jobs: jobs)
                let t1 = CACurrentMediaTime()
                for i in 0..<4 { _ = d.feats[i].frame { [d] id in UnsafePointer(d.dyn[id]) } }
                let t2 = CACurrentMediaTime()
                tApply += t1 - t0; tFrame += t2 - t1
            }
            FeatureClip.enabled = false
            for _ in 0..<n { let t = CACurrentMediaTime(); for i in 0..<4 { _ = d.feats[i].frame { [d] id in UnsafePointer(d.dyn[id]) } }; tFrameOff += CACurrentMediaTime() - t }
            FeatureClip.enabled = true
            let cost = (tApply + tFrame - tFrameOff) / Double(n) * 1000
            let line = String(format: "FEATCLIP perf 4 bodies %@: apply %.3f ms, feature frames %.3f ms (clip off %.3f ms) -> clip cost %.3f ms/frame", name, tApply / Double(n) * 1000, tFrame / Double(n) * 1000, tFrameOff / Double(n) * 1000, cost)
            print(line); MotionLog.write(line)
            XCTAssertLessThan(cost, limit, "budget \(limit) ms for 4 bodies, \(name)")
        }
    }
}
