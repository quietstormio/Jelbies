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
    static func truthGap(_ da: UnsafePointer<Float>, _ db: UnsafePointer<Float>, count: Int, index: [UInt32], indexB: [UInt32]? = nil, rootA: SIMD2<Float>, rootB: SIMD2<Float>) -> Float {
        let d = rootB - rootA, L = simd_length(d), u = d / L, v = SIMD2(-u.y, u.x)
        let w0: Float = -1.2, step: Float = 0.001, n = 2400
        var envA = [Float](repeating: -.infinity, count: n), envB = [Float](repeating: .infinity, count: n)
        func edges(_ dyn: UnsafePointer<Float>, _ root: SIMD2<Float>, _ offset: Float, _ isA: Bool, _ index: [UInt32]) {
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
        edges(da, rootA, 0, true, index)
        edges(db, rootB, L, false, indexB ?? index)
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
                        return ContactSurface(root: ContactField.root(i), dyn: UnsafePointer(d.dyn[i]), ranges: rs, index: MotionRig.renderMesh.index)          // (with the triangles: the footprint gap sees the surface between the vertices)
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

    /// 2026-11-04: the gap stays a finite signed number however deep the footprints sit in each other (it used to go nil past ~-0.3 m: the settle and the wall switched off exactly there).
    func testGapIsFiniteOnDeepOverlap() {
        for (f0, f1) in [(JellyFeature.none, JellyFeature.ears), (.ears, .wings), (.spines, .none)] {
            let d = FeatureClipTests.Duo(positions: [SIMD2(-1.5, 0.6), SIMD2(1.5, 0.6)], features: [f0, f1], seed: 5)
            FeatureClipTests.keep.append(d)
            d.place([SIMD2(-0.8, 0.6), SIMD2(0.8, 0.6)])
            for _ in 0..<20 { d.tick() }
            _ = d.skinAll()
            guard let t = ContactField.touchDistance(0, 1) else { XCTFail("no profile"); continue }
            let ra = ContactField.root(0), u = simd_normalize(ContactField.root(1) - ra)
            for depth in [0.1, 0.2, 0.3, 0.4, 0.5, 0.7] as [Float] {
                for feats in [false, true] {
                    let g = ContactField.gap(0, at: ra, 1, at: ra + u * (t - depth), features: feats)
                    XCTAssertNotNil(g, "\(f0)/\(f1) \(depth) m deep: a gap, never nil")
                    if let g, !feats { XCTAssertEqual(g, -depth, accuracy: 0.01, "\(f0)/\(f1): \(depth) m into each other reads about -\(depth)") }
                    if let g, feats { XCTAssertLessThanOrEqual(g, 0.01, "\(f0)/\(f1) \(depth) m deep (features): not apart") }
                }
            }
        }
    }

    // MARK: 2026-11-04 measurement trust (g-measure)

    /// A synthetic skinned stream: a cylinder of radius `r` around `c`, five heights, 360 points a ring (6 floats a vertex).
    private func cylinder(_ c: SIMD2<Float>, r: Float) -> [Float] {
        var f: [Float] = []
        for h in 0..<5 { for k in 0..<360 {
            let a = Float(k) * .pi / 180
            f += [c.x + r * cosf(a), 0.1 + 0.2 * Float(h), c.y + r * sinf(a), 0, 1, 0]
        } }
        return f
    }
    private func withSyntheticBuild(_ body: () -> Void) {
        let save = (ContactField.eggLimit, ContactField.tailLo, ContactField.tailHi, ContactField.eggStride, ContactField.limbStride, ContactField.refinePasses)
        ContactField.eggLimit = Int.max; ContactField.tailLo = Int.max; ContactField.tailHi = Int.max; ContactField.eggStride = 1; ContactField.limbStride = 1; ContactField.refinePasses = 0
        body()
        (ContactField.eggLimit, ContactField.tailLo, ContactField.tailHi, ContactField.eggStride, ContactField.limbStride, ContactField.refinePasses) = save
    }

    /// A tail / wing / spike vertex INSIDE the other body always reads negative (it used to read +infinity - i.e. the plain body gap - when the lone tip had no neighbouring bin to make an edge).
    func testFeatureTipInsideTheOtherBodyReadsNegative() {
        withSyntheticBuild {
            let ra = SIMD2<Float>(0, 0), rb = SIMD2<Float>(1.0, 0)
            let da = cylinder(ra, r: 0.45), db = cylinder(rb, r: 0.45)
            ContactField.build(id: 0, dyn: da, count: da.count / 6, root: ra)
            ContactField.build(id: 1, dyn: db, count: db.count / 6, root: rb)
            func rebuild() { ContactField.build(id: 0, dyn: da, count: da.count / 6, root: ra); ContactField.build(id: 1, dyn: db, count: db.count / 6, root: rb) }          // (a new stamp: the pair gap is cached per profile stamp)
            XCTAssertEqual(ContactField.gap(0, 1) ?? 9, 0.10, accuracy: 0.01, "the bodies alone: 1.0 apart, two 0.45 radii")
            // (1) A's tail: a lone tip at (1.0, 0) = B's centre, 0.45 inside B's skin
            ContactField.buildFeature(id: 0, count: 1, position: { _ in SIMD3(1.0, 0.3, 0) })
            let g1 = ContactField.gap(0, 1, features: true)
            XCTAssertNotNil(g1); XCTAssertEqual(g1 ?? 9, -0.45, accuracy: 0.02, "A's tail tip at B's centre: 0.45 m inside B's near edge (0.55)")
            XCTAssertEqual(ContactField.gap(0, at: ra, 1, at: rb, features: true) ?? 9, -0.45, accuracy: 0.02, "the hypothetical-roots query agrees")
            rebuild()
            // (2) the same tip beside B (lateral 0.8: nothing to hit): the features add nothing
            ContactField.buildFeature(id: 0, count: 1, position: { _ in SIMD3(1.0, 0.3, 0.8) })
            XCTAssertEqual(ContactField.gap(0, 1, features: true) ?? 9, 0.10, accuracy: 0.01, "a tip beside the other body is no overlap")
            rebuild()
            // (3) B's tail pointing into A: the mirror
            ContactField.clearFeature(id: 0)
            ContactField.buildFeature(id: 1, count: 1, position: { _ in SIMD3(0.1, 0.3, 0) })
            XCTAssertEqual(ContactField.gap(0, 1, features: true) ?? 9, -0.35, accuracy: 0.02, "B's tail tip 0.1 from A's centre: 0.35 inside A's far edge (0.45)")
            rebuild()
            // (4) a short tail whose tip is OUTSIDE: positive, equal to the true tip clearance (tip at 0.7 from A's root, B's near edge at 0.55 -> -0.15 is inside; at 0.5 -> +0.05)
            ContactField.clearFeature(id: 1)
            ContactField.buildFeature(id: 0, count: 1, position: { _ in SIMD3(0.5, 0.3, 0) })
            XCTAssertEqual(ContactField.gap(0, 1, features: true) ?? 9, 0.05, accuracy: 0.015, "a tail tip 5 cm short of B: the tip clearance (the body gap is 10 cm)")
        }
    }

    /// ArrivalTracker: nothing before somebody has stepped; the first quiet frame AFTER a step that stays quiet is the arrival; a one-frame hiccup between two steps is not.
    func testArrivalTracker() {
        var t = ArrivalTracker()
        for f in 0..<5 { XCTAssertFalse(t.wantsGap(anyStepping: false)); t.feed(frame: f, anyStepping: false, gap: nil) }          // (no walker yet)
        XCTAssertNil(t.gap)
        for f in 5..<20 { t.feed(frame: f, anyStepping: true, gap: nil) }
        XCTAssertTrue(t.wantsGap(anyStepping: false))
        t.feed(frame: 20, anyStepping: false, gap: 0.30)          // a hiccup ...
        XCTAssertNil(t.gap)
        t.feed(frame: 21, anyStepping: true, gap: nil)          // ... the next step goes on
        XCTAssertNil(t.gap)
        XCTAssertTrue(t.wantsGap(anyStepping: false), "the hiccup's candidate is dropped: the gap is wanted again")
        t.feed(frame: 30, anyStepping: false, gap: 0.062)          // the real arrival
        t.feed(frame: 31, anyStepping: false, gap: nil); XCTAssertNil(t.gap, "not confirmed after 2 quiet frames")
        t.feed(frame: 32, anyStepping: false, gap: nil)
        XCTAssertEqual(t.gap ?? 9, 0.062, accuracy: 1e-6, "the gap of the FIRST quiet frame")
        XCTAssertEqual(t.frame, 30)
        t.feed(frame: 33, anyStepping: true, gap: nil); t.feed(frame: 50, anyStepping: false, gap: 0.5); t.feed(frame: 51, anyStepping: false, gap: nil); t.feed(frame: 52, anyStepping: false, gap: nil)
        XCTAssertEqual(t.gap ?? 9, 0.062, accuracy: 1e-6, "once recorded it never changes (later shuffles are not the arrival)")
    }

    /// The harness gap is a property of the DRAWN mesh: moving a root along the axis (the brain root runs ahead of the lagging sim body in a hop) changes nothing; moving the mesh does.
    /// And the support gap is the strict one: for bodies standing staggered it reads an overlap where the footprints still have floor between them.
    func testGapIsFromTheMeshNotTheRoots() {
        func box(_ c: SIMD2<Float>, root: SIMD2<Float>? = nil) -> ContactSurface {
            var pts: [SIMD3<Float>] = []
            for i in -20...20 { for j in -20...20 { for h in [0.1, 0.5, 0.9] as [Float] { pts.append(SIMD3(c.x + Float(i) * 0.02, h, c.y + Float(j) * 0.02)) } } }
            return ContactSurface(root: root ?? c, points: pts)
        }
        let a = box(SIMD2(0, 0))
        let base = BruteForceContactMetric.skinGap(a, box(SIMD2(1.0, 0)))
        XCTAssertEqual(base, 0.2, accuracy: 1e-4, "two 0.8 wide boxes 1.0 apart")
        XCTAssertEqual(BruteForceContactMetric.skinGap(a, box(SIMD2(1.0, 0), root: SIMD2(1.45, 0))), base, accuracy: 1e-4, "the root 0.45 ahead of the mesh along the axis: the same gap")
        XCTAssertEqual(BruteForceContactMetric.skinGap(a, box(SIMD2(1.0, 0), root: SIMD2(0.55, 0))), base, accuracy: 1e-4, "... or behind it")
        XCTAssertEqual(BruteForceContactMetric.skinGap(a, box(SIMD2(0.9, 0))), base - 0.1, accuracy: 1e-4, "moving the MESH moves the gap")
        let st = box(SIMD2(0.5, 0.9))
        let both = BruteForceContactMetric.drawnGap(a, st)
        XCTAssertLessThan(both.support, 0, "staggered boxes overlap in support along the centre axis (\(both.support))")
        XCTAssertGreaterThan(both.footprint, 0.05, "... while the footprints are apart (\(both.footprint)): the axis artefact the footprint column exposes")
        XCTAssertLessThanOrEqual(both.support, both.footprint, "the support gap is the lower bound")
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
            for j in js { ContactField.build(id: j.id, dyn: UnsafePointer(j.dst), count: j.skinner.vertexCount, root: j.root, blocks: j.skinner.contactBlocks) }
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
