//
//  FeatureTests.swift
//  The character features (Features/): every feature resource loads within budget and binds where it was authored; no feature vertex is on the mouth
//  keep-out across poses (rest, squashed, the flap sweep, the daisy closed, every on-hat placement); the compat rules hold for every wearable (no
//  feature / wearable interpenetration beyond tolerance at rest and through the flap range); the solver matches the art lab's examples; Lavender's
//  flap-hop completes, lands, keeps the feet attached and the arms capped, and respects its gates; the hide rules (wash, sleep).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FeatureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let features: [JellyFeature] = [.spines, .daisy, .wings]
    static let restBody = SoftBody(mesh: MotionRig.simMesh, firmness: 0.95)

    /// A slot at rest (carry = identity about the rest centroid) with the given fit / animation.
    static func restSlot(_ f: JellyFeature, fit: FeatureFit = FeatureFit(), flap: Float = 0, spread: Float = 0, close: Float = 0, squash: Float = 1) -> FeatureSet.Slot {
        var s = FeatureSet.Slot()
        s.feature = f; s.fit = fit; s.scale = 1; s.primed = true
        let c0 = restBody.restCentroid
        s.carry = EyeMaskModel.Carry(centroid: c0, rotation: simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), squash: squash, restCentroid: c0)
        s.flap = flap; s.spread = spread; s.close = close
        for p in fit.hiddenParts { s.partScale[p] = 0 }
        s.spineA = Array(repeating: .zero, count: FeatureSpec.shared.spines.count)
        return s
    }
    static func placement(_ f: JellyFeature, _ fit: FeatureFit) -> FeatureMeshes.Placement {
        var pl = FeatureMeshes.Placement()
        if f == .daisy { pl.onHat = fit.onHat; pl.anchor = fit.anchor; pl.tilt = fit.tilt; pl.sink = fit.sink }
        if f == .wings { pl.dy = fit.wingDY }
        return pl
    }
    /// The feature mesh of a rest slot (world = rest space), rigidly carried.
    static func mesh(_ s: FeatureSet.Slot) -> (RoomMesh, FeaturePrepared)? {
        guard let p = FeatureMeshes.prepare(s.feature, placement: placement(s.feature, s.fit), body: WearBody.shared) else { return nil }
        var m = RoomMesh()
        FeatureSet.emit(p, into: &m, slot: s, skin: nil, spec: .shared)
        return (m, p)
    }

    // MARK: resources

    func testEveryFeatureLoadsWithinBudgetAndBindsWhereAuthored() {
        let spec = FeatureSpec.shared
        XCTAssertGreaterThan(spec.version, 0, "feature_compat.json is in the bundle")
        XCTAssertEqual(spec.spines.count, 8); XCTAssertEqual(spec.wings.sides.count, 2); XCTAssertEqual(spec.hop.keyframes.count, 11)
        let body = WearBody.shared
        var worst = (0.0, "")
        var placements: [(JellyFeature, FeatureMeshes.Placement)] = [(.spines, FeatureMeshes.Placement()), (.daisy, FeatureMeshes.Placement()), (.wings, FeatureMeshes.Placement())]
        var hat = FeatureMeshes.Placement(); hat.onHat = true; hat.anchor = SIMD3(0, 1.3875, 0); hat.sink = 0.06
        placements.append((.daisy, hat))
        for (f, pl) in placements {
            let t0 = CFAbsoluteTimeGetCurrent()
            guard let p = FeatureMeshes.prepare(f, placement: pl, body: body) else { XCTFail("\(f) did not load"); continue }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if ms > worst.0 { worst = (ms, p.art) }
            XCTAssertLessThanOrEqual(p.rest.count, FeatureMeshes.vertexBudget, p.art)
            XCTAssertLessThanOrEqual(p.triangles, FeatureMeshes.triangleBudget, p.art)
            XCTAssertEqual(p.rest.count, spec.meshes[p.art]?.vertices, "\(p.art) matches the converter's table")
            XCTAssertEqual(p.triangles, spec.meshes[p.art]?.triangles, p.art)
            XCTAssertEqual(p.parts.map(\.name), spec.meshes[p.art]?.parts ?? [], p.art)
            XCTAssertFalse(p.rest.contains { $0.x.isNaN })
            for part in p.parts where part.bind.tri != .zero {
                XCTAssertLessThan(simd_distance(body.restPoint(part.bind), part.pivot), 2e-3, "\(p.art) \(part.name): the pivot binds where it was authored")
            }
        }
        for v in ["beanie_honey_nopom", "beanie_pink_nopom", "cap_team_pink_nobutton", "cap_team_sky_nobutton", "party_hat_nopom", "party_hat_short"] {
            guard let a = WearMeshes.art(v) else { XCTFail("variant \(v) did not load"); continue }
            XCTAssertLessThanOrEqual(a.triangles, WearMeshes.triangleBudget, v)
            XCTAssertFalse(a.parts.contains { $0.name == "pom" || $0.name == "button" }, "\(v): the ornament is gone")
        }
        MotionLog.write(String(format: "FEATURE load+bind worst %.1f ms (%@)", worst.0, worst.1))
        XCTAssertLessThan(worst.0, 600)
    }

    func testRosterHasFourStartersWithFeatures() {
        XCTAssertEqual(JellyRoster.maxCount, 4)
        XCTAssertEqual(JellyRoster.names, ["Bob", "Pip", "Moss", "Lavender"])
        XCTAssertEqual((0..<4).map { JellyRoster.feature($0) }, [.none, .spines, .daisy, .wings])
        XCTAssertEqual(JellyRoster.spawnSpots(count: 4).count, 4)
        XCTAssertNotNil(JellyRoster.palette(3))
        XCTAssertEqual(JellyRoster.selectBlobs(count: 4).count, 4)
        XCTAssertNotNil(JellyNameRoster.name(3))
        let care = GameCare(jellyCount: 4, persistent: false)
        Self.keep.append(care)
        XCTAssertEqual(care.jellyCount, 4)
        XCTAssertEqual(care.jelly(3)?.feature, .wings)
        // the widget snapshot: the feature field is optional in old files
        let old = #"{"version":1,"savedAt":1,"jellies":[{"id":1,"name":"Pip","color":"yellow","levels":[1,1,1],"dirt":0,"sparkle":0,"mood":"okay"}]}"#
        let snap = try? JSONDecoder().decode(JellySnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(snap?.jellies.first?.feature, "")
        XCTAssertEqual(WidgetBridge.colorName(3), "lavender")
    }

    // MARK: the mouth keep-out

    static func ellipse(_ p: SIMD3<Float>) -> Float { let x = p.x / 0.15, y = (p.y - 0.651) / 0.10; return x * x + y * y }

    func testNoFeatureVertexInsideTheMouthKeepOutAcrossPoses() {
        let spec = FeatureSpec.shared
        var slots: [(String, FeatureSet.Slot)] = []
        for f in Self.features {
            for sq: Float in [1, 0.76, 1.08] { slots.append(("\(f) rest squash \(sq)", Self.restSlot(f, squash: sq))) }
        }
        for flap in stride(from: Float(-40), through: 75, by: 23) { slots.append(("wings flap \(flap)", Self.restSlot(.wings, flap: flap, spread: min(40, 0.4 * max(flap, 0))))) }
        for dy: Float in [-0.2, 0.16] { var fit = FeatureFit(); fit.wingDY = dy; slots.append(("wings dy \(dy)", Self.restSlot(.wings, fit: fit, flap: 75, spread: 30))) }
        slots.append(("daisy closed", Self.restSlot(.daisy, close: 1)))
        for (w, p) in spec.pairs where p.moss.rule == "adjust" {
            let fit = FeatureCompat.solve(.daisy, worn: [w])
            slots.append(("daisy on \(w)", Self.restSlot(.daisy, fit: fit)))
            slots.append(("daisy on \(w) closed", Self.restSlot(.daisy, fit: fit, close: 1)))
        }
        for (name, s) in slots {
            guard let (m, _) = Self.mesh(s) else { XCTFail(name); continue }
            XCTAssertGreaterThan(m.vertices.count, 100, name)
            var bad = 0
            for v in m.vertices where v.pos.z > 0.15 && Self.ellipse(SIMD3(v.pos.x, v.pos.y, v.pos.z)) < 1 { bad += 1 }
            XCTAssertEqual(bad, 0, "\(name): \(bad) vertices on the mouth")
            // and nothing over the eyes / brows band in front
            let front = m.vertices.filter { $0.pos.z > 0.3 && $0.pos.y > 0.75 && $0.pos.y < 1.05 && abs($0.pos.x) < 0.3 }.count
            XCTAssertEqual(front, 0, "\(name): \(front) vertices over the face")
        }
    }

    // MARK: compat

    /// A wearable's triangles in a uniform grid: segment / triangle crossings ("pierces") and nearest-surface distances. Hats are open shells, so an
    /// inside test is meaningless; a feature that CROSSES a wearable surface is the thing the eye catches.
    final class TriSoup {
        let pos: [SIMD3<Float>], idx: [UInt32]
        let lo: SIMD3<Float>, cell: Float = 0.06, dim: SIMD3<Int>
        var grid: [[Int32]]
        init(_ pos: [SIMD3<Float>], _ idx: [UInt32]) {
            self.pos = pos; self.idx = idx
            var mn = SIMD3<Float>(repeating: .infinity), mx = SIMD3<Float>(repeating: -.infinity)
            for p in pos { mn = simd_min(mn, p); mx = simd_max(mx, p) }
            lo = mn - 0.01
            let d = simd_max(SIMD3<Float>(repeating: 1), ((mx + 0.01 - lo) / cell).rounded(.up))
            dim = SIMD3(Int(d.x), Int(d.y), Int(d.z))
            grid = [[Int32]](repeating: [], count: dim.x * dim.y * dim.z)
            var t = 0
            while t + 2 < idx.count {
                let a = pos[Int(idx[t])], b = pos[Int(idx[t + 1])], c = pos[Int(idx[t + 2])]
                let i0 = cellOf(simd_min(a, simd_min(b, c))), i1 = cellOf(simd_max(a, simd_max(b, c)))
                for z in i0.z...i1.z { for y in i0.y...i1.y { for x in i0.x...i1.x { grid[(z * dim.y + y) * dim.x + x].append(Int32(t / 3)) } } }
                t += 3
            }
        }
        func cellOf(_ q: SIMD3<Float>) -> SIMD3<Int> {
            let f = ((q - lo) / cell).rounded(.down)
            return SIMD3(min(max(Int(f.x), 0), dim.x - 1), min(max(Int(f.y), 0), dim.y - 1), min(max(Int(f.z), 0), dim.z - 1))
        }
        /// Does segment ab cross any triangle? Returns the crossing point and the triangle normal.
        func pierce(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> (x: SIMD3<Float>, n: SIMD3<Float>)? {
            let mn = simd_min(a, b), mx = simd_max(a, b)
            if any(mx .< lo) || any(mn .> lo + SIMD3(Float(dim.x), Float(dim.y), Float(dim.z)) * cell) { return nil }
            let i0 = cellOf(mn), i1 = cellOf(mx)
            let d = b - a
            var seen = Set<Int32>()
            for z in i0.z...i1.z { for y in i0.y...i1.y { for x in i0.x...i1.x {
                for ti in grid[(z * dim.y + y) * dim.x + x] where seen.insert(ti).inserted {
                    let t = Int(ti) * 3
                    let p0 = pos[Int(idx[t])], p1 = pos[Int(idx[t + 1])], p2 = pos[Int(idx[t + 2])]
                    let e1 = p1 - p0, e2 = p2 - p0
                    let pv = simd_cross(d, e2), det = simd_dot(e1, pv)
                    if abs(det) < 1e-12 { continue }
                    let inv = 1 / det, tv = a - p0
                    let u = simd_dot(tv, pv) * inv
                    if u < 0 || u > 1 { continue }
                    let qv = simd_cross(tv, e1)
                    let v = simd_dot(d, qv) * inv
                    if v < 0 || u + v > 1 { continue }
                    let s = simd_dot(e2, qv) * inv
                    if s > 1e-5 && s < 1 - 1e-5 { return (a + d * s, simd_normalize(simd_cross(e1, e2))) }
                }
            } } }
            return nil
        }
        func distance(_ p: SIMD3<Float>) -> Float {
            var best = Float.infinity, t = 0
            while t + 2 < idx.count {
                let w = WearBody.closest(p, pos[Int(idx[t])], pos[Int(idx[t + 1])], pos[Int(idx[t + 2])])
                let q = pos[Int(idx[t])] * w.x + pos[Int(idx[t + 1])] * w.y + pos[Int(idx[t + 2])] * w.z
                best = min(best, simd_distance(p, q)); t += 3
            }
            return best
        }
    }

    func testCompatRulesHoldForEveryWearable() {
        let body = WearBody.shared
        // a grazing contact up to 2 cm passes; the on-hat flower head may rest its lower petals into the hat tip by 3.5 cm (it "sits on the tip" by design:
        // the lab's daisy_xf placements for the party hat / top hat were approved like that; the petals are thin and the dip is behind the flower face)
        let tol: Float = 0.02, tolOnHat: Float = 0.035
        var rows: [String] = []
        for look in WearLook.pieces where !WearRules.isArm(look) {
            for f in Self.features {
                let fit = FeatureCompat.solve(f, worn: [look.art])
                if fit.hidden { rows.append("\(look.art) + \(f): hidden"); continue }
                guard let wp = WearMeshes.prepare(look, body: body, art: fit.hatVariant[look.art]) else { XCTFail("\(look)"); continue }
                let soup = TriSoup(wp.rest, wp.idx)
                var poses: [(String, FeatureSet.Slot)] = [("rest", Self.restSlot(f, fit: fit))]
                if f == .wings && !fit.folded {
                    for k in 0...4 {
                        let flap = fit.flapMin + (fit.flapMax - fit.flapMin) * Float(k) / 4
                        poses.append(("flap \(Int(flap))", Self.restSlot(f, fit: fit, flap: flap, spread: min(fit.spreadMax, 0.4 * max(flap, 0)))))
                    }
                }
                if f == .daisy { poses.append(("closed", Self.restSlot(f, fit: fit, close: 1))) }
                // every feature edge that CROSSES the wearable's surface is a pierce; its depth = how far the deeper end sits past the surface. The stem
                // (and on a hat the leaves at its root) are sunk into the hat by design; hidden spines are not drawn.
                var worstDepth: Float = 0, worstPose = "", pierces = 0, deep = 0
                for (pn, s) in poses {
                    guard let (m, p) = Self.mesh(s) else { continue }
                    var t = 0
                    while t + 2 < m.indices.count {
                        let ids = [m.indices[t], m.indices[t + 1], m.indices[t + 2]]
                        t += 3
                        let part = p.parts[p.partOfVertex[Int(ids[0])]]
                        if part.name == "stem" || (fit.onHat && part.name.hasPrefix("leaf")) { continue }
                        if fit.hiddenParts.contains(part.name) { continue }
                        for e in 0..<3 {
                            let a = m.vertices[Int(ids[e])].pos, b = m.vertices[Int(ids[(e + 1) % 3])].pos
                            let pa = SIMD3(a.x, a.y, a.z), pb = SIMD3(b.x, b.y, b.z)
                            guard let hit = soup.pierce(pa, pb) else { continue }
                            pierces += 1
                            let depth = max(abs(simd_dot(pa - hit.x, hit.n)), abs(simd_dot(pb - hit.x, hit.n)))
                            if depth > (fit.onHat ? tolOnHat : tol) { deep += 1 }
                            if depth > worstDepth { worstDepth = depth; worstPose = pn + " " + part.name }
                        }
                    }
                }
                rows.append(String(format: "%@ + %@: %@ pierces %d (deeper than %.2f: %d) worst %.3f (%@)", look.art, "\(f)", fit.folded ? "FOLDED" : (fit.onHat ? "on-hat" : "fit"), pierces, tol, deep, worstDepth, worstPose))
                XCTAssertEqual(deep, 0, "\(look.art) + \(f): the feature pierces the wearable deeper than \(tol) (worst \(worstDepth) at \(worstPose))")
            }
        }
        for r in rows { MotionLog.write("FEATURECOMPAT " + r) }
    }

    func testCompatSolverMatchesTheArtLabExamples() {
        let spec = FeatureSpec.shared
        // (work/wingsolve.py today: beanie + scarf -> dy -0.08, flap [-5, 25]; the compat.json example text predates the scarf table)
        let a = FeatureCompat.solveWings(["beanie_honey", "scarf_sky"], spec: spec)
        XCTAssertEqual(a?.dy, -0.08); XCTAssertEqual(a?.lo, -5); XCTAssertEqual(a?.hi, 25)
        let cb = FeatureCompat.solveWings(["cape_hero", "beanie_pink"], spec: spec)
        XCTAssertEqual(cb?.dy, 0.08); XCTAssertEqual(cb?.lo, -5); XCTAssertEqual(cb?.hi, 15)
        XCTAssertNil(FeatureCompat.solveWings(["cape_hero", "bucket_hat"], spec: spec), "nothing fits: the wings fold")
        let c = FeatureCompat.solveWings(["tophat", "scarf_cosy"], spec: spec)
        XCTAssertEqual(c?.dy, 0); XCTAssertEqual(c?.lo, -35); XCTAssertEqual(c?.hi, 75)
        let fold = FeatureCompat.solve(.wings, worn: ["cape_hero", "bucket_hat"])
        XCTAssertTrue(fold.folded); XCTAssertEqual(fold.flapMax, 0)
        let free = FeatureCompat.solve(.wings, worn: ["glasses_round"])
        XCTAssertFalse(free.folded); XCTAssertEqual(free.flapMax, 75); XCTAssertEqual(free.wingDY, 0)
        let beanie = FeatureCompat.solve(.wings, worn: ["beanie_honey"])
        XCTAssertEqual(beanie.wingDY, -0.12); XCTAssertEqual(beanie.flapMax, 30); XCTAssertEqual(beanie.spreadMax, 12)
        // Pip: the union of the hidden spines; Moss: the on-hat sprout and the hat variant; the ring / clip group leaves the sprout alone
        XCTAssertEqual(FeatureCompat.solve(.spines, worn: ["cat_ears", "sweatband"]).hiddenParts, ["spike_01", "spike_05", "spike_06"])
        let moss = FeatureCompat.solve(.daisy, worn: ["beanie_honey", "bowtie_pink"])
        XCTAssertTrue(moss.onHat); XCTAssertEqual(moss.hatVariant["beanie_honey"], "beanie_honey_nopom"); XCTAssertEqual(moss.anchor.y, 1.3698, accuracy: 1e-4)
        let chef = FeatureCompat.solve(.daisy, worn: ["chef_hat"])
        XCTAssertEqual(chef.tilt, 50); XCTAssertEqual(chef.sink, 0.1); XCTAssertNil(chef.hatVariant["chef_hat"])
        XCTAssertFalse(FeatureCompat.solve(.daisy, worn: ["flower_crown"]).onHat)
        XCTAssertTrue(FeatureCompat.solve(.daisy, worn: ["propeller_beanie"]).hidden)
        // the variant hats are only for Moss
        XCTAssertTrue(FeatureCompat.solve(.spines, worn: ["beanie_honey"]).hatVariant.isEmpty)
        XCTAssertTrue(FeatureCompat.solve(.wings, worn: ["party_hat"]).hatVariant.isEmpty)
    }

    // MARK: the flap-hop

    func testFlapHopCompletesLandsWithFeetAttachedAndArmsCapped() {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.renderSamples = false
        r.brain.feature = .wings; r.brain.idleForced = true; r.brain.seed = 11; r.brain.amplitude = 1
        let restY = r.sim.centroid().y
        XCTAssertTrue(r.brain.idleStart(.flapHop, r.sim))
        XCTAssertEqual(r.brain.idleState.kind, .flapHop)
        var maxLift: Float = 0, maxFlap: Float = -1e9, minFlap: Float = 1e9, maxDrift: Float = 0
        var w = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), frames = 0
        var armMax = 0.0, armFrames = 0
        let start = r.root
        r.run(6, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            let c = r.sim.centroid()
            maxLift = max(maxLift, c.y - restY)
            maxDrift = max(maxDrift, simd_distance(r.root, start))
            if r.brain.flapHop.active { maxFlap = max(maxFlap, r.brain.flapHop.flapDeg); minFlap = min(minFlap, r.brain.flapHop.flapDeg) }
            if let f = FeetAttachTests.footFrame(r) { FeetAttachTests.accumulate(&w, f); frames += 1 }
            if r.brain.armG > 0.5 {
                for si in 0..<2 { let g = r.brain.armLastGeom[si]; armMax = max(armMax, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2))); armFrames += 1 }
            }
        }
        MotionLog.write(String(format: "FLAPHOP lift max %.3f drift %.3f flap %.0f...%.0f bean frames %d arm max %.4f (%d frames) end t %.2f", maxLift, maxDrift, minFlap, maxFlap, frames, armMax, armFrames, r.t))
        XCTAssertNil(r.brain.idleState.kind, "the hop ended")
        XCTAssertFalse(r.brain.flapHop.active)
        XCTAssertEqual(r.brain.flapHop.count, 1)
        XCTAssertGreaterThanOrEqual(maxLift, 0.25, "he got into the air")
        XCTAssertLessThanOrEqual(maxLift, 0.40, "and not too high")
        XCTAssertGreaterThan(maxDrift, 0.4, "he drifted forward")
        XCTAssertGreaterThan(maxFlap, 40); XCTAssertLessThan(minFlap, -10)
        XCTAssertLessThanOrEqual(maxFlap, 75.5); XCTAssertGreaterThanOrEqual(minFlap, -40.5)
        for _ in 0..<60 { r.tick() }
        XCTAssertLessThan(abs(r.sim.centroid().y - restY), 0.04, "he landed on the floor")
        XCTAssertLessThan(r.groundGap, 0.02, "the feet are on the floor")
        XCTAssertGreaterThan(frames, 60, "the beans were out in the air")
        FeetAttachTests.check("flap-hop", w, frames: frames)
        XCTAssertLessThanOrEqual(armMax, ArmCap.maximum * 1.02, "the arms stay stubby")
    }

    func testFlapHopGatesAndFoldedFallback() {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.idleForced = true
        XCTAssertFalse(r.brain.idleStart(.flapHop, r.sim), "no wings: no flap-hop")
        XCTAssertNil(r.brain.idleState.kind)
        r.brain.feature = .wings
        XCTAssertTrue(r.brain.flapHopAllowed)
        r.brain.idleMood = .grumpy; XCTAssertFalse(r.brain.flapHopAllowed); r.brain.idleMood = .happy
        r.brain.idleNight = 0.8; XCTAssertFalse(r.brain.flapHopAllowed); r.brain.idleNight = 0
        r.brain.sleepLocked = true; XCTAssertFalse(r.brain.flapHopAllowed); r.brain.sleepLocked = false
        r.brain.reserved = true; XCTAssertFalse(r.brain.flapHopAllowed); r.brain.reserved = false
        XCTAssertTrue(r.brain.flapHopAllowed)
        XCTAssertTrue(BlobBrain.fastKinds.contains(.flapHop))
        r.brain.kindCooldownStart(.flapHop)
        XCTAssertTrue(r.brain.kindCooling.contains(.flapHop))
        // folded wings: the plain happy bounce instead, one hop
        r.brain.wingsFolded = true
        XCTAssertTrue(r.brain.idleStart(.flapHop, r.sim))
        XCTAssertEqual(r.brain.idleState.kind, .bounce)
        XCTAssertFalse(r.brain.flapHop.active)
        var maxLift: Float = 0
        let restY = r.sim.centroid().y
        r.run(4, until: { r.brain.idleState.kind == nil }) { maxLift = max(maxLift, r.sim.centroid().y - restY) }
        XCTAssertNil(r.brain.idleState.kind)
        XCTAssertLessThan(maxLift, 0.25, "a plain hop, not a flight")
        // a yield (held) mid-flight ends it cleanly
        r.brain.wingsFolded = false
        XCTAssertTrue(r.brain.idleStart(.flapHop, r.sim))
        r.run(1.0)
        XCTAssertTrue(r.brain.flapHop.active)
        r.brain.reserved = true
        r.run(0.5)
        XCTAssertFalse(r.brain.flapHop.active); XCTAssertNil(r.brain.idleState.kind)
        r.brain.reserved = false
        for _ in 0..<90 { r.tick() }
        XCTAssertLessThan(r.groundGap, 0.03)
    }

    func testFlapHopUrgeStartsItOnItsOwnWhenAllowed() {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.feature = .wings; r.brain.autonomy = true; r.brain.anticsEnabled = true; r.brain.idleMood = .happy
        r.brain.idleState.cooldown = 0; r.brain.restTimer = 0; r.brain.zoomUrge = 1e6
        r.brain.flapHop.urge = 0.5
        var started = false
        r.run(30, until: { r.brain.flapHop.count > 0 }) { if r.brain.idleState.kind == .flapHop { started = true } }
        XCTAssertTrue(started, "the urge started a flap-hop")
        XCTAssertGreaterThanOrEqual(r.brain.flapHop.urge, 20, "and re-armed for 25...40 s")
    }

    // MARK: hide rules

    func testFeaturesHideInTheWashAndSpinesWingsOffWhileLyingDaisyCloses() {
        let r = MotionRig(game: true)
        Self.keep.append(r)
        let f = FeatureSet(); f.body = WearBody.shared; Self.keep.append(f)
        for id in 1...3 { f.tick(id: id, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: [], hideAll: false, dt: 1.0 / 60) }
        for id in 1...3 { XCTAssertEqual(f.shown(id), JellyRoster.feature(id)) }
        let m = [Float](repeating: 0, count: 1)
        let mesh = m.withUnsafeBufferPointer { _ in f.frame { _ in nil } }
        XCTAssertGreaterThan(mesh.vertices.count, 1800, "three features drawn")
        XCTAssertEqual(f.lastBounds.count, 3)
        for id in 1...3 { f.tick(id: id, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: [], hideAll: true, dt: 1.0 / 60) }
        XCTAssertFalse(f.anyShown, "the wash hides everything")
        // lying on his back: spines and wings poof off, the daisy stays and closes
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim)); r.brain.sleep.hold = 500
        r.run(40, until: { r.brain.isNapping })
        XCTAssertTrue(r.brain.isNapping)
        for _ in 0..<120 { for id in 1...3 { f.tick(id: id, brain: r.brain, sim: r.sim, feature: JellyRoster.feature(id), worn: [], hideAll: false, dt: 1.0 / 60) } }
        XCTAssertNil(f.shown(1)); XCTAssertNil(f.shown(3)); XCTAssertEqual(f.shown(2), .daisy)
        XCTAssertGreaterThan(f.slot(2)?.close ?? 0, 0.9, "the daisy closed")
        // a hat hides the head-zone spines (and they come back when the hat goes)
        f.tick(id: 1, brain: r.brain, sim: r.sim, feature: .spines, worn: ["party_hat"], hideAll: false, dt: 1.0 / 60)
        XCTAssertEqual(f.slot(1)?.fit.hiddenParts, ["spike_00", "spike_01", "spike_02", "spike_03"])
        f.tick(id: 1, brain: r.brain, sim: r.sim, feature: .spines, worn: [], hideAll: false, dt: 1.0 / 60)
        XCTAssertTrue(f.slot(1)?.fit.hiddenParts.isEmpty ?? false)
    }
}
