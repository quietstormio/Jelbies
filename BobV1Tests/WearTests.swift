//
//  WearTests.swift
//  The Blender wardrobe: every piece loads within budget, binds to the rest surface and lands where it was authored, never covers the mouth (at rest AND on
//  the posed, squashed, chomping body), hides by its rules, the old saves still decode, the jersey band stays clear of the mouth.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WearTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    // MARK: rig

    func room(_ n: Int = 3) -> (GameCare, [JellyActor]) {
        let sm = MotionRig.simMesh, rm = MotionRig.renderMesh
        let emb = embed(simRest: sm.rest, tets: sm.tets, verts: rm.rest)
        let care = GameCare(jellyCount: n, persistent: false)
        let spots = JellyRoster.spawnSpots(count: n)
        let actors: [JellyActor] = (0..<n).map {
            let a = JellyActor(id: $0, name: JellyRoster.names[$0], simMesh: sm, renderMesh: rm, embedding: emb, appearance: .berry, firmness: 0.95, damping: 0.45, spawn: spots[$0])
            a.profile = care.jelly($0); a.care = care
            a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
            a.reset(drop: 0.35, shift: true)
            let b = BlobBrain.forGame()
            b.attach(renderMesh: rm, synchronous: true)
            b.autonomy = false; b.steerID = $0
            care.wireWorld(b, isBob: $0 == 0)
            a.brain = b
            for _ in 0..<200 { a.sim.step() }
            b.currentPose(a.sim)
            return a
        }
        WearBody.install(rm)
        Self.keep += actors; Self.keep.append(care)
        return (care, actors)
    }

    /// 6 floats per render vertex: the skinned body as the renderer would draw it.
    func skin(_ a: JellyActor) -> [Float] {
        var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
        a.skinner.update(x: a.sim.x, index: MotionRig.renderMesh.index, into: &d)
        return d
    }

    func frame(_ w: WornSet, skin s: [Float]?, hidden: Bool = false) -> RoomMesh {
        let arr = s ?? []
        return arr.withUnsafeBufferPointer { p in
            w.frame(theme: RoomTheme(), hidden: hidden, time: 0.3) { _ in s == nil ? nil : p.baseAddress }.opaque
        }
    }

    static func ellipse(_ p: SIMD3<Float>) -> Float {
        let x = (p.x - 0) / 0.15, y = (p.y - 0.651) / 0.10
        return x * x + y * y
    }

    // MARK: data

    func testOldSavesStillDecodeAndUnknownLooksAreNil() throws {
        let json = #"{"counts":{"fries":2},"pages":[],"wearables":["sneakerMint","someFutureHat"],"worn":{"0":{"feet":"sneakerMint","head":"someFutureHat"}},"starterGiven":true,"newItems":1,"placed":[]}"#
        let saved = try JSONDecoder().decode(StoreBook.Saved.self, from: Data(json.utf8))
        XCTAssertNil(saved.awarded)
        let w = DropsWallet(persists: false)
        let d = UserDefaults(suiteName: "WearTests.old")!
        d.removePersistentDomain(forName: "WearTests.old")
        d.set(Data(json.utf8), forKey: "k")
        let b = StoreBook(wallet: w, persists: true, defaults: d, key: "k")
        Self.keep.append(b)
        XCTAssertEqual(b.worn(0, .feet), .sneakerMint)
        XCTAssertNil(b.worn(0, .head), "a look this build does not know reads as nothing")
        XCTAssertEqual(b.count("fries"), 2)
    }

    func testCatalogHasEveryLookAndTheMedalIsNotSold() {
        for l in WearLook.allCases where !WearLook.unlisted.contains(l) { XCTAssertNotNil(StoreCatalog.item(wearing: l), "\(l)") }
        for l in WearLook.unlisted { XCTAssertNil(StoreCatalog.item(wearing: l), "\(l) is out of the shop") }
        let medal = StoreCatalog.item(wearing: .medalGold)!
        XCTAssertTrue(medal.awarded)
        XCTAssertFalse(ShopTab.wear.items.contains { $0.awarded })
        let w = DropsWallet(persists: false); w.add(500, silent: true)
        let b = StoreBook(wallet: w, persists: false); Self.keep.append(b)
        XCTAssertEqual(b.buy(medal.id), .unknown)
        XCTAssertFalse(b.ownsLook(.medalGold))
        XCTAssertTrue(b.awardMedal()); XCTAssertFalse(b.awardMedal())
        XCTAssertTrue(b.wear(.medalGold, on: 0)); XCTAssertEqual(b.worn(0, .neck), .medalGold)
        for t in WearTag.allCases { XCTAssertTrue(WearLook.allCases.contains { $0.tags.contains(t) }, "\(t)") }
        XCTAssertEqual(Set(WearSlot.allCases).count, 6)
    }

    /// The hoodie / raincoat are unlisted: an owner has them taken off and gets the price back, exactly once.
    func testUnlistedCoatsAreRefundedOnce() throws {
        let suite = "WearTests.unlisted.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { d.removePersistentDomain(forName: suite) }
        var saved = StoreBook.Saved()
        saved.wearables = [WearLook.hoodie.rawValue, WearLook.raincoat.rawValue, WearLook.beret.rawValue]
        saved.worn = ["0": ["body": WearLook.hoodie.rawValue, "head": WearLook.beret.rawValue]]
        d.set(try JSONEncoder().encode(saved), forKey: StoreBook.key)
        let w = DropsWallet(persists: false)
        let before = w.count
        let b = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b)
        XCTAssertEqual(w.count - before, 65 + 60)
        XCTAssertFalse(b.ownsLook(.hoodie)); XCTAssertFalse(b.ownsLook(.raincoat)); XCTAssertTrue(b.ownsLook(.beret))
        XCTAssertNil(b.saved.worn["0"]?["body"]); XCTAssertEqual(b.saved.worn["0"]?["head"], WearLook.beret.rawValue)
        let b2 = StoreBook(wallet: w, persists: true, defaults: d); Self.keep.append(b2)
        XCTAssertEqual(w.count - before, 65 + 60, "a second load never pays twice")
    }

    // MARK: art

    func testEveryWearableLoadsWithinBudget() {
        let body = WearBody.shared
        var worst = (0.0, "")
        for l in WearLook.pieces {
            let t0 = CFAbsoluteTimeGetCurrent()
            guard let p = WearMeshes.prepare(l, body: body) else { XCTFail("\(l) did not load"); continue }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            if ms > worst.0 { worst = (ms, l.rawValue) }
            XCTAssertLessThanOrEqual(p.rest.count, WearMeshes.vertexBudget, "\(l)")
            XCTAssertLessThanOrEqual(p.triangles, WearMeshes.triangleBudget, "\(l)")
            XCTAssertGreaterThan(p.triangles, 50, "\(l)")
            XCTAssertEqual(p.rest.count, l.row.vertices, "\(l) matches the generated table")
            XCTAssertFalse(p.rest.contains { $0.x.isNaN })
        }
        for n in 0..<10 { XCTAssertNotNil(WearMeshes.art("digit_\(n)")) }
        MotionLog.write(String(format: "WEAR load+bind worst %.1f ms (%@) of %d pieces", worst.0, worst.1, WearLook.pieces.count))
        XCTAssertLessThan(worst.0, 600)
    }

    func testBindsLandWhereTheyWereAuthored() {
        let body = WearBody.shared
        for l in WearLook.pieces where !WearRules.isArm(l) {
            guard let p = WearMeshes.prepare(l, body: body) else { continue }
            var worst: Float = 0
            for i in p.rest.indices where p.w[i] > 0.001 { worst = max(worst, simd_distance(body.restPoint(p.bind[i]), p.rest[i])) }
            XCTAssertLessThan(worst, 2e-3, "\(l): a bound vertex must land on its authored position at rest")
        }
    }

    func testNoWearableVertexIsInsideTheMouthKeepOutAtRest() {
        let body = WearBody.shared
        for l in WearLook.pieces where !WearRules.isArm(l) {
            guard let p = WearMeshes.prepare(l, body: body) else { continue }
            for (i, r) in p.rest.enumerated() where r.z > 0.15 {
                XCTAssertGreaterThanOrEqual(Self.ellipse(r), 1.0, "\(l) vertex \(i) at \(r) is on the mouth")
            }
        }
        for t in [WearTeam.sky, .pink, .coral] {
            guard let b = WearMeshes.bib(team: t, number: 21, body: body) else { XCTFail("bib"); continue }
            XCTAssertLessThan(b.rest.map(\.y).max()!, 0.51, "the bib stays under the jersey band top")
            for r in b.rest where r.z > 0.15 { XCTAssertGreaterThanOrEqual(Self.ellipse(r), 1.0) }
        }
    }

    func testTheJerseyBandStaysBelowTheMouth() {
        let p = MelonRenderer.jerseyParams(.sky)
        XCTAssertLessThanOrEqual(p.4.y, 0.51)
        XCTAssertEqual(p.4.x, 0.22, accuracy: 1e-6)
        // the band's soft edge (+softness) must still end below the keep-out ellipse bottom (0.551)
        XCTAssertLessThan(p.4.y + p.4.z, 0.551)
    }

    // MARK: rules

    func testHideRulesAndPoofs() {
        let (_, actors) = room(1)
        let a = actors[0], b = a.brain!
        let w = WornSet(); w.body = WearBody.shared; Self.keep.append(w)
        w.soundOn = false
        let outfit: [WearSlot: WearLook] = [.head: .tophat, .face: .sunglassesStar, .neck: .bowtieSky, .hands: .gloveSky, .body: .capeHero]
        func tick(_ n: Int = 1, hideAll: Bool = false) { for _ in 0..<n { w.tick(id: 0, brain: b, sim: a.sim, outfit: outfit, role: .none, hideAll: hideAll, dt: 1.0 / 60) } }
        tick(2)
        for (s, l) in outfit { XCTAssertEqual(w.shown(0, s), l, "\(l) is on") }
        // the wash hides everything at once
        tick(1, hideAll: true)
        for s in outfit.keys { XCTAssertNil(w.shown(0, s)) }
        tick(30)
        for (s, l) in outfit { XCTAssertEqual(w.shown(0, s), l) }
        // asleep: hats and face items off with a poof; neck / hands / body stay
        b.idleForced = true; _ = b.idleStart(.sleep, a.sim)
        b.sleep.stage = 3
        XCTAssertTrue(WornSet.sleepHides(b))
        tick(40)
        XCTAssertNil(w.shown(0, .head)); XCTAssertNil(w.shown(0, .face))
        XCTAssertNotNil(w.shown(0, .neck)); XCTAssertNotNil(w.shown(0, .hands))
        XCTAssertGreaterThan(w.poofOuts, 0); XCTAssertGreaterThan(w.puffSpawns, 0)
        // waking (past half of the roll back): they pop back
        b.sleep.stage = 4; b.sleep.t = SleepTuning.rollBackTime * 0.8
        tick(40)
        XCTAssertEqual(w.shown(0, .head), .tophat); XCTAssertEqual(w.shown(0, .face), .sunglassesStar)
        b.idleState.kind = nil
        // the eye mask and a hat are never both out
        XCTAssertFalse(SleepMaskSet.wanted(b) && w.shown(0, .head) != nil)
        // hide flags
        for l in WearLook.allCases { XCTAssertFalse(WearRules.hide(l).contains(.eating), "\(l) stays on while he eats or drinks") }
        // eating / drinking: heart shades + beanie stay on and fully scaled
        let drinkFit: [WearSlot: WearLook] = [.head: .beaniePink, .face: .heartShades]
        b.script = .eat(t: 0.5, bowl: SIMD2(0, 0), dur: 3, drink: true)
        XCTAssertTrue(WornSet.eating(b))
        for _ in 0..<40 { w.tick(id: 0, brain: b, sim: a.sim, outfit: drinkFit, role: .none, hideAll: false, dt: 1.0 / 60) }
        XCTAssertEqual(w.shown(0, .face), .heartShades); XCTAssertEqual(w.shown(0, .head), .beaniePink)
        XCTAssertTrue(WearRules.hide(.capeHero).contains(.flip))
        for l in WearLook.allCases { XCTAssertTrue(WearRules.hide(l).contains(.wash), "\(l) hides in the wash") }
        for l in WearLook.looks(.head) + WearLook.looks(.face) { XCTAssertTrue(WearRules.hide(l).contains(.asleep), "\(l)") }
    }

    // MARK: mouth, posed

    /// The body is posed (squashed, tipped) and chomping at mouthOpen 1: no worn vertex sits in front of the part of the skin the mouth is drawn on.
    func testNoWearableCoversTheMouthOnAPosedSquashedBody() {
        let (_, actors) = room(1)
        let a = actors[0]
        let rm = MotionRig.renderMesh
        let body = WearBody.shared
        var checked = 0
        for (squash, pitch) in [(Float(1), Float(0)), (0.82, 0.25), (1.08, -0.2)] {
            a.sim.attractor.squash = squash
            a.sim.attractor.rotation = simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
            for _ in 0..<90 { a.sim.step() }
            a.brain?.currentPose(a.sim)
            let sk = skin(a)
            // the skin patch the mouth decal is drawn on (rest Q in the ellipse, grown a little for the open mouth)
            var patch: [Int] = []
            for (ti, t) in body.tris.enumerated() {
                let q = [t.x, t.y, t.z].map { body.pos[Int($0)] }
                if q.contains(where: { $0.z > 0.15 && Self.ellipse($0) < 1.6 }) { patch.append(ti) }
            }
            XCTAssertFalse(patch.isEmpty)
            func P(_ i: UInt32) -> SIMD3<Float> { SIMD3(sk[6 * Int(i)], sk[6 * Int(i) + 1], sk[6 * Int(i) + 2]) }
            for l in WearLook.pieces where !WearRules.isArm(l) {
                let w = WornSet(); w.body = body; w.soundOn = false; Self.keep.append(w)
                w.tick(id: 0, brain: a.brain!, sim: a.sim, outfit: [l.slot: l], role: .none, hideAll: false, dt: 1.0 / 60)
                let m = frame(w, skin: sk)
                XCTAssertFalse(m.vertices.isEmpty, "\(l)")
                for v in m.vertices {
                    let q = SIMD3(v.pos.x, v.pos.y, v.pos.z)
                    var best: (d: Float, tri: Int, w: SIMD3<Float>) = (.infinity, -1, .zero)
                    for ti in patch {
                        let t = body.tris[ti]
                        let bw = WearBody.closest(q, P(t.x), P(t.y), P(t.z))
                        let c = P(t.x) * bw.x + P(t.y) * bw.y + P(t.z) * bw.z
                        let d = simd_distance(q, c)
                        if d < best.d { best = (d, ti, bw) }
                    }
                    guard best.tri >= 0, best.d < 0.2 else { continue }
                    let t = body.tris[best.tri]
                    let rq = body.pos[Int(t.x)] * best.w.x + body.pos[Int(t.y)] * best.w.y + body.pos[Int(t.z)] * best.w.z
                    // in front of the mouth patch and over its drawn mouth
                    if rq.z > 0.15, Self.ellipse(rq) < 0.9 { XCTFail("\(l) covers the mouth (squash \(squash), pitch \(pitch)): rest point \(rq), \(best.d) in front"); break }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }

    // MARK: medal ribbon (W6)

    private func ribbonIndices(_ p: WearPrepared) -> [Int] {
        p.rest.indices.filter { p.partNames[Int(p.partOfVertex[$0])].hasPrefix("ribbon") }
    }

    /// The ribbon is a closed loop: every 15 degree wedge round the body axis holds ribbon, all of it surface-bound.
    func testMedalRibbonIsAClosedLoopAroundTheBody() {
        guard let p = WearMeshes.prepare(.medalGold, body: WearBody.shared) else { return XCTFail("medal did not load") }
        let rib = ribbonIndices(p)
        XCTAssertFalse(rib.isEmpty)
        var bins = [Int](repeating: 0, count: 24)
        for i in rib {
            XCTAssertEqual(p.w[i], 1, accuracy: 1e-6, "ribbon vertices follow the skin")
            let a = atan2(p.rest[i].z, p.rest[i].x)
            bins[min(23, Int((a + .pi) / (2 * .pi) * 24))] += 1
        }
        XCTAssertTrue(p.anyBound)
        for (k, n) in bins.enumerated() { XCTAssertGreaterThan(n, 0, "no ribbon in the \(k * 15 - 180)..\(k * 15 - 165) degree wedge") }
    }

    func testMedalRibbonClearsTheMouthAndTheShoulders() {
        guard let p = WearMeshes.prepare(.medalGold, body: WearBody.shared) else { return XCTFail("medal did not load") }
        for i in ribbonIndices(p) {
            let r = p.rest[i]
            if r.z > 0.15 { XCTAssertGreaterThanOrEqual(Self.ellipse(r), 1.0, "ribbon at \(r) is over the mouth") }
            if abs(r.x) > 0.45, r.z > -0.25 { XCTAssertGreaterThanOrEqual(r.y, 0.69, "ribbon at the side \(r) dips onto the arm root") }
            if abs(r.x) < 0.1, r.z < 0 { XCTAssertTrue((0.62...0.74).contains(r.y), "back-centre ribbon at height \(r.y)") }
        }
    }

    /// Through a walk, a run and a wave the posed arm capsules never poke the ribbon out (no ribbon vertex deeper than 1.5 cm inside a capsule).
    func testMedalRibbonStaysOutOfThePosedArms() {
        WearBody.install(MotionRig.renderMesh)
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.seed = 11; r.brain.amplitude = 1
        guard let p = WearMeshes.prepare(.medalGold, body: WearBody.shared) else { return XCTFail("medal did not load") }
        let rib = ribbonIndices(p)
        let w = WornSet(); w.body = WearBody.shared; w.soundOn = false; Self.keep.append(w)
        var samples = 0, deepest: Float = 0, worst = ""
        func sample() {
            guard r.brain.armG > 0.3 else { return }
            var d = [Float](repeating: 0, count: MotionRig.renderMesh.vertexCount * 6)
            r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &d)
            for _ in 0..<30 { w.tick(id: 0, brain: r.brain, sim: r.sim, outfit: [.neck: .medalGold], role: .none, hideAll: false, dt: 1.0 / 60) }
            let m = frame(w, skin: d)
            XCTAssertEqual(m.vertices.count, p.rest.count)
            guard m.vertices.count == p.rest.count else { return }
            for f in GameCare.armFrames(brain: r.brain, sim: r.sim) {
                let ab = f.b - f.a, L2 = simd_length_squared(ab)
                for i in rib {
                    let v = m.vertices[i].pos, q = SIMD3(v.x, v.y, v.z)
                    let t = L2 > 0 ? max(0, min(1, simd_dot(q - f.a, ab) / L2)) : 0
                    let r1 = Float(BobForm.armTopR)
                    let rad = r1 + (f.r2 - r1) * t
                    let inside = rad - simd_length(q - (f.a + ab * t))
                    if inside > deepest { deepest = inside; worst = "rest \(p.rest[i]) t \(t) a \(f.a) b \(f.b) r2 \(f.r2) armG \(r.brain.armG) blend \(r.brain.armBlendNow)" }
                }
            }
            samples += 1
        }
        r.brain.request(.goTo(SIMD2(1.6, 0.4)))
        r.run(5) { sample() }
        r.brain.request(.goTo(SIMD2(-1.2, 1.0)))
        r.run(4) { sample() }
        XCTAssertGreaterThan(samples, 20)
        XCTAssertLessThanOrEqual(deepest, 0.015, "a ribbon vertex is \(deepest) inside a posed arm: \(worst)")
    }

    // MARK: gloves

    /// Gloves follow the POSED arm capsule: through walking, a run and an idle the capsule still obeys the arm cap, and every glove vertex stays within
    /// 1.2 arm radii of the capsule axis and never past the tip sphere. Decision (documented in WornSet.swift): a glove is a skin over the capsule, not extra
    /// arm, so it does not count toward ArmCap's exposed length; this test is what holds it to that.
    func testGlovesHugThePosedArmAndTheCapStillHolds() {
        WearBody.install(MotionRig.renderMesh)
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.seed = 11; r.brain.amplitude = 1
        r.brain.request(.goTo(SIMD2(1.6, 0.4)))
        var samples = 0, worstRadial: Float = 0, worstTip: Float = 0, worstExposed = 0.0
        let slotShell = WornSet.Slot()
        for look in [WearLook.gloveSky, .boxingMitts, .wristbandsSky] {
            guard let p = WearMeshes.prepare(look, body: WearBody.shared) else { XCTFail("\(look)"); continue }
            r.run(7) {
                guard r.brain.armG > 0.5 else { return }
                var slot = slotShell
                slot.arms = GameCare.armFrames(brain: r.brain, sim: r.sim)
                for si in 0..<2 {
                    let g = r.brain.armLastGeom[si]
                    worstExposed = max(worstExposed, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2)))
                }
                var m = RoomMesh()
                WornSet.emitArms(p, into: &m, slot: slot, scale: 1)
                XCTAssertEqual(m.vertices.count, 2 * p.rest.count)
                for side in 0..<2 {
                    let f = slot.arms[side]
                    let Y = simd_normalize(f.a - f.b)
                    for k in 0..<p.rest.count {
                        let v = m.vertices[side * p.rest.count + k].pos
                        let q = SIMD3(v.x, v.y, v.z) - f.b
                        let t = simd_dot(q, Y)
                        worstTip = max(worstTip, -t / f.r2)
                        worstRadial = max(worstRadial, simd_length(q - Y * t) / f.r2)
                    }
                }
                samples += 1
            }
        }
        XCTAssertGreaterThan(samples, 100)
        XCTAssertLessThanOrEqual(worstTip, 1.0 + 1e-3, "no glove vertex past the capsule's tip sphere")
        XCTAssertLessThanOrEqual(worstRadial, 1.2, "a glove is a skin of at most ~1.2 arm radii")
        XCTAssertLessThanOrEqual(worstExposed, ArmCap.maximum + 1e-6, "the capsule itself stays within the global cap with gloves on")
        MotionLog.write(String(format: "WEAR gloves: %d samples, worst radial %.3f r2, past-tip %.3f r2, exposed max %.4f (cap %.4f)", samples, worstRadial, worstTip, worstExposed, ArmCap.maximum))
    }

    // MARK: jersey

    /// The jersey draws a band on the egg but never touches the mouth: with the mouth wide open the pixels around it are identical with and without the jersey,
    /// and the band itself really is drawn (pixels differ below the mouth).
    func testJerseyBandIsDrawnAndNeverCoversTheMouth() throws {
        GameCamera.configureRoom(count: 1)
        let sc = try XCTUnwrap(GfxLabScene(width: 603, height: 1311))
        Self.keep.append(sc)
        sc.ren.setMouth(1, body: 0)
        let plain = sc.render(cache: false)
        sc.ren.setJersey(.sky, body: 0)
        let jersey = sc.render(cache: false)
        XCTAssertGreaterThan(sc.ren.jerseyDraws, 0, "the jersey pipeline was used")
        let pose = sc.rig.sim.bodyPose(iterations: 3)
        let c = EyeMaskModel.Carry(centroid: pose.centroid, rotation: pose.rotation, squash: sc.rig.sim.attractor.squash, restCentroid: sc.rig.sim.restCentroid)
        let cam = GameCamera.camera(aspect: Float(603) / Float(1311), focus: 0)
        func px(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let w = c.world(p); let k = cam.viewProj * SIMD4<Float>(w.x, w.y, w.z, 1)
            return SIMD2((k.x / k.w * 0.5 + 0.5) * 603, (1 - (k.y / k.w * 0.5 + 0.5)) * 1311)
        }
        func diff(in r: (SIMD2<Float>, SIMD2<Float>)) -> Int {
            var n = 0
            for y in Int(r.0.y)...Int(r.1.y) { for x in Int(r.0.x)...Int(r.1.x) {
                let i = 4 * (y * 603 + x)
                if abs(Int(plain.bgra[i]) - Int(jersey.bgra[i])) > 2 || abs(Int(plain.bgra[i + 1]) - Int(jersey.bgra[i + 1])) > 2 { n += 1 }
            } }
            return n
        }
        let m0 = px(SIMD3(-0.15, 0.75, 0.5)), m1 = px(SIMD3(0.15, 0.55, 0.5))
        let mouth = (SIMD2(min(m0.x, m1.x), min(m0.y, m1.y)), SIMD2(max(m0.x, m1.x), max(m0.y, m1.y)))
        XCTAssertEqual(diff(in: mouth), 0, "the open mouth region is pixel-identical with the jersey on")
        let b0 = px(SIMD3(-0.4, 0.5, 0.35)), b1 = px(SIMD3(0.4, 0.25, 0.35))
        let band = (SIMD2(min(b0.x, b1.x), min(b0.y, b1.y)), SIMD2(max(b0.x, b1.x), max(b0.y, b1.y)))
        XCTAssertGreaterThan(diff(in: band), 1500, "the band is drawn on the belly")
    }
}
