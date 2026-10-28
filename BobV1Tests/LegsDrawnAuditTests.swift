//
//  LegsDrawnAuditTests.swift
//  2026-10-28 (legs come off, on the phone): audit of the geometry that is actually DRAWN, not the idealised rest-egg shape the other feet suites measure.
//  The rig runs the stage's per-frame order (MelonStage.draw): a frame is 0...2 fixed steps (brain tick, jelly tick, sim step), the post-step refit once
//  after the steps, the skin EVERY frame (Skinner.update into the dyn buffer: bean blend, retract, jiggle, tail, eyes); 60 / 120 fps cadences, optional hitch
//  frames (two steps in one frame, dropped time).
//  Per leg and frame, from the skinned dyn buffer and the real body triangles (the index range the renderer draws as the egg, before the arm / bean / tail block):
//    burial   how deep the bean's crown (the part meant to be buried) lies INSIDE the drawn body (signed distance to the nearest drawn triangle, sign from the
//             skinned vertex normals). <= 0 = even the deepest crown vertex is outside the drawn body = the leg came off.
//    gap      max(0, -burial): the closest approach of the bean's top to the drawn surface when it is not inside (0 = joined).
//  Env: AUDIT_ONLY="a,b" (scenario name parts), AUDIT_CW_N (cartwheel reps), AUDIT_CAP_DIR (render the worst frames + cartwheel strips), AUDIT_STRIPS_ONLY=1.
//

import XCTest
import Metal
import simd
import UIKit
@testable import BobV1

@MainActor
final class LegsDrawnAuditTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let scratch = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/legs/"

    // MARK: drawn-space measurement

    /// Triangles of the egg as the renderer draws it (everything before the arm capsule / foot bean / tail block).
    static let bodyTri: [Int32] = { let rm = MotionRig.renderMesh; return rm.index[0..<(rm.armCapsule?.indexFirst ?? 0)].map { Int32($0) } }()
    /// A few crown vertices of the bean: the top pole and every second vertex of the top three rings (the part that must lie inside the egg).
    static let crown: [Int] = { let c = FootBean.crownIndices; return c.enumerated().filter { $0.offset % 2 == 0 || $0.element == FootBean.vertexCount - 1 }.map { $0.element } }()

    struct LegM {
        var beans = false, blend: Float = 0
        var burial: Float = .infinity            // deepest crown vertex inside the DRAWN body (<= 0 = off); min over both legs
        var crownOut: Float = -.infinity         // the crown vertex farthest outside the drawn body
        var ideal: Float = -.infinity            // the old measurement: deepest bean vertex vs the REST egg in the fitted frame (needs <= -0.02)
        var stretch: Float = 0, coreDisp: Float = 0      // embedded foot (beans in): extent over rest extent; largest distance from its place on the rigid fitted body
        var legOut: Float = .infinity            // how far the bean's farthest vertex stands OUT of the drawn body (the visible leg length); min over legs
        var shoeBurial: Float = .infinity        // shoes: deepest vertex of the SHOE SHELL inside the drawn body (<= 0 = the shell floats off the body); min over legs
        var shoeBeanOff: Float = 0               // shoes: largest distance between the vertices the shoe is built from and the bean that is drawn
        var gap: Float { max(0, -burial) }
    }

    static func measure(_ r: MotionRig, shoes: Bool, look: WearLook = .shoes[0]) -> LegM {
        var m = LegM()
        m.beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05; m.blend = r.skinner.beanBlend
        let pose = r.sim.bodyPose(iterations: 4), c0 = r.sim.restCentroid
        let tri = bodyTri
        r.dyn.withUnsafeBufferPointer { d in
            @inline(__always) func P(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v], d[6 * v + 1], d[6 * v + 2]) }
            @inline(__always) func N(_ v: Int) -> SIMD3<Float> { SIMD3(d[6 * v + 3], d[6 * v + 4], d[6 * v + 5]) }
            if m.beans {
                for s in 0..<2 {
                    let first = Int(r.bean[s][0])
                    var pts: [SIMD3<Float>] = []
                    for i in crown { pts.append(P(first + i)) }
                    var c = SIMD3<Float>.zero; for p in pts { c += p }; c /= Float(pts.count)
                    // candidate drawn triangles near this bean
                    var cand: [Int] = []
                    var t = 0
                    while t < tri.count {
                        let a = P(Int(tri[t])), b = P(Int(tri[t + 1]))
                        if simd_distance_squared(a, c) < 0.45 * 0.45 || simd_distance_squared(b, c) < 0.45 * 0.45 { cand.append(t) }
                        t += 3
                    }
                    var deepest = -Float.infinity, farOut = -Float.infinity
                    for p in pts {
                        var bd = Float.infinity, sgn: Float = 1
                        for t in cand {
                            let ia = Int(tri[t]), ib = Int(tri[t + 1]), ic = Int(tri[t + 2])
                            let (q, w) = DrawnGeom.closest(p, P(ia), P(ib), P(ic))
                            let dd = simd_distance_squared(p, q)
                            if dd < bd { bd = dd; let n = N(ia) * w.x + N(ib) * w.y + N(ic) * w.z; sgn = simd_dot(p - q, n) >= 0 ? 1 : -1 }
                        }
                        let sd = sgn * bd.squareRoot()
                        deepest = max(deepest, -sd); farOut = max(farOut, sd)
                    }
                    m.burial = min(m.burial, deepest); m.crownOut = max(m.crownOut, farOut)
                    // visible leg length: the bean vertex farthest outside the drawn body (every 4th vertex)
                    var leg: Float = -.infinity
                    var cand2: [Int] = []
                    var tt = 0
                    while tt < tri.count { if simd_distance_squared(P(Int(tri[tt])), c) < 0.35 * 0.35 { cand2.append(tt) }; tt += 3 }
                    var vi = 0
                    while vi < FootBean.vertexCount {
                        let p = P(first + vi)
                        var bd = Float.infinity, sgn: Float = 1
                        for t in cand2 {
                            let ia = Int(tri[t]), ib = Int(tri[t + 1]), ic = Int(tri[t + 2])
                            let (q, w) = DrawnGeom.closest(p, P(ia), P(ib), P(ic))
                            let dd = simd_distance_squared(p, q)
                            if dd < bd { bd = dd; let n = N(ia) * w.x + N(ib) * w.y + N(ic) * w.z; sgn = simd_dot(p - q, n) >= 0 ? 1 : -1 }
                        }
                        leg = max(leg, sgn * bd.squareRoot())
                        vi += 4
                    }
                    m.legOut = min(m.legOut, leg)
                    // the old idealised number, every 2nd bean vertex
                    var ideal = Float.infinity
                    var i = 0
                    while i < FootBean.vertexCount {
                        let q = c0 + pose.rotation.inverse.act(P(first + i) - pose.centroid)
                        ideal = min(ideal, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                        i += 2
                    }
                    m.ideal = max(m.ideal, ideal)
                }
                if shoes {
                    let w: [[SIMD3<Float>]]? = r.dyn.withUnsafeBufferPointer { GameCare.footBeans(brain: r.brain, sim: r.sim, skinner: r.skinner, drawn: $0.baseAddress) }
                    if let w {
                        for s in 0..<2 where w[s].count == FootBean.vertexCount {
                            let first = Int(r.bean[s][0])
                            for i in 0..<FootBean.vertexCount { m.shoeBeanOff = max(m.shoeBeanOff, simd_distance(w[s][i], P(first + i))) }
                            let b = RoomMeshBuilder(); b.material = .plain
                            ShoeModel.buildShell(look, bean: w[s], floorY: r.sim.floorY, body: SIMD3(0.35, 0.5, 0.9), time: 0, gpuPaint: true, side: s, into: b)
                            var pts: [SIMD3<Float>] = []
                            var k = 0
                            for v in b.mesh.vertices { if k % 5 == 0 { pts.append(SIMD3(v.pos.x, v.pos.y, v.pos.z)) }; k += 1 }
                            guard !pts.isEmpty else { continue }
                            var c = SIMD3<Float>.zero; for p in pts { c += p }; c /= Float(pts.count)
                            var rho: Float = 0; for p in pts { rho = max(rho, simd_distance(p, c)) }
                            var cand: [Int] = []
                            var t = 0
                            while t < tri.count {
                                if simd_distance_squared(P(Int(tri[t])), c) < (rho + 0.07) * (rho + 0.07) { cand.append(t) }
                                t += 3
                            }
                            var deepest = -Float.infinity
                            for p in pts {
                                var bd = Float.infinity, sgn: Float = 1
                                for t in cand {
                                    let ia = Int(tri[t]), ib = Int(tri[t + 1]), ic = Int(tri[t + 2])
                                    let (q, ww) = DrawnGeom.closest(p, P(ia), P(ib), P(ic))
                                    let dd = simd_distance_squared(p, q)
                                    if dd < bd { bd = dd; let n = N(ia) * ww.x + N(ib) * ww.y + N(ic) * ww.z; sgn = simd_dot(p - q, n) >= 0 ? 1 : -1 }
                                }
                                deepest = max(deepest, -sgn * bd.squareRoot())
                            }
                            m.shoeBurial = min(m.shoeBurial, deepest)
                        }
                    }
                }
            } else {
                let rest = MotionRig.renderMesh.rest
                for s in 0..<2 {
                    let ids = r.core[s]
                    guard !ids.isEmpty else { continue }
                    var mean = SIMD3<Float>.zero
                    for id in ids { mean += P(Int(id)) }
                    mean /= Float(ids.count)
                    var ext: Float = 0
                    for id in ids {
                        let p = P(Int(id)); ext = max(ext, simd_distance(p, mean))
                        let rp = SIMD3(rest[3 * Int(id)], rest[3 * Int(id) + 1], rest[3 * Int(id) + 2])
                        m.coreDisp = max(m.coreDisp, simd_distance(p, pose.centroid + pose.rotation.act(rp - c0)))
                    }
                    m.stretch = max(m.stretch, ext / FeetAttachTests.coreRestExtent[s])
                }
            }
        }
        return m
    }

    // MARK: stage-order driver

    /// `jitter`: each frame's dt is dt * (1 +- jitter) (vsync noise: frames with 0, 1 or 2 steps); `slowFirst`: the first seconds at 30 fps (the idle-rest governor drops to 30 fps and takes a moment to wake).
    struct Cadence { let name: String; let dt: Float; let hitch: Bool; var jitter: Float = 0; var slowFirst: Float = 0 }
    static let cadences = [Cadence(name: "60", dt: 1.0 / 60, hitch: false), Cadence(name: "120", dt: 1.0 / 120, hitch: false),
                           Cadence(name: "60+hitch", dt: 1.0 / 60, hitch: true), Cadence(name: "120+hitch", dt: 1.0 / 120, hitch: true),
                           Cadence(name: "30", dt: 1.0 / 30, hitch: false), Cadence(name: "30>60", dt: 1.0 / 60, hitch: false, slowFirst: 0.5),
                           Cadence(name: "60jit", dt: 1.0 / 60, hitch: false, jitter: 0.2), Cadence(name: "120jit", dt: 1.0 / 120, hitch: false, jitter: 0.25)]
    static let features: [(String, JellyFeature)] = [("Bob", .none), ("Pip", .spines), ("Moss", .daisy), ("Lavender", .wings)]

    static func lcg(_ s: inout UInt64) -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 40) & 0xFFFFFF) / Float(0x1000000) }

    struct Scenario {
        let name: String
        let game: Bool
        let seconds: Float
        let setup: (MotionRig, UInt64) -> Bool
        var each: ((MotionRig) -> Void)? = nil
        var decor = false
        var endKind: IdleKind? = nil            // stop 0.5 s after this move ends (after it has been seen)
        var stopWhenDone = false                // stop when the idle move is over
        var measureEvery = 1
        var variants = 8
    }

    struct Run {
        var frames = 0, beanFrames = 0, coreFrames = 0, off = 0, gap5 = 0, marginal = 0, started = true, hitches = 0
        var minBurial: Float = .infinity, minBurialFrame = -1, minBurialBlend: Float = 0, maxCrownOut: Float = -.infinity, maxIdeal: Float = -.infinity
        var idealOkButOff = 0
        var maxStretch: Float = 0, maxCoreDisp: Float = 0, maxShoeBeanOff: Float = 0, minShoeBurial: Float = .infinity, shoeOff = 0, shoeMarginal = 0
    }

    /// One scenario run. `onFrame` is called after the skin of every frame (frame index, the rig, the measurement or nil when not measured).
    static func run(_ sc: Scenario, feature: JellyFeature, shoes: Bool, cad: Cadence, seed: UInt64, onFrame: ((Int, MotionRig, LegM?) -> Void)? = nil) -> Run {
        var out = Run()
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        let r = MotionRig(game: sc.game, settle: 0.5)
        keep.append(r); defer { keep.removeAll(); DecorField.shared.clear() }
        r.renderSamples = false
        r.brain.feature = feature
        r.skinner.configureTail(MotionRig.renderMesh); r.skinner.tailOn = feature == .spines; r.brain.skinnerRef = r.skinner
        r.brain.shoesWorn = shoes
        r.brain.seed = 5 + seed
        guard sc.setup(r, seed) else { out.started = false; return out }
        var rs = seed &* 0x9E3779B97F4A7C15 &+ 99
        let stepDt = r.sim.stepDt
        var acc: Float = 0, t: Float = 0, frame = 0, after: Float = 0, seen = false
        let maxFrames = Int(sc.seconds * 130) + 600
        while t < sc.seconds && frame < maxFrames {
            var dt = cad.dt
            if t < cad.slowFirst { dt = 1.0 / 30 }
            if cad.jitter > 0 { dt *= 1 + cad.jitter * (2 * lcg(&rs) - 1) }
            if cad.hitch { let u = lcg(&rs); if u < 0.08 { dt = 2 * stepDt + 0.0005; out.hitches += 1 } else if u < 0.11 { dt = 0.1; out.hitches += 1 } }
            acc += dt
            var steps = 0
            while acc >= stepDt && steps < 2 {
                r.brain.tick(sim: r.sim, skinner: r.skinner, dt: stepDt, touched: false)
                r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: stepDt)
                sc.each?(r)
                if sc.decor { DecorField.shared.tick(dt: stepDt) }
                r.sim.step(); r.t += stepDt; t += stepDt
                acc -= stepDt; steps += 1
            }
            if steps == 2 { acc = min(acc, stepDt) }
            if steps > 0 { r.brain.refitBeans(r.sim, r.skinner) }
            r.skinner.tickBlink(dt: dt)
            r.render()
            if let k = sc.endKind {
                if r.brain.idleState.kind == k { seen = true } else if seen { after += dt }
                if after > 0.5 { break }
                if !seen && t > 2.0 { out.started = false; break }
            }
            if sc.stopWhenDone, t > 0.5, r.brain.idleState.kind == nil { break }
            frame += 1
            var mm: LegM? = nil
            if frame % sc.measureEvery == 0 {
                let m = measure(r, shoes: shoes, look: WearLook.shoes[Int(seed) % WearLook.shoes.count])
                mm = m
                out.frames += 1
                if m.beans {
                    out.beanFrames += 1
                    if m.blend > 0.05 {
                        if m.burial <= 0 { out.off += 1; if m.ideal <= -0.02 { out.idealOkButOff += 1 } }
                        if m.gap > 0.005 { out.gap5 += 1 }
                        if m.burial < 0.01 { out.marginal += 1 }
                        if m.burial < out.minBurial { out.minBurial = m.burial; out.minBurialFrame = frame; out.minBurialBlend = m.blend }
                        out.maxCrownOut = max(out.maxCrownOut, m.crownOut); out.maxIdeal = max(out.maxIdeal, m.ideal)
                    }
                    out.maxShoeBeanOff = max(out.maxShoeBeanOff, m.shoeBeanOff)
                    if shoes, m.blend > 0.05, m.shoeBurial.isFinite {
                        out.minShoeBurial = min(out.minShoeBurial, m.shoeBurial)
                        if m.shoeBurial <= 0 { out.shoeOff += 1 }
                        if m.shoeBurial < 0.005 { out.shoeMarginal += 1 }
                    }
                } else { out.coreFrames += 1; out.maxStretch = max(out.maxStretch, m.stretch); out.maxCoreDisp = max(out.maxCoreDisp, m.coreDisp) }
            }
            onFrame?(frame, r, mm)
        }
        return out
    }

    // MARK: scenarios

    static func cartwheel(_ entry: String) -> Scenario {
        Scenario(name: "cartwheel-\(entry)", game: true, seconds: 14, setup: { r, seed in
            var s = seed &* 2654435761 &+ 17
            let px = (lcg(&s) - 0.5) * 2.4, pz = (lcg(&s) - 0.3) * 1.8
            r.sim.teleport(toXZ: SIMD2(px, pz)); r.run(0.4)
            r.brain.currentPose(r.sim)
            if lcg(&s) < 0.5 { let p = r.root + SIMD2(0.55 + 0.2 * lcg(&s), 0.3 * (lcg(&s) - 0.5)); r.brain.peers = { [(id: 1, pos: p)] }; r.brain.steerID = 0; r.brain.peerGap = 0.9 }
            r.brain.idleForced = true
            let goal = SIMD2<Float>(-px * 0.6 + 0.3 * (lcg(&s) - 0.5), 1.0 + 0.8 * lcg(&s))
            switch entry {
            case "stand": return r.brain.idleStart(.cartwheel, r.sim)
            case "walk": r.brain.requestNow(.goTo(goal)); r.run(0.4 + 1.2 * lcg(&s)); return r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            case "run": _ = r.brain.idleStart(.run, r.sim); r.run(0.5 + 1.5 * lcg(&s)); return r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            default: r.brain.seed = 11; _ = r.brain.idleStart(.zoomies, r.sim); r.run(0.8 + 2.5 * lcg(&s)); return r.brain.flourishStart(.cartwheel, resume: goal, r.sim, r.skinner)
            }
        }, endKind: .cartwheel)
    }

    static func ride(_ name: String, _ kind: DecorKind, at p: SIMD2<Float>, move: IdleKind, seconds: Float) -> Scenario {
        Scenario(name: name, game: true, seconds: seconds, setup: { r, _ in
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
            r.brain.anticsEnabled = true; r.brain.sleepEnabled = true
            r.brain.abortScript(r.sim, r.skinner)
            r.sim.teleport(toXZ: SIMD2(-1.2, 1.4)); for _ in 0..<120 { r.sim.step() }
            r.brain.currentPose(r.sim); r.brain.idleForced = true
            return r.brain.decorStart(move, r.sim, only: kind)
        }, decor: true, stopWhenDone: true, measureEvery: 3, variants: 4)
    }

    static func fromMove(_ name: String, measureEvery: Int = 1) -> Scenario? {
        guard let m = FeetAttachTests.moves.first(where: { $0.name == name }) else { return nil }
        return Scenario(name: m.name, game: m.game, seconds: m.seconds, setup: { r, _ in m.start(r); return true }, each: m.each, decor: m.name.hasPrefix("decor") || m.name.hasPrefix("soccer"), measureEvery: measureEvery)
    }

    static func allScenarios() -> [Scenario] {
        let names = ["hop", "antic: spin after his tail", "flip", "faceplant", "run", "zoomies", "walk (game)", "antic: roll", "flourish: roll along the leg",
                     "sleep: roll onto the back and up again", "sit", "jumping jacks", "belly slide", "antic: flop", "Lavender: flap-hop", "flourish: skip-hop",
                     "flourish: mid-leg spin", "jump for joy", "decor2: climb the slide, sit, ride, exit", "decor: hop on the mat", "ears dance", "antic: cartwheel"]
        var list = names.compactMap { fromMove($0) }
        list.append(ride("toy: scooter", .kickscooter, at: SIMD2(1.2, 0.4), move: .decorSlide, seconds: 45))
        list.append(ride("toy: rocket", .toyrocket, at: SIMD2(1.1, 0.5), move: .decorSit, seconds: 50))
        list.append(ride("toy: rocking horse", .rockinghorse, at: SIMD2(1.1, 0.5), move: .decorSit, seconds: 50))
        return list
    }

    func filtered(_ list: [Scenario]) -> [Scenario] {
        guard let only = ProcessInfo.processInfo.environment["AUDIT_ONLY"], !only.isEmpty else { return list }
        let parts = only.components(separatedBy: ",")
        return list.filter { s in parts.contains { s.name.contains($0) } }
    }

    struct Row { let sc: Scenario; let fi: Int; let shoes: Bool; let cad: Int; let seed: UInt64; var res: Run }

    func line(_ sc: String, _ fi: Int, _ shoes: Bool, _ cad: Int, _ seed: UInt64, _ x: Run) -> String {
        String(format: "AUDIT %@ | %@ shoes=%d cad=%@ seed=%d | frames=%d bean=%d core=%d off=%d gap>5mm=%d marginal(<1cm)=%d idealOKbutOff=%d | minBurial=%.4f@%d(blend %.2f) maxCrownOut=%.4f idealOverlap=%.3f | coreStretch=%.2f coreDisp=%.3f shoeVsBean=%.3f shoeShellBurial=%.4f shoeOff=%d shoeMarg=%d hitches=%d",
               sc, Self.features[fi].0, shoes ? 1 : 0, Self.cadences[cad].name, Int(seed), x.frames, x.beanFrames, x.coreFrames, x.off, x.gap5, x.marginal, x.idealOkButOff, x.minBurial, x.minBurialFrame, x.minBurialBlend, x.maxCrownOut, x.maxIdeal, x.maxStretch, x.maxCoreDisp, x.maxShoeBeanOff, x.minShoeBurial, x.shoeOff, x.shoeMarginal, x.hitches)
    }

    // MARK: sweep

    func testDrawnLegsAuditSweep() throws {
        let env = ProcessInfo.processInfo.environment
        ToyTuning.settle = 0; defer { ToyTuning.settle = 5; DecorField.shared.clear() }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        var rows: [Row] = []
        let cwN = Int(env["AUDIT_CW_N"] ?? "") ?? 256
        // cartwheels: character x shoes x entry x cadence all covered, many random seeds
        var cwScs: [Scenario] = []
        for e in ["stand", "walk", "run", "zoomies"] { cwScs.append(Self.cartwheel(e)) }
        for sc in filtered(cwScs) {
            let entry = sc.name
            for n in 0..<(cwN / 4) {
                let fi = n % 4, shoes = (n / 4) % 2 == 1, cad = (n / 8) % Self.cadences.count
                let seed = UInt64(1 + n) &+ UInt64(entry.count * 1000)
                let res = Self.run(sc, feature: Self.features[fi].1, shoes: shoes, cad: Self.cadences[cad], seed: seed)
                if !res.started { continue }
                rows.append(Row(sc: sc, fi: fi, shoes: shoes, cad: cad, seed: seed, res: res))
                MotionLog.write(line(sc.name, fi, shoes, cad, seed, res))
            }
        }
        // the other moves: every character x shoes, cadences rotating
        for (si, sc) in filtered(Self.allScenarios()).enumerated() {
            for v in 0..<sc.variants {
                let fi = v % 4, shoes = (v / 4) % 2 == 1, cad = (fi + 2 * (shoes ? 1 : 0) + si) % Self.cadences.count
                let seed = UInt64(3 + v)
                let res = Self.run(sc, feature: Self.features[fi].1, shoes: shoes, cad: Self.cadences[cad], seed: seed)
                if !res.started { MotionLog.write("AUDIT \(sc.name) did not start (\(Self.features[fi].0))"); continue }
                rows.append(Row(sc: sc, fi: fi, shoes: shoes, cad: cad, seed: seed, res: res))
                MotionLog.write(line(sc.name, fi, shoes, cad, seed, res))
            }
        }
        // summary per scenario and per cadence
        var bySc: [String: (frames: Int, off: Int, gap: Int, marg: Int, minB: Float, ideal: Int, stretch: Float, disp: Float)] = [:]
        var byCad: [String: (Int, Int)] = [:]
        for x in rows {
            var e = bySc[x.sc.name] ?? (0, 0, 0, 0, .infinity, 0, 0, 0)
            e.frames += x.res.beanFrames; e.off += x.res.off; e.gap += x.res.gap5; e.marg += x.res.marginal; e.minB = min(e.minB, x.res.minBurial); e.ideal += x.res.idealOkButOff
            e.stretch = max(e.stretch, x.res.maxStretch); e.disp = max(e.disp, x.res.maxCoreDisp)
            bySc[x.sc.name] = e
            var c = byCad[Self.cadences[x.cad].name] ?? (0, 0); c.0 += x.res.beanFrames; c.1 += x.res.off; byCad[Self.cadences[x.cad].name] = c
        }
        for (k, e) in bySc.sorted(by: { $0.key < $1.key }) {
            MotionLog.write(String(format: "AUDITSUM %@: beanFrames=%d off=%d gap>5mm=%d marginal=%d idealOKbutOff=%d worstBurial=%.4f maxCoreStretch=%.2f maxCoreDisp=%.3f", k, e.frames, e.off, e.gap, e.marg, e.ideal, e.minB, e.stretch, e.disp))
        }
        MotionLog.write("AUDITCAD \(byCad.sorted { $0.key < $1.key }.map { "\($0.key): frames \($0.value.0) off \($0.value.1)" })")
        let worst = rows.filter { $0.res.minBurialFrame >= 0 }.sorted { $0.res.minBurial < $1.res.minBurial }.prefix(10)
        for w in worst { MotionLog.write("AUDITWORST " + line(w.sc.name, w.fi, w.shoes, w.cad, w.seed, w.res)) }
        let totalOff = rows.reduce(0) { $0 + $1.res.off }
        MotionLog.write("AUDIT TOTAL runs=\(rows.count) off=\(totalOff) gap>5mm=\(rows.reduce(0) { $0 + $1.res.gap5 }) marginal=\(rows.reduce(0) { $0 + $1.res.marginal })")

        if let dir = env["AUDIT_CAP_DIR"], !dir.isEmpty, env["AUDIT_STRIPS_ONLY"] == nil {
            try renderWorst(Array(worst.prefix(8)), dir: dir)
        }
        XCTAssertGreaterThan(rows.count, 4)
        // (strict by default; AUDIT_LAX=1 only logs)
        guard env["AUDIT_LAX"] == nil else { return }
        XCTAssertGreaterThanOrEqual(rows.map { $0.res.minShoeBurial }.min() ?? 0, -0.006, "a shoe shell floats more than 6 mm off the drawn body (the shell is a collar around the bean, so it may touch the belly from outside; a 5 mm sliver is not visible)")
        XCTAssertEqual(totalOff, 0, "frames where a leg's bean is not inside the DRAWN body")
        XCTAssertEqual(rows.reduce(0) { $0 + $1.res.gap5 }, 0, "frames with a visible gap > 5 mm")
        XCTAssertEqual(rows.reduce(0) { $0 + $1.res.marginal }, 0, "frames where the bean is buried less than 1 cm in the DRAWN body")
    }

    // MARK: rendering

    @MainActor final class Shooter {
        let device: MTLDevice, ren: MelonRenderer, target: MTLTexture
        let T: Int
        var rig = CameraRig()
        init?(r: MotionRig, T: Int) {
            guard let d = MTLCreateSystemDefaultDevice(), let ren = MelonRenderer(device: d, colorPixelFormat: .bgra8Unorm, mesh: MotionRig.renderMesh, simEdges: r.sim.edges, particleCount: r.sim.n) else { return nil }
            device = d; self.ren = ren; self.T = T
            ren.resize(width: T, height: T)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: T, height: T, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
            target = d.makeTexture(descriptor: td)!
        }
        /// The leg area of this frame: the centre of the drawn beans.
        func legCentre(_ r: MotionRig) -> SIMD3<Float> {
            var c = SIMD3<Float>.zero, n: Float = 0
            for s in 0..<2 { for id in r.bean[s] { let o = 6 * Int(id); c += SIMD3(r.dyn[o], r.dyn[o + 1], r.dyn[o + 2]); n += 1 } }
            return c / n
        }
        /// Renders the dyn buffer the audit measured. az: camera azimuth (0 = front), el: elevation (negative = from below).
        func shot(_ r: MotionRig, az: Float, el: Float, dist: Float, target tgt: SIMD3<Float>, palette: PaletteKey) -> [UInt8] {
            let eye = tgt + SIMD3(dist * sinf(az) * cosf(el), dist * sinf(el), dist * cosf(az) * cosf(el))
            var cam = CameraState()
            cam.view = M4.lookAt(eye: eye, at: tgt, up: SIMD3(0, 1, 0))
            cam.viewProj = M4.mul(M4.perspective(fovy: CameraRig.fov, aspect: 1, near: 0.05, far: 60), cam.view)
            cam.invViewProj = M4.invert(cam.viewProj); cam.pos = eye; cam.fwd = simd_normalize(tgt - eye)
            rig.azimuth = az
            let light = rig.light(centroid: r.sim.centroid())
            ren.beginFrame()
            r.dyn.withUnsafeBufferPointer { ren.dynPointer.update(from: $0.baseAddress!, count: r.dyn.count) }
            var fp = FrameParams()
            fp.shape = SIMD4<Float>(Shape.T, Shape.Ro, Shape.skin, Shape.pale)
            fp.exposure = 1; fp.meshAlpha = 0
            let pal = palette.palette
            fp.bg = pal.matte ? melonCreamLinear : melonBackgroundLinear
            ren.setUniforms(camera: cam, light: light, palette: pal, params: fp, viewSize: SIMD2<Float>(Float(T), Float(T)))
            let cmd = ren.queue.makeCommandBuffer()!
            ren.draw(to: target, commandBuffer: cmd, showMesh: false)
            cmd.waitUntilCompleted()
            var px = [UInt8](repeating: 0, count: T * T * 4)
            px.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: T * 4, from: MTLRegionMake2D(0, 0, T, T), mipmapLevel: 0) }
            return px
        }
    }

    static func palette(_ fi: Int) -> PaletteKey { fi == 1 ? .yellow : .blue }

    static func compose(_ tiles: [[UInt8]], T: Int, cols: Int, labels: [String], header: String?, to path: String) {
        let rows = (tiles.count + cols - 1) / cols
        let lab = 34, hdr = header == nil ? 0 : 30
        let W = T * cols, H = (T + lab) * rows + hdr
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            if let header { (header as NSString).draw(at: CGPoint(x: 6, y: 6), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white]) }
            for (i, t) in tiles.enumerated() {
                let ox = (i % cols) * T, oy = hdr + (i / cols) * (T + lab)
                (labels[i] as NSString).draw(in: CGRect(x: ox + 3, y: oy + 1, width: T - 6, height: lab), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(white: 0.9, alpha: 1)])
                if let ui = LockImage(w: T, h: T, bgra: t).uiImage() { ui.draw(in: CGRect(x: ox, y: oy + lab, width: T, height: T)) }
            }
        }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? img.pngData()?.write(to: URL(fileURLWithPath: path))
    }

    /// The worst frames of the sweep, re-run deterministically and rendered from the side and from below 3/4, close on the legs.
    private func renderWorst(_ worst: [Row], dir: String) throws {
        for (k, w) in worst.enumerated() {
            var tiles: [[UInt8]] = [], labels: [String] = []
            var shooter: Shooter? = nil
            _ = Self.run(w.sc, feature: Self.features[w.fi].1, shoes: w.shoes, cad: Self.cadences[w.cad], seed: w.seed) { frame, r, _ in
                guard frame == w.res.minBurialFrame else { return }
                if shooter == nil { shooter = Shooter(r: r, T: 520) }
                guard let sh = shooter else { return }
                let c = sh.legCentre(r)
                let m = Self.measure(r, shoes: w.shoes)
                let tgt = c + SIMD3(0, 0.08, 0)
                tiles.append(sh.shot(r, az: .pi / 2, el: 0.05, dist: 2.6, target: tgt, palette: Self.palette(w.fi)))
                labels.append(String(format: "side  burial %.4f crownOut %.4f ideal %.3f", m.burial, m.crownOut, m.ideal))
                tiles.append(sh.shot(r, az: 0.65, el: -0.35, dist: 2.6, target: tgt, palette: Self.palette(w.fi)))
                labels.append("below 3/4")
                tiles.append(sh.shot(r, az: 0.0, el: 0.1, dist: 2.6, target: tgt, palette: Self.palette(w.fi)))
                labels.append("front")
            }
            guard !tiles.isEmpty else { continue }
            let name = String(format: "worst%02d_%@_%@_%@%@_cad%@_f%d.png", k, w.sc.name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ",", with: ""), Self.features[w.fi].0, w.shoes ? "shoes_" : "", "", Self.cadences[w.cad].name, w.res.minBurialFrame)
            Self.compose(tiles, T: 520, cols: 3, labels: labels, header: line(w.sc.name, w.fi, w.shoes, w.cad, w.seed, w.res).prefix(200).description, to: dir + "/" + name)
            MotionLog.write("AUDITPNG " + dir + "/" + name)
        }
    }

    /// Every 2nd frame through one full cartwheel (120 fps cadence), close on the legs, side view + below 3/4.
    func testCartwheelStrips() throws {
        guard let dir = ProcessInfo.processInfo.environment["AUDIT_CAP_DIR"], !dir.isEmpty else { throw XCTSkip("AUDIT_CAP_DIR not set") }
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        for (fi, tag) in [(0, "Bob"), (1, "Pip")] {
            var tiles: [[UInt8]] = [], labels: [String] = []
            var shooter: Shooter? = nil
            let sc = Self.cartwheel("stand")
            let res = Self.run(sc, feature: Self.features[fi].1, shoes: false, cad: Self.cadences[1], seed: 7) { frame, r, _ in
                guard frame % 2 == 0, r.brain.idleState.kind == .cartwheel else { return }
                if shooter == nil { shooter = Shooter(r: r, T: 300) }
                guard let sh = shooter else { return }
                let m = Self.measure(r, shoes: false)
                let tgt = sh.legCentre(r)
                tiles.append(sh.shot(r, az: .pi / 2, el: 0.05, dist: 1.9, target: tgt, palette: Self.palette(fi)))
                labels.append(String(format: "f%d %@ burial %.3f beans %d", frame, "\(r.brain.gait.phase)", m.beans ? m.burial : 0, m.beans ? 1 : 0))
            }
            XCTAssertTrue(res.started)
            guard !tiles.isEmpty else { continue }
            Self.compose(tiles, T: 300, cols: 10, labels: labels, header: "\(tag) cartwheel, 120 fps, every 2nd frame, side view, close on the legs. minBurial \(res.minBurial)", to: dir + "/cartwheel_strip_\(tag).png")
            MotionLog.write("AUDITPNG \(dir)/cartwheel_strip_\(tag).png frames=\(tiles.count) minBurial=\(res.minBurial) off=\(res.off) core=\(res.coreFrames)")
        }
    }

    /// Cost of the drawn-space bean guard: Skinner.update for 3 Jelbies walking / cartwheeling with the guard on vs off (best of 5 batches, microseconds per frame for all three).
    func testBeanGuardCost() throws {
        let rigs = (0..<3).map { _ in MotionRig(game: true, settle: 0.5) }
        Self.keep += rigs
        for (k, r) in rigs.enumerated() {
            r.brain.idleForced = true
            if k == 0 { _ = r.brain.idleStart(.run, r.sim) } else if k == 1 { r.brain.shoesWorn = true; _ = r.brain.idleStart(.zoomies, r.sim) } else { _ = r.brain.idleStart(.jacks, r.sim) }
        }
        var best: [Bool: Double] = [:]
        var guardMoved = 0
        for on in [false, true, false, true] {
            for r in rigs { r.skinner.guardEnabled = on }
            var bestBatch = Double.infinity
            for _ in 0..<5 {
                for _ in 0..<60 { for r in rigs { r.tick() } }
                var t = 0.0
                let n = 120
                for _ in 0..<n {
                    for r in rigs { r.tick() }
                    let t0 = CFAbsoluteTimeGetCurrent()
                    for r in rigs { r.skinner.update(x: r.sim.x, index: MotionRig.renderMesh.index, into: &r.dyn) }
                    t += CFAbsoluteTimeGetCurrent() - t0
                    for r in rigs where r.skinner.guardShift.contains(where: { $0 != .zero }) { guardMoved += 1 }
                }
                bestBatch = min(bestBatch, t / Double(n) * 1e6)
            }
            best[on] = min(best[on] ?? .infinity, bestBatch)
        }
        MotionLog.write(String(format: "GUARDCOST 3 Jelbies: skin %.0f us/frame with the guard off, %.0f us/frame on (delta %.0f us); guard moved a bean on %d jelly-frames", best[false]!, best[true]!, best[true]! - best[false]!, guardMoved))
    }
}
