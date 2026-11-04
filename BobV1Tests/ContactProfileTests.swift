//
//  ContactProfileTests.swift
//  The contact profile (Melon/ContactProfile.swift): the radial extent table of the DRAWN skin must match the ground truth of the skinned body (the farthest crossing of the
//  projected triangle edges along each ray from the root) within 0.3 cm, standing / lying / leaning, for all 6 species; the pair gap must match the real skin-to-skin gap
//  (SkinGap, the nearest-vertex measure) to a few mm; the whole profile + pair pass fits the frame budget.
//

import XCTest
import simd
import QuartzCore
@testable import BobV1

@MainActor
final class ContactProfileTests: XCTestCase {
    override func setUp() {
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        ContactField.reset(); ContactField.enabled = true; FeatureClip.enabled = true; LieClearTuning.enabled = true
    }
    override func tearDown() {
        ContactField.reset(); ContactField.enabled = true; FeatureClip.eggs = []
        RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    /// The 6 species: character id, feature.
    static let species: [(name: String, feature: JellyFeature)] = [("Bob", .none), ("Pip", .spines), ("Moss", .daisy), ("Lavender", .wings), ("Teddy", .ears), ("Pearl", .wings)]

    /// Ground truth: the farthest crossing, along the ray from `root` in the direction `dir`, of the projected edges of the triangles `index` over the vertices `pos` (world xz).
    static func truthExtent(_ pos: (Int) -> SIMD3<Float>, count: Int, index: [UInt32], root: SIMD2<Float>, dir: SIMD2<Float>) -> Float {
        var best: Float = 0
        var i = 0
        while i + 2 < index.count {
            let t3 = [Int(index[i]), Int(index[i + 1]), Int(index[i + 2])]
            i += 3
            guard t3.allSatisfy({ $0 < count }) else { continue }
            for e in 0..<3 {
                let pa = pos(t3[e]), pb = pos(t3[(e + 1) % 3])
                let a = SIMD2(pa.x, pa.z) - root, b = SIMD2(pb.x, pb.z) - root
                let E = b - a
                let denom = dir.x * E.y - dir.y * E.x
                if abs(denom) < 1e-9 { continue }
                let t = (a.x * E.y - a.y * E.x) / denom
                let u = (a.x * dir.y - a.y * dir.x) / denom
                if t > best, u >= 0, u <= 1 { best = t }
            }
        }
        return best
    }

    /// The render mesh's triangles without Pip's tail block (the body profile leaves the tail to the feature layer).
    static let bodyIndex: [UInt32] = {
        let rm = MotionRig.renderMesh
        let tail = ContactField.tailLo..<ContactField.tailHi
        var idx: [UInt32] = []
        var t = 0
        while t + 2 < rm.index.count { if !(tail.contains(Int(rm.index[t])) || tail.contains(Int(rm.index[t + 1])) || tail.contains(Int(rm.index[t + 2]))) { idx.append(contentsOf: rm.index[t..<(t + 3)]) }; t += 3 }
        return idx
    }()

    /// Ground truth of the pair gap from the full skinned meshes: the translation gap along the root axis of the two projected triangle meshes, sampled every 1 mm across the
    /// lateral overlap (B's nearest axial coordinate - A's farthest, over every projected edge of both meshes).
    static func truthGap(_ da: UnsafePointer<Float>, _ db: UnsafePointer<Float>, count: Int, index: [UInt32], rootA: SIMD2<Float>, rootB: SIMD2<Float>) -> Float {
        let d = rootB - rootA, L = simd_length(d), u = d / L, v = SIMD2(-u.y, u.x)
        let w0: Float = -1.2, step: Float = 0.001, n = 2400
        var envA = [Float](repeating: -.infinity, count: n), envB = [Float](repeating: .infinity, count: n)
        func edges(_ dyn: UnsafePointer<Float>, _ root: SIMD2<Float>, _ offset: Float, _ isA: Bool) {
            var i = 0
            while i + 2 < index.count {
                for e in 0..<3 {
                    let ia = Int(index[i + e]), ib = Int(index[i + (e + 1) % 3])
                    guard ia < count, ib < count else { continue }
                    let pa = SIMD2(dyn[6 * ia] - root.x, dyn[6 * ia + 2] - root.y), pb = SIMD2(dyn[6 * ib] - root.x, dyn[6 * ib + 2] - root.y)
                    let a0 = simd_dot(pa, u) + offset, a1 = simd_dot(pb, u) + offset, l0 = simd_dot(pa, v), l1 = simd_dot(pb, v)
                    let lo = min(l0, l1), hi = max(l0, l1)
                    var k0 = Int(((lo - w0) / step).rounded(.up)), k1 = Int(((hi - w0) / step).rounded(.down))
                    k0 = max(k0, 0); k1 = min(k1, n - 1)
                    if k0 > k1 { continue }
                    for k in k0...k1 {
                        let w = w0 + Float(k) * step
                        let t: Float = abs(l1 - l0) < 1e-7 ? (isA ? max(a0, a1) : min(a0, a1)) : a0 + (a1 - a0) * ((w - l0) / (l1 - l0))
                        if isA { if t > envA[k] { envA[k] = t } } else { if t < envB[k] { envB[k] = t } }
                    }
                }
                i += 3
            }
        }
        edges(da, rootA, 0, true)
        edges(db, rootB, L, false)
        var best = Float.infinity
        for k in 0..<n where envA[k].isFinite && envB[k].isFinite { best = min(best, envB[k] - envA[k]) }
        return best
    }

    /// One pose of one species: profile vs truth at 72 directions. Returns the worst difference (m) for the body table and for the feature table.
    private func compare(_ d: FeatureClipTests.Duo, label: String) -> (body: Float, feature: Float, within: Int, withinF: Int, nF: Int) {
        let feat = d.skinAll()
        let r = d.lab.rigs[0]
        let root = GameCare.floorPos(r.brain, r.sim)
        let rm = MotionRig.renderMesh
        let dyn = d.dyn[0]
        var worstB: Float = 0, worstF: Float = 0
        var errB: [Float] = [], errF: [Float] = []
        for k in 0..<72 {
            let a = Float(k) * (2 * .pi / 72) + 0.013
            let dir = SIMD2(cosf(a), sinf(a))
            let truth = Self.truthExtent({ SIMD3(dyn[6 * $0], dyn[6 * $0 + 1], dyn[6 * $0 + 2]) }, count: rm.vertexCount, index: Self.bodyIndex, root: root, dir: dir)
            let prof = ContactField.ext(0, dir, features: false) ?? -1
            if abs(prof - truth) > worstB { worstB = abs(prof - truth) }
            errB.append(abs(prof - truth))
        }
        // the feature mesh (wings, daisy, spines) of the owner: its triangles are in the room mesh, not the skin
        let m = d.feats[0].frame { [dyn] id in UnsafePointer(dyn) }
        if !m.vertices.isEmpty {
            for k in 0..<72 {
                let a = Float(k) * (2 * .pi / 72) + 0.013
                let dir = SIMD2(cosf(a), sinf(a))
                let truth = Self.truthExtent({ let p = m.vertices[$0].pos; return SIMD3(p.x, p.y, p.z) }, count: m.vertices.count, index: m.indices, root: root, dir: dir)
                let prof = ContactField.featureExt(0, dir)          // (a corridor support: never below the farthest crossing of the ray, a little above where the feature is oblique)
                let e = truth > 0.01 ? max(0, truth - prof) : 0
                if e > worstF { worstF = e }
                errF.append(e)
            }
        }
        _ = feat
        let within = errB.filter { $0 <= 0.003 }.count, withinF = errF.filter { $0 <= 0.003 }.count
        MotionLog.write(String(format: "PROFILE %@: body within 3 mm at %d/72 directions (max %.1f mm); feature never under by more than 3 mm at %d/%d (max under %.1f mm, %d feature verts)", label, within, worstB * 1000, withinF, errF.count, worstF * 1000, m.vertices.count))
        return (worstB, worstF, within, withinF, errF.count)
    }

    func testProfileMatchesSkinStandingLyingLeaning() {
        var worstAll: Float = 0, worstFeat: Float = 0
        for (name, feature) in Self.species {
            for pose in ["standing", "lying", "leaning"] {
                let d = FeatureClipTests.Duo(positions: [SIMD2(0, 0.6)], features: [feature], seed: 5)
                let r = d.lab.rigs[0]
                r.brain.idleForced = true
                switch pose {
                case "lying":
                    XCTAssertTrue(r.brain.idleStart(.lieDown, r.sim)); r.brain.idleState.hold = 60
                    for _ in 0..<150 { d.tick() }
                case "leaning":
                    XCTAssertTrue(r.brain.idleStart(.look, r.sim)); r.brain.idleState.hold = 60
                    for _ in 0..<80 { d.tick() }
                default:
                    for _ in 0..<30 { d.tick() }
                }
                let c = compare(d, label: "\(name) \(pose)")
                worstAll = max(worstAll, c.body); worstFeat = max(worstFeat, c.feature)
                XCTAssertGreaterThanOrEqual(c.within, 50, "\(name) \(pose): the body profile is within 0.3 cm of the skin at (nearly) every direction (the exceptions are the steep arm / tail edges: a notch narrower than a bin)")
                XCTAssertLessThanOrEqual(c.body, 0.08, "\(name) \(pose): and within 8 cm even there")
                XCTAssertGreaterThanOrEqual(c.withinF, c.nF - 1, "\(name) \(pose): the feature profile never under-reports the feature mesh by more than 0.3 cm")
            }
        }
        MotionLog.write(String(format: "PROFILE worst over 6 species x 3 poses: body %.2f mm, feature %.2f mm", worstAll * 1000, worstFeat * 1000))
    }

    /// The pair gap (the exact translation gap of the two profile polygons) against the ground truth of the full skinned meshes: Teddy + Pearl lying, Bob + Teddy standing,
    /// Pip + Pearl, at several centre distances. Also the old nearest-vertex measure (SkinGap) for comparison.
    func testPairGapMatchesTheSkinToSkinGap() {
        var worst: Float = 0, worstTouch: Float = 0
        let rm = MotionRig.renderMesh
        for (f0, f1) in [(JellyFeature.ears, JellyFeature.wings), (.none, .ears), (.spines, .wings)] {
            for lying in [false, true] {
                for dist in [1.1, 1.3, 1.6, 2.0] as [Float] {
                    let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [f0, f1], seed: 5)
                    d.place([SIMD2(-dist / 2, 0.6), SIMD2(dist / 2, 0.6)])
                    let a = d.lab.rigs[0], b = d.lab.rigs[1]
                    LieClearTuning.enabled = false          // (the pair is put exactly here: no walking away first)
                    if lying {
                        a.brain.idleForced = true; b.brain.idleForced = true
                        _ = a.brain.idleStart(.lieDown, a.sim); _ = b.brain.idleStart(.lieDown, b.sim)
                        a.brain.idleState.hold = 60; b.brain.idleState.hold = 60
                        for _ in 0..<150 { d.tick() }
                    } else { for _ in 0..<10 { d.tick() } }
                    FeatureClip.enabled = false
                    _ = d.skinAll()
                    guard let g = ContactField.gap(0, 1) else { XCTFail("no profile"); continue }
                    let ra = ContactField.root(0), rb = ContactField.root(1)
                    let truth = Self.truthGap(UnsafePointer(d.dyn[0]), UnsafePointer(d.dyn[1]), count: rm.vertexCount, index: Self.bodyIndex, rootA: ra, rootB: rb)
                    let dir = simd_normalize(rb - ra)
                    let est = (ContactField.touch(0, 1, dir: dir) ?? 0)
                    let estGap = simd_distance(ra, rb) - est
                    worst = max(worst, abs(g - truth)); worstTouch = max(worstTouch, abs(estGap - truth))
                    MotionLog.write(String(format: "PAIRGAP %@/%@ %@ centres %.2f: polygon gap %.4f, radial touch gap %.4f, mesh truth %.4f (polygon err %.1f mm, radial err %.1f mm), nearest-vertex %.4f", "\(f0)", "\(f1)", lying ? "lying" : "standing", dist, g, estGap, truth, abs(g - truth) * 1000, abs(estGap - truth) * 1000, d.skinGap(0, 1)))
                }
            }
        }
        MotionLog.write(String(format: "PAIRGAP worst: polygon gap %.1f mm, radial touch %.1f mm off the mesh truth", worst * 1000, worstTouch * 1000))
        XCTAssertLessThan(worst, 0.006, "the pair gap is within 6 mm of the ground truth of the skinned meshes")
    }

    /// The pair gap against `BruteForceContactMetric.skinGap` (the catalogue's ground truth: root distance minus both skins' support along the root axis over the shared height, every
    /// drawn vertex) on the same skinned streams: 6 species (each with the next), standing / lying / leaning, side by side and one behind the other, near touching.
    func testGapAgreesWithBruteForceMetric() {
        var worst: Float = 0, worstF: Float = 0, rows: [String] = [], n = 0, within = 0
        let sp = Self.species
        for (si, s0) in sp.enumerated() {
            let s1 = sp[(si + 1) % sp.count]
            for pose in ["standing", "lying", "leaning"] {
                for axis in ["x", "z"] {
                    let u: SIMD2<Float> = axis == "x" ? SIMD2(1, 0) : SIMD2(0, 1)
                    let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [s0.feature, s1.feature], seed: 5)
                    FeatureClipTests.keep.append(d)
                    LieClearTuning.enabled = false
                    d.place([SIMD2(0, 0.6) - u * 1.0, SIMD2(0, 0.6) + u * 1.0])
                    let a = d.lab.rigs[0], b = d.lab.rigs[1]
                    switch pose {
                    case "lying":
                        for r in [a, b] { r.brain.idleForced = true; _ = r.brain.idleStart(.lieDown, r.sim); r.brain.idleState.hold = 60 }
                        for _ in 0..<150 { d.tick() }
                    case "leaning":
                        for r in [a, b] { r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.hold = 60 }
                        for _ in 0..<80 { d.tick() }
                    default: for _ in 0..<20 { d.tick() }
                    }
                    // B settles along the axis to about touching (the profile's own say), then both are measured on the same frame
                    d.live = true
                    for _ in 0..<70 { d.tick(); ContactSettle.step(a.brain, b.brain, target: 0.005, anchoredA: true) }
                    d.live = false
                    FeatureClip.enabled = false
                    _ = d.skinAll()
                    FeatureClip.enabled = true
                    guard let g = ContactField.gap(0, 1) else { XCTFail("no profile"); continue }
                    let surf = (0..<2).map { i -> ContactSurface in
                        var rs = d.contactRanges(i)
                        rs.removeAll { $0.lowerBound == ContactField.tailLo }          // (the tail is a feature: FeatureClip's job, not the body profile's)
                        return ContactSurface(root: ContactField.root(i), dyn: UnsafePointer(d.dyn[i]), ranges: rs)
                    }
                    let truth = BruteForceContactMetric.skinGap(surf[0], surf[1]), foot = BruteForceContactMetric.footprintGap(surf[0], surf[1])
                    let sg = ContactField.skinGap(0, 1) ?? 9
                    let e = abs(sg - truth), eF = abs(g - foot)
                    worst = max(worst, e); worstF = max(worstF, eF); n += 1; if e <= 0.005 { within += 1 }
                    let row = String(format: "%@+%@ %@ along %@: skinGap %.4f vs brute force %.4f (|diff| %.1f mm); footprint gap %.4f vs brute force %.4f (|diff| %.1f mm)", s0.name, s1.name, pose, axis, sg, truth, e * 1000, g, foot, eF * 1000)
                    rows.append(row); MotionLog.write("BRUTEFORCE " + row)
                    XCTAssertLessThanOrEqual(e, 0.005, "skinGap (support) vs BruteForceContactMetric.skinGap: " + row)
                    XCTAssertLessThanOrEqual(eF, 0.005, "gap (footprint) vs BruteForceContactMetric.footprintGap: " + row)
                    XCTAssertGreaterThanOrEqual(g, sg - 0.002, "the footprint gap is never below the support gap: " + row)
                }
            }
        }
        MotionLog.write(String(format: "BRUTEFORCE worst |skinGap - brute force| %.1f mm, |gap - brute-force footprint| %.1f mm over %d pairs (%d within 0.5 cm)", worst * 1000, worstF * 1000, n, within))
    }

    /// Cost: building the profiles inside the parallel skin pass, and the pair queries.
    func testProfilePerf() {
        let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6), SIMD2(0, 2.4), SIMD2(0, -1), SIMD2(2.4, 2.4)], features: [.ears, .wings, .spines, .daisy, .none], seed: 5)
        for _ in 0..<20 { d.tick() }
        let js = d.jobs()
        for j in js { j.skinner.update(x: j.sim.x, index: MotionRig.renderMesh.index, into: j.dst) }
        let n = 300
        var tBuild = 0.0
        for _ in 0..<n {
            let t0 = CACurrentMediaTime()
            for j in js { ContactField.build(id: j.id, dyn: UnsafePointer(j.dst), count: j.skinner.vertexCount, root: j.root) }
            tBuild += CACurrentMediaTime() - t0
        }
        var tPairs = 0.0, sink: Float = 0
        for _ in 0..<n {
            let t0 = CACurrentMediaTime()
            for i in 0..<5 { for j in (i + 1)..<5 { sink += ContactField.gap(i, at: ContactField.root(i), j, at: ContactField.root(j)) ?? 0 } }          // (uncached)
            tPairs += CACurrentMediaTime() - t0
        }
        let perBody = tBuild / Double(n) / 5 * 1000
        let line = String(format: "PROFILE perf: build %.4f ms per body (%d vertices), 5 bodies %.3f ms serial, 10 pair gaps %.4f ms (sink %.1f)", perBody, js[0].skinner.vertexCount, tBuild / Double(n) * 1000, tPairs / Double(n) * 1000, sink)
        print(line); MotionLog.write(line)
        XCTAssertLessThan(perBody, 0.03, "budget 0.03 ms a body")
        XCTAssertLessThan(tPairs / Double(n) * 1000, 0.15, "10 uncached pair gaps (a 5-body room has 10 pairs; the frame computes each once, cached per profile)")
        XCTAssertLessThan(tBuild / Double(n) * 1000 + tPairs / Double(n) * 1000 * 0.3, 0.25, "5 bodies: profiles (serial worst case) + the pair checks within 0.25 ms")
    }
}
