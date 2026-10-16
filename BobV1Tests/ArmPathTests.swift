//
//  ArmPathTests.swift
//  Wave-arm geometry: pose path, keyframed skin displacements, capsule, runtime restore.
//

import XCTest
import simd
@testable import BobV1

nonisolated final class ArmPathFixture: @unchecked Sendable {
    let sim = buildSimMesh()
    let render = buildRenderMesh()
    let kf: ArmKeyframes
    let path: ArmPath
    init(path: ArmPath = .wave) {
        let rm = render
        self.path = path
        kf = ArmKeyframeBuilder.build(path: path, rest: rm.rest, mat: rm.mat, capsule: rm.armCapsule!, index: rm.index)
        print("ARM keyframes built in \(kf.seconds * 1000) ms, vertices per side \(kf.sides.map { $0.vertices.count })")
    }
    static let shared = ArmPathFixture()
    static let nubForward = ArmPathFixture(path: .nubForward)
    static let nubBack = ArmPathFixture(path: .nubBack)
    static let nubToMouth = ArmPathFixture(path: .nubToMouth)
}

@MainActor
final class ArmPathTests: XCTestCase {
    private var fx: ArmPathFixture = .shared

    private func rest(_ v: Int) -> SIMD3<Double> {
        SIMD3(Double(fx.render.rest[3 * v]), Double(fx.render.rest[3 * v + 1]), Double(fx.render.rest[3 * v + 2]))
    }

    func testPosedFieldAtRestEqualsBobForm() {
        let F = PosedArmField(ArmPath.wave.geom(at: 0))
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<400 {
            let p = SIMD3(Double.random(in: 0.2...0.9, using: &rng), Double.random(in: 0.1...1.0, using: &rng), Double.random(in: -0.4...0.4, using: &rng))
            XCTAssertEqual(F.value(p), BobForm.sdf(p), accuracy: 1e-12)
        }
    }

    func testRestKeyframeIsExactlyZeroAndCapsuleHidden() {
        for sd in fx.kf.sides {
            let n = sd.vertices.count
            for i in 0..<(3 * n) { XCTAssertEqual(sd.delta[i], 0) }
            for i in 0..<n { XCTAssertEqual(sd.ao[i], sd.restMat[i]) }
        }
        let cap = fx.render.armCapsule!
        for f in cap.firstVertex {
            for v in f..<(f + ArmCapsule.vertexCount) {
                XCTAssertLessThan(BobForm.sdf(rest(v)), -0.01, "capsule vertex \(v) is inside the rest skin")
                XCTAssertEqual(fx.render.mat[v], 0)
            }
        }
        // capsule triangles live in the body index range
        XCTAssertEqual(cap.indexFirst + cap.indexCount, fx.render.body.count)
        // every vertex with a baked mat in 0...0.4 stays within range at every keyframe
        for sd in fx.kf.sides { XCTAssertTrue(sd.ao.allSatisfy { $0 >= 0 && $0 <= 0.4 + 1e-6 }) }
    }

    /// Mirrored-space posed positions of a side's override vertices at keyframe k.
    private func posed(_ side: Int, _ k: Int) -> [Int: SIMD3<Double>] {
        let sd = fx.kf.side(side), n = sd.vertices.count, sigma = Double(side)
        var out: [Int: SIMD3<Double>] = [:]
        for i in 0..<n {
            let v = Int(sd.vertices[i])
            let o = 3 * (k * n + i)
            let p = rest(v) + SIMD3(Double(sd.delta[o]), Double(sd.delta[o + 1]), Double(sd.delta[o + 2]))
            out[v] = SIMD3(p.x * sigma, p.y, p.z)
        }
        return out
    }

    func testEveryKeyframeInvariantsAndNoWeb() { checkKeyframeInvariants() }
    /// The pendulum nub paths are held to exactly the same ceilings as the wave (webs, folds, class invariants).
    func testNubForwardKeyframeInvariantsAndNoWeb() { fx = .nubForward; checkKeyframeInvariants() }
    func testNubBackKeyframeInvariantsAndNoWeb() { fx = .nubBack; checkKeyframeInvariants() }
    func testNubToMouthKeyframeInvariantsAndNoWeb() { fx = .nubToMouth; checkKeyframeInvariants() }
    func testNubPathsStartExactlyAtRestAndMeetThere() {
        for f in [ArmPathFixture.nubForward, ArmPathFixture.nubBack] {
            for sd in f.kf.sides { for i in 0..<(3 * sd.vertices.count) { XCTAssertEqual(sd.delta[i], 0) } }
        }
        let g0 = ArmPath.nubForward.geom(at: 0), g1 = ArmPath.nubBack.geom(at: 0)
        XCTAssertEqual(simd_length(g0.A - g1.A), 0, accuracy: 1e-12); XCTAssertEqual(simd_length(g0.B - g1.B), 0, accuracy: 1e-12)
        // the swung nub keeps its root and length, and tilts forward / back about the shoulder
        let f = ArmPath.nubForward.geom(at: 1), b = ArmPath.nubBack.geom(at: 1)
        XCTAssertEqual(simd_length(f.A - BobForm.armTop), 0, accuracy: 1e-6)
        XCTAssertEqual(simd_length(f.B - f.A), simd_length(BobForm.armTip - BobForm.armTop), accuracy: 1e-6)
        XCTAssertGreaterThan(f.B.z, BobForm.armTip.z + 0.03); XCTAssertLessThan(b.B.z, BobForm.armTip.z - 0.03)
    }

    private func checkKeyframeInvariants() {
        let K = fx.kf.intervals
        let rm = fx.render
        let cap = rm.armCapsule!
        var worstF2: Double = 0, minClass1 = Double.infinity
        var counts = [0, 0, 0]
        var worstWeb = 0, worstFold = 0, report = ""
        var worstWebF = 0.0, worstWebVisible = 0, worstFoldVisible = 0
        for side in [-1, 1] {
            let sd = fx.kf.side(side), n = sd.vertices.count, sigma = Double(side)
            // triangle lists touching this side's override set
            let set = Set(sd.vertices.map { Int($0) })
            var tris: [(Int, Int, Int)] = []
            var t = 0
            while t < rm.body.count {
                let a = Int(rm.index[t]), b = Int(rm.index[t + 1]), c = Int(rm.index[t + 2])
                if set.contains(a) || set.contains(b) || set.contains(c) { tris.append((a, b, c)) }
                t += 3
            }
            for k in 1...K {
                let g = fx.path.geom(at: Double(k) / Double(K))
                let F = PosedArmField(g)
                let pos = posed(side, k)
                func P(_ v: Int) -> SIMD3<Double> {
                    if let p = pos[v] { return p }
                    let r = rest(v); return SIMD3(r.x * sigma, r.y, r.z)
                }
                for i in 0..<sd.skinCount {
                    let v = Int(sd.vertices[i]); let p = pos[v]!
                    switch sd.cls[k * n + i] {
                    case 1:
                        counts[0] += 1
                        let c = F.cone(p)
                        minClass1 = min(minClass1, -c)
                        XCTAssertLessThanOrEqual(c, g.capsuleInflate - 0.007 + 1e-6, "k \(k) vertex \(v) class 1 inside the capsule")
                        if g.grow >= 1 { XCTAssertLessThanOrEqual(c, -0.004 + 1e-6) }
                    case 2:
                        counts[1] += 1
                        // on the field (|F| <= 0.006), or pulled inward (F >= -0.015) by the web relaxation (never outside it)
                        let fv = F.value(p); worstF2 = max(worstF2, abs(fv))
                        XCTAssertLessThanOrEqual(fv, 0.006, "k \(k) vertex \(v) class 2 outside the field")
                        XCTAssertGreaterThanOrEqual(fv, -0.015, "k \(k) vertex \(v) class 2 pulled too far in")
                    default: counts[2] += 1
                    }
                }
                // web / fold detectors. A flagged triangle is only acceptable when it cannot be seen: every vertex lies inside the
                // capsule by >= 0.002 (cone value <= capsule offset - 0.002), i.e. hidden under it.
                var webs = 0, flipped = 0, webVisible = 0, foldVisible = 0
                func hiddenUnderCapsule(_ ps: [SIMD3<Double>]) -> Bool { ps.allSatisfy { F.cone($0) <= g.capsuleInflate - 0.002 } }
                for (a, b, c) in tris {
                    let pa = P(a), pb = P(b), pc = P(c)
                    let cen = (pa + pb + pc) / 3
                    let f = F.value(cen)
                    if f > 0.01 {
                        webs += 1
                        if !hiddenUnderCapsule([pa, pb, pc]) { webVisible += 1; if webVisible <= 3 { print("WEBVIS side \(side) k\(k) F \(f) verts \([a, b, c])") } }
                    }
                    if abs(f) < 0.01 {
                        var nrm = simd_cross(pb - pa, pc - pa)
                        if side < 0 { nrm = -nrm }
                        if simd_length(nrm) > 1e-10, simd_dot(simd_normalize(nrm), F.normal(cen)) < -0.05 {
                            flipped += 1
                            if !hiddenUnderCapsule([pa, pb, pc]) { foldVisible += 1; if foldVisible <= 3 { print("FOLDVIS side \(side) k\(k) verts \([a, b, c])") } }
                        }
                    }
                }
                if let dumpDir = ProcessInfo.processInfo.environment["ARM_DUMP_DIR"] ?? (FileManager.default.fileExists(atPath: "/private/tmp/arm_dump_enable") ? "/private/tmp/arm_dump" : nil), [5, 7, 9, 11, 32].contains(k) {
                    dumpGeometry(dir: dumpDir, side: side, k: k, F: F, g: g, tris: tris, pos: pos)
                }
                worstWeb = max(worstWeb, webs); worstFold = max(worstFold, flipped)
                worstWebVisible = max(worstWebVisible, webVisible); worstFoldVisible = max(worstFoldVisible, foldVisible)
                // webs: original strict check restored (no triangle at all with its centroid > 0.01 outside F_s)
                XCTAssertEqual(webs, 0, "side \(side) keyframe \(k): web triangles outside the posed field")
                XCTAssertEqual(webVisible, 0, "side \(side) keyframe \(k): visible web triangles")
                // folds: triangles whose face normal opposes the field gradient are back faces for any outside viewer (culled by the
                // renderer, so they cannot show as a fin; they mark the faceted root wrinkle of the raise, s ~ 0.25-0.45). Bounded
                // tightly once the arm is out (k >= 15), see dbg_folds_k9_k11.png.
                XCTAssertLessThan(flipped, k >= 15 ? 6 : 200, "side \(side) keyframe \(k): folded triangles")
                if webs > 0 || flipped > 0 { report += " [s\(side) k\(k): web \(webs) (visible \(webVisible)) fold \(flipped) (visible \(foldVisible))]" }
                // capsule vertices lie on the cone offset
                for i in sd.skinCount..<n {
                    let p = pos[Int(sd.vertices[i])]!
                    // the capsule lies on the cone offset (the flared base is off by default)
                    if g.grow >= 1 { XCTAssertEqual(F.cone(p), g.capsuleInflate, accuracy: 0.003) }
                }
            }
            _ = cap
        }
        print("ARM detectors:" + report)
        print("ARM worst web \(worstWeb) (max F \(worstWebF)) fold \(worstFold); visible web \(worstWebVisible) fold \(worstFoldVisible)")
        print("ARM classes: covered \(counts[0]) fillet \(counts[1]) rest \(counts[2]) worst |F| class2 \(worstF2) min depth class1 \(minClass1)")
    }

    /// Debug aid (only when /private/tmp/arm_dump_enable exists): writes the posed mesh of a keyframe with per-triangle flags
    /// (0 ok, 1 web, 2 fold; +4 when hidden under the capsule) so the flagged triangles can be rendered offline.
    private func dumpGeometry(dir: String, side: Int, k: Int, F: PosedArmField, g: ArmGeom, tris: [(Int, Int, Int)], pos: [Int: SIMD3<Double>]) {
        let rm = fx.render, sigma = Double(side)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var p: [Float] = []
        for v in 0..<rm.vertexCount {
            let q: SIMD3<Double>
            if let m = pos[v] { q = SIMD3(m.x * sigma, m.y, m.z) } else { q = SIMD3(Double(rm.rest[3 * v]), Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2])) }
            p += [Float(q.x), Float(q.y), Float(q.z)]
        }
        var idx: [Int32] = []
        var flags: [UInt8] = []
        var t = 0
        while t < rm.body.count {
            idx += [Int32(rm.index[t]), Int32(rm.index[t + 1]), Int32(rm.index[t + 2])]
            t += 3
        }
        // flags for the triangles touching this side's set
        var flagFor: [Int: UInt8] = [:]
        for (a, b, c) in tris {
            func M(_ v: Int) -> SIMD3<Double> { let q = pos[v] ?? SIMD3(Double(rm.rest[3 * v]) * sigma, Double(rm.rest[3 * v + 1]), Double(rm.rest[3 * v + 2])); return q }
            let pa = M(a), pb = M(b), pc = M(c)
            let cen = (pa + pb + pc) / 3, f = F.value(cen)
            var fl: UInt8 = 0
            if f > 0.01 { fl = 1 }
            else if abs(f) < 0.01 {
                var nrm = simd_cross(pb - pa, pc - pa); if side < 0 { nrm = -nrm }
                if simd_length(nrm) > 1e-10, simd_dot(simd_normalize(nrm), F.normal(cen)) < -0.05 { fl = 2 }
            }
            if fl != 0 {
                if [pa, pb, pc].allSatisfy({ F.cone($0) <= g.capsuleInflate - 0.002 }) { fl |= 4 }
                flagFor[a &* 1000003 &+ b &* 7919 &+ c] = fl
            }
        }
        for i in stride(from: 0, to: idx.count, by: 3) {
            flags.append(flagFor[Int(idx[i]) &* 1000003 &+ Int(idx[i + 1]) &* 7919 &+ Int(idx[i + 2])] ?? 0)
        }
        var data = Data()
        var header = [Int32(p.count / 3), Int32(idx.count / 3)]
        data.append(Data(bytes: &header, count: 8))
        p.withUnsafeBytes { data.append(contentsOf: $0) }
        idx.withUnsafeBytes { data.append(contentsOf: $0) }
        data.append(contentsOf: flags)
        FileManager.default.createFile(atPath: "\(dir)/s\(side < 0 ? "m" : "p")_k\(k).bin", contents: data)
    }

    func testMirrorSymmetry() {
        let a = fx.kf.side(-1), b = fx.kf.side(1)
        let ca = a.vertices.count - ArmCapsule.vertexCount, cb = b.vertices.count - ArmCapsule.vertexCount
        let K = fx.kf.intervals
        for k in [8, 16, 32] {
            for i in 0..<ArmCapsule.vertexCount {
                let oa = 3 * (k * a.vertices.count + ca + i), ob = 3 * (k * b.vertices.count + cb + i)
                XCTAssertEqual(a.delta[oa], -b.delta[ob], accuracy: 1e-5)
                XCTAssertEqual(a.delta[oa + 1], b.delta[ob + 1], accuracy: 1e-5)
                XCTAssertEqual(a.delta[oa + 2], b.delta[ob + 2], accuracy: 1e-5)
                XCTAssertEqual(a.ao[k * a.vertices.count + ca + i], b.ao[k * b.vertices.count + cb + i], accuracy: 1e-5)
            }
        }
        _ = K
        // skin: the mirrored mesh vertex moves the mirrored way (meshes are near-symmetric: compare the class counts)
        func count(_ s: ArmKeyframes.Side, _ c: UInt8) -> Int { (0..<s.skinCount).filter { s.cls[32 * s.vertices.count + $0] == c }.count }
        for c: UInt8 in [1, 2] {
            XCTAssertEqual(Double(count(a, c)), Double(count(b, c)), accuracy: Double(count(b, c)) * 0.12 + 5)
        }
    }

    func testWaveEndRestoresSkinnerAndMat() {
        let sm = fx.sim, rm = fx.render
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        func mk() -> Skinner {
            Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                    eyes: buildEyeRig(render: rm, sim: sm), antennae: buildAntennaRig(render: rm, sim: sm))
        }
        let body = SoftBody(mesh: sm, firmness: 0.95)
        body.reset(drop: 0)
        for _ in 0..<60 { body.step() }
        let a = mk(), b = mk()
        a.autoBlink = false; b.autoBlink = false
        var mat = rm.mat
        func apply(_ sk: Skinner) {
            if let w = sk.takeMatWrites() {
                for (k, v) in w.vertices.enumerated() { mat[Int(v)] = w.values?[k] ?? rm.mat[Int(v)] }
            }
        }
        var dyn = [Float](repeating: 0, count: rm.vertexCount * 6), ref = dyn
        let kf = fx.kf
        var dl: [SIMD3<Float>] = [], ao: [Float] = []
        var sawMatChange = false
        for step in 0..<40 {
            let s = Float(step) / 39
            kf.evaluate(side: 1, s: s, rotation: simd_quatf(angle: 0.3, axis: SIMD3(0, 1, 0)), delta: &dl, ao: &ao)
            a.overrideVertices = kf.side(1).vertices; a.overrideDelta = dl; a.overrideMat = ao
            dyn.withUnsafeMutableBufferPointer { a.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
            apply(a)
            if mat != rm.mat { sawMatChange = true }
        }
        XCTAssertTrue(sawMatChange)
        a.clearOverride()
        dyn.withUnsafeMutableBufferPointer { a.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
        apply(a)
        ref.withUnsafeMutableBufferPointer { b.update(x: body.x, index: rm.index, into: $0.baseAddress!) }
        XCTAssertTrue(a.overrideVertices.isEmpty)
        XCTAssertEqual(dyn, ref, "after the wave the skinner output equals a never-waved skinner")
        XCTAssertEqual(mat, rm.mat, "mat restored")
        XCTAssertNil(a.takeMatWrites())
    }

    func testPathIsContinuousAndGeneric() {
        // the geometry changes smoothly along s (no jumps between keyframes) and a custom path works like the wave
        var prev = ArmPath.wave.geom(at: 0)
        for k in 1...200 {
            let g = ArmPath.wave.geom(at: Double(k) / 200)
            XCTAssertLessThan(simd_length(g.B - prev.B), 0.06, "tip jump at \(k)")
            XCTAssertLessThan(simd_length(g.A - prev.A), 0.06, "root jump at \(k)")
            prev = g
        }
        let custom = ArmPath(name: "reach", knots: [.init(s: 0, pose: .rest),
            .init(s: 1, pose: .posed(yS: 0.5, thetaDeg: 90, tiltDeg: 40, inset: 0.1, prot: 0.3, r1: 0.12, r2: 0.12, k: 0.05))])
        let g = custom.geom(at: 1)
        XCTAssertGreaterThan(g.B.z, g.A.z + 0.1, "forward tilt supported")
    }
}
