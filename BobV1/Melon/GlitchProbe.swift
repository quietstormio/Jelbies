//
//  GlitchProbe.swift
//  glitch-hunt-r1 (2026-11-24, owner: "flawless action, natural movement no bumps or slips or glitches"). DEV BUILDS ONLY (compiled out of the App Store archive), LOGGING ONLY.
//  `-GlitchProbe 1`: once per drawn frame, after the skin pass, every drawn Jelmiko is compared with the frame before; a discontinuity is logged
//      [glitch] kind=<jump|yaw|pose|slide|blend|camera|hitch> who=<id> scene=<scene> size=<value> step=<per step value> move=<move key> prev=<previous move> since=<ms since the move changed> ...
//  kinds (jump, yaw, pose and camera are the DEVIATION from the motion of the frame before, per physics step: a steady run or spin reads 0, a snap reads its size):
//    jump    the body's centroid (tele=1 when the body was moved on purpose: SoftBody.teleport / shift / reset)
//    yaw     the body's facing (skipped while it is tipped over, tilt > 50 deg)
//    pose    a POP: a drawn vertex (body / arm / foot / tail / feature, the body's own rigid motion taken out) that moved fast this step after moving under a third
//            of that the step before (a snap to a new pose, a one-frame flicker); a swing or a spring's jiggle is not one. Feet only while the foot pieces are fully out
//    slide   a foot the brain holds planted (bean morph 0, both frames) whose drawn contact patch moved across the floor (plain distance per step)
//    blend   one of the skinner's blend weights (feet, arms) changed by more than `blendStep` in one step
//    camera  the camera's eye
//    hitch   a frame took longer than `hitchMs` of wall time (cpu = the frame's own CPU time)
//  Each (kind, who) burst within `burstS` seconds is one event carrying its largest size. The logged thresholds are LOW (half the stated glitch bars); the parser applies the real bars.
//  Every `sumS` game seconds: `[glitch] sum scene=.. steps=..` (game time per scene, the rate denominator). Thresholds: -GlitchJump -GlitchYaw -GlitchPose -GlitchSlide -GlitchCam -GlitchHitch.
//  Pure core (`GlitchCore`) so a unit test can pin it.
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

/// The thresholds the probe LOGS at (the parser applies the real bars on top).
nonisolated struct GlitchBars {
    var jumpU: Float = 0.04          // real bar 0.08 u
    var yawDeg: Float = 12.5         // real bar 25 deg
    var poseCm: Float = 1.5          // cm per step of sudden motion (real bar 3)
    var slideCm: Float = 0.5         // real bar 1 cm
    var blendStep: Float = 0.3
    var camU: Float = 0.12
    var hitchMs: Double = 50
    var burstS: Double = 0.25
    static func fromDefaults(_ d: UserDefaults = .standard) -> GlitchBars {
        var b = GlitchBars()
        func f(_ k: String) -> Float? { d.object(forKey: k) != nil ? d.float(forKey: k) : nil }
        if let v = f("GlitchJump") { b.jumpU = v }
        if let v = f("GlitchYaw") { b.yawDeg = v }
        if let v = f("GlitchPose") { b.poseCm = v }
        if let v = f("GlitchSlide") { b.slideCm = v }
        if let v = f("GlitchCam") { b.camU = v }
        if let v = f("GlitchHitch") { b.hitchMs = Double(v) }
        return b
    }
}

/// One body's drawn state in one frame (what the core compares).
nonisolated struct GlitchSample {
    var centroid: SIMD3<Float>
    var rotation: simd_quatf
    var tilt: Float
    var moveSerial: Int
    var brainYaw: Float?
    /// Sampled drawn vertices in the body's own frame (rigid motion removed), with their group.
    var local: [SIMD3<Float>]
    var group: [UInt8]
    /// The drawn vertex index of each sample (diagnostics only; may be empty).
    var index: [Int32] = []
    /// Foot pieces: lowest y and the xz of the contact patch; nil = no foot pieces out.
    var feet: [(minY: Float, xz: SIMD2<Float>)]?
    var blends: [Float]          // beanBlend, armBlend
    /// The brain's bean morph per foot (0 = planted boot, 1 = lifted ball; 1 while the foot is in a step's swing); nil = unknown.
    var footMorph: [Float]? = nil
}

nonisolated enum GlitchGroup: UInt8, CaseIterable { case body, arm, foot, tail, feature
    var name: String { ["body", "arm", "foot", "tail", "feature"][Int(rawValue)] }
}

nonisolated struct GlitchEvent {
    var kind: String
    var size: Float          // per frame
    var perStep: Float       // per physics step
    var detail: String
}

/// Compares one body's sample with the frames before it. Pure value type (a unit test drives it).
/// Jump, yaw and pose are measured as the DEVIATION FROM THE MOTION SO FAR (the second difference, per step): a run at 6 u/s or a steady spin is smooth and reads 0;
/// a snap of d in one frame reads d. The planted-foot slide is a plain distance while the brain holds that foot planted (bean morph 0 = the boot on the floor).
nonisolated struct GlitchCore {
    var bars = GlitchBars()
    private(set) var prev: GlitchSample?
    private var vel: SIMD3<Float>?          // centroid motion per step over the last frame
    private var yawVel: Float?               // yaw change per step (rad)
    private var localVel: [SIMD3<Float>]?    // each sampled vertex's local motion per step, last frame
    private var localVel2: [SIMD3<Float>]?   // ... the frame before that
    private var feetOutBefore = false, armsOutBefore = false
    private var planted = [0, 0]             // steps each foot has been held planted

    mutating func forget() { prev = nil; vel = nil; yawVel = nil; localVel = nil; localVel2 = nil; feetOutBefore = false; armsOutBefore = false; planted = [0, 0] }

    /// `steps`: physics steps run this frame (0 = nothing moved: nothing compared, the history is kept).
    mutating func observe(_ s: GlitchSample, steps: Int) -> [GlitchEvent] {
        guard steps > 0 else { return [] }
        guard let p = prev, p.local.count == s.local.count else { forget(); prev = s; return [] }          // first frame or a different mesh: start over
        let k = Float(steps)
        var out: [GlitchEvent] = []
        let tele = s.moveSerial != p.moveSerial
        // jump: the centroid's move against the move the frame before predicted
        let dv = (s.centroid - p.centroid) / k
        if let v = vel {
            let err = simd_distance(dv, v)
            if err > bars.jumpU { out.append(GlitchEvent(kind: "jump", size: err * k, perStep: err, detail: String(format: "tele=%d move=%.3f was=%.3f dy=%.3f", tele ? 1 : 0, simd_length(dv), simd_length(v), dv.y))) }
        }
        if tele { forget(); prev = s; return out }          // a deliberate move: the rest is meaningless this frame; start over
        vel = dv
        // yaw
        if s.tilt < 0.87, p.tilt < 0.87 {
            let w = Self.wrap(Self.yaw(s.rotation) - Self.yaw(p.rotation)) / k
            if let w0 = yawVel {
                let err = abs(w - w0) * 180 / .pi
                if err > bars.yawDeg {
                    var by = "-"
                    if let a = p.brainYaw, let b = s.brainYaw { by = String(format: "%.1f", abs(Self.wrap(b - a)) * 180 / .pi) }
                    out.append(GlitchEvent(kind: "yaw", size: err * k, perStep: err, detail: String(format: "turn=%.1f was=%.1f brainYaw=%@", w * 180 / .pi, w0 * 180 / .pi, by)))
                }
            }
            yawVel = w
        } else { yawVel = nil }
        // pose: a POP, judged one frame late. Vertex velocity v(t-1), v(t), v(t+1) per step in the body's own frame: a pop at t moves fast (|v(t)| over the bar)
        // after moving under a third of that, and then either stops (a snap to a new pose: |v(t+1)| under a third) or goes straight back (a one-frame flicker).
        // A swing, a run's arms or a spring's jiggle keep moving and are not pops. Feet only while the foot pieces are fully out.
        let feetOut = s.blends.first.map { $0 > 0.95 } ?? false && p.blends.first.map { $0 > 0.95 } ?? false
        let armsOut = s.blends.count > 1 && p.blends.count > 1 && s.blends[1] > 0.95 && p.blends[1] > 0.95          // (a capsule fading or put back into the body is hidden: not a pop)
        var lv = [SIMD3<Float>](repeating: .zero, count: s.local.count)
        var worst = [Float](repeating: 0, count: GlitchGroup.allCases.count), worstI = [Int](repeating: -1, count: GlitchGroup.allCases.count)
        for i in 0..<s.local.count {
            lv[i] = (s.local[i] - p.local[i]) / k
            guard let v0 = localVel2, let v1 = localVel, v0.count == lv.count, v1.count == lv.count else { continue }
            let g = Int(s.group[i])
            if g == Int(GlitchGroup.foot.rawValue), !(feetOut && feetOutBefore) { continue }
            if g == Int(GlitchGroup.arm.rawValue), !(armsOut && armsOutBefore) { continue }
            let m = simd_length(v1[i])
            guard m * 100 > bars.poseCm, simd_length(v0[i]) * 3 < m else { continue }
            let after = lv[i]
            guard simd_length(after) * 3 < m || simd_dot(after, v1[i]) < -0.5 * m * m else { continue }
            if m > worst[g] { worst[g] = m; worstI[g] = i }
        }
        for g in GlitchGroup.allCases {
            let cm = worst[Int(g.rawValue)] * 100
            let i = worstI[Int(g.rawValue)]
            if cm > bars.poseCm, i >= 0, let v0 = localVel2, let v1 = localVel {
                let at = p.local[i]
                out.append(GlitchEvent(kind: "pose", size: cm, perStep: cm, detail: String(format: "part=%@ before=%.1f after=%.1f at=%.2f,%.2f,%.2f vi=%d", g.name, simd_length(v0[i]) * 100, simd_length(lv[i]) * 100, at.x, at.y, at.z, Int(s.index.count > i ? s.index[i] : -1))))
                _ = v1
            }
        }
        localVel2 = localVel; localVel = lv; feetOutBefore = feetOut; armsOutBefore = armsOut
        // slide: a foot the brain holds planted (both frames) whose drawn contact patch moved across the floor
        if let f1 = s.feet, let f0 = p.feet, f1.count == 2, f0.count == 2, let m1 = s.footMorph, let m0 = p.footMorph, m1.count == 2, m0.count == 2 {
            for i in 0..<2 {
                guard m1[i] < 0.02 && m0[i] < 0.02, abs(f1[i].minY - f0[i].minY) < 0.003 * k else { planted[i] = 0; continue }          // (a foot leaving or meeting the floor this step is not planted)
                planted[i] += steps
                let cm = simd_distance(f1[i].xz, f0[i].xz) * 100 / k
                if cm > bars.slideCm { out.append(GlitchEvent(kind: "slide", size: cm * k, perStep: cm, detail: "foot=\(i == 0 ? "L" : "R") held=\(planted[i])")) }
            }
        } else { planted = [0, 0] }
        // blends
        let names = ["feet", "arms"]
        for i in 0..<min(s.blends.count, p.blends.count) {
            let db = abs(s.blends[i] - p.blends[i])
            if db / k > bars.blendStep { out.append(GlitchEvent(kind: "blend", size: db, perStep: db / k, detail: "blend=\(i < names.count ? names[i] : "\(i)") from=\(String(format: "%.2f", p.blends[i])) to=\(String(format: "%.2f", s.blends[i]))")) }
        }
        prev = s
        return out
    }

    static func yaw(_ q: simd_quatf) -> Float { let f = q.act(SIMD3<Float>(0, 0, 1)); return atan2f(f.x, f.z) }
    static func wrap(_ a: Float) -> Float { var a = a; while a > .pi { a -= 2 * .pi }; while a < -.pi { a += 2 * .pi }; return a }
}

/// Collapses bursts: one line per (kind, who) burst with its largest size.
nonisolated struct GlitchBurst {
    struct Open { var ev: GlitchEvent; var who: String; var t0: Double; var tLast: Double; var n: Int; var ctx: String }
    var window: Double = 0.25
    private(set) var open: [String: Open] = [:]
    /// Adds an event; returns the bursts that closed (older than the window).
    mutating func add(_ e: GlitchEvent, who: String, ctx: String, now: Double) {
        let key = e.kind + "|" + who + "|" + (e.kind == "pose" || e.kind == "blend" || e.kind == "slide" ? e.detail.prefix(10) : "")
        if var o = open[key], now - o.tLast <= window {
            o.n += 1; o.tLast = now
            if e.perStep > o.ev.perStep { o.ev = e; o.ctx = ctx }
            open[key] = o
        } else {
            open[key] = Open(ev: e, who: who, t0: now, tLast: now, n: 1, ctx: ctx)
        }
    }
    mutating func flush(now: Double, all: Bool = false) -> [Open] {
        var done: [Open] = []
        for (k, o) in open where all || now - o.tLast > window { done.append(o); open[k] = nil }
        return done.sorted { $0.t0 < $1.t0 }
    }
}

extension GameCare {
    /// The white scene wipe over the game view (the largest of every trip's / the bath's / the room switch's): 1 = the world is hidden.
    var glitchWipe: Float { max(bath.wipe, cafe.wipe, groom.wipe, park.wipe, race.wipe, show.wipe, volley.wipe, roomSwitch.wipe) }
}

/// The stage glue: samples, attributes and logs.
@MainActor
final class GlitchProbe {
    nonisolated(unsafe) static var on = false
    static let shared = GlitchProbe()
    nonisolated deinit {}
    var bars = GlitchBars()
    private var cores: [Int: GlitchCore] = [:]
    private var seenFrame: [Int: Int] = [:]
    private var frame = 0
    private var burst = GlitchBurst()
    private var lastScene = ""
    private var lastCamPos: SIMD3<Float>?, lastCamVel: SIMD3<Float>?, lastCamFwd: SIMD3<Float>?
    private var moves: [Int: (name: String, prev: String, t: Double)] = [:]
    private var sceneSteps: [String: Int] = [:]
    private var stepsSinceSum = 0
    private var counts: [String: Int] = [:]
    private var groups: [Int: (sig: [Int], group: [UInt8], idx: [Int32])] = [:]
    var tag = ""

    static func configure(defaults: UserDefaults = .standard) {
        guard DevArgs.enabled else { on = false; return }
        on = defaults.integer(forKey: "GlitchProbe") != 0
        if on { shared.bars = GlitchBars.fromDefaults(defaults); shared.burst.window = shared.bars.burstS
            NSLog("[glitch] probe on jump=%.3f yaw=%.1f pose=%.1f slide=%.2f cam=%.2f hitch=%.0f", shared.bars.jumpU, shared.bars.yawDeg, shared.bars.poseCm, shared.bars.slideCm, shared.bars.camU, shared.bars.hitchMs) }
    }

    /// Which drawn vertices to sample and their group (built once per skinner layout).
    private func layout(_ sk: Skinner, key: Int) -> (group: [UInt8], idx: [Int32]) {
        let sig = Self.layoutSignature(sk)          // (the blocks are configured after the first frames: a layout is rebuilt when they change)
        if let g = groups[key], g.sig == sig { return (g.group, g.idx) }
        let l = Self.buildLayout(sk)
        groups[key] = (sig, l.group, l.idx)
        NSLog("[glitch] layout key=%d verts=%d egg=%d arms=%@ feet=%@ tail=%d", key, sk.vertexCount, l.egg, sk.armFirst.map(String.init).joined(separator: ","), sk.beanFirst.map(String.init).joined(separator: ","), sk.tailFirst)
        return (l.group, l.idx)
    }

    nonisolated static func layoutSignature(_ sk: Skinner) -> [Int] { [sk.vertexCount, sk.tailFirst] + sk.armFirst + sk.beanFirst }

    /// The sampled drawn vertices (every 7th of the body egg, every 3rd of the limb / feature blocks) and their group.
    nonisolated static func buildLayout(_ sk: Skinner) -> (group: [UInt8], idx: [Int32], egg: Int) {
        let n = sk.vertexCount
        var gr = [UInt8](repeating: GlitchGroup.feature.rawValue, count: n)
        var starts: [Int] = []
        for f in sk.armFirst where f >= 0 { starts.append(f); for i in f..<min(n, f + ArmCapsule.vertexCount) { gr[i] = GlitchGroup.arm.rawValue } }
        for f in sk.beanFirst where f >= 0 { starts.append(f); for i in f..<min(n, f + FootBean.vertexCount) { gr[i] = GlitchGroup.foot.rawValue } }
        if sk.tailFirst >= 0 { starts.append(sk.tailFirst); for i in sk.tailFirst..<min(n, sk.tailFirst + TailBean.vertexCount) { gr[i] = GlitchGroup.tail.rawValue } }
        let egg = starts.min() ?? n
        for i in 0..<min(egg, n) { gr[i] = GlitchGroup.body.rawValue }
        var idx: [Int32] = [], g: [UInt8] = []
        for i in 0..<n {
            let stride = gr[i] == GlitchGroup.body.rawValue ? 7 : 3
            if i % stride == 0 { idx.append(Int32(i)); g.append(gr[i]) }
        }
        return (g, idx, egg)
    }

    /// One body's drawn state (`dyn` = its skinned vertices, 6 floats each) as the core compares it. The stage and the headless tests build it the same way.
    static func makeSample(sim: SoftBody, skinner sk: Skinner, brain: BlobBrain?, dyn: UnsafePointer<Float>, group g: [UInt8], idx: [Int32]) -> GlitchSample {
        let pose = sim.bodyPose()
        let inv = pose.rotation.inverse
        var local = [SIMD3<Float>](); local.reserveCapacity(idx.count)
        for i in idx { let o = 6 * Int(i); local.append(inv.act(SIMD3(dyn[o], dyn[o + 1], dyn[o + 2]) - pose.centroid)) }
        var feet: [(minY: Float, xz: SIMD2<Float>)]? = nil
        if sk.beansActive, sk.beanBlend > 0.9, sk.beanFirst.count == 2 {
            var fs: [(minY: Float, xz: SIMD2<Float>)] = []
            for s in 0..<2 {
                let f = sk.beanFirst[s]
                var mn: Float = .greatestFiniteMagnitude
                var c = SIMD2<Float>.zero
                for i in 0..<FootBean.vertexCount { let o = 6 * (f + i); mn = min(mn, dyn[o + 1]); c += SIMD2(dyn[o], dyn[o + 2]) }          // (the whole piece's centre: a contact patch jumps between heel and toe as the boot rocks)
                fs.append((mn, c / Float(FootBean.vertexCount)))
            }
            feet = fs
        }
        return GlitchSample(centroid: pose.centroid, rotation: pose.rotation, tilt: pose.tilt, moveSerial: sim.moveSerial, brainYaw: brain?.yaw,
                            local: local, group: g, index: idx, feet: feet, blends: [sk.beanBlend, sk.armBlend],
                            footMorph: brain.map { b in (0..<2).map { s in b.feet.swinging && b.feet.side == s ? 1 : b.beanMorphLast[s] } })          // (a foot in a step's swing is never planted, even when the step does not lift it)
    }

    private func moveName(_ b: BlobBrain?, asleep: Bool) -> String {
        guard let b else { return "-" }
        return FootLog.MoveKey(script: b.scriptKindName, idle: b.idleState.kind, activity: b.activity, gait: b.gait.phase, volley: b.volley.active ? b.volley.phase : nil,
                               race: b.race.active, held: b.held, asleep: asleep).name
    }

    /// Once per drawn frame after the skin pass. `bodies`: (key, actor, drawn vertex pointer) for every body skinned THIS frame.
    func record(bodies: [(key: Int, actor: JellyActor, dyn: UnsafeMutablePointer<Float>)], steps: Int, scene: String, touching: Bool, cover: Bool, wipe: Float,
                cam: CameraState, rawIntervalMs: Double, cpuMs: Double) {
        guard GlitchProbe.on else { return }
        frame += 1
        let now = CACurrentMediaTime()
        let sceneChanged = scene != lastScene
        if sceneChanged {
            if !lastScene.isEmpty { NSLog("[glitch] scene %@ -> %@", lastScene, scene) }
            lastScene = scene
        }
        sceneSteps[scene, default: 0] += steps; stepsSinceSum += steps
        let ctxBase = "scene=\(scene) touch=\(touching ? 1 : 0) cover=\(cover ? 1 : 0) wipe=\(String(format: "%.2f", wipe))\(tag.isEmpty ? "" : " tag=\(tag)")"
        // camera
        if let lc = lastCamPos {          // the eye's move against the move the frame before (a smooth dolly reads 0; a cut or a snap reads its size); and the view direction's turn
            let v = cam.pos - lc
            if let v0 = lastCamVel {
                let err = simd_distance(v, v0)
                let turn = lastCamFwd.map { acosf(max(-1, min(1, simd_dot(simd_normalize($0), simd_normalize(cam.fwd))))) * 180 / .pi } ?? 0
                if err > bars.camU { burst.add(GlitchEvent(kind: "camera", size: err, perStep: err, detail: String(format: "sceneChange=%d move=%.3f was=%.3f turn=%.1f", sceneChanged ? 1 : 0, simd_length(v), simd_length(v0), turn)), who: "cam", ctx: ctxBase, now: now) }
            }
            lastCamVel = v
        }
        lastCamPos = cam.pos; lastCamFwd = cam.fwd
        if rawIntervalMs > bars.hitchMs { burst.add(GlitchEvent(kind: "hitch", size: Float(rawIntervalMs), perStep: Float(rawIntervalMs), detail: String(format: "cpu=%.1f steps=%d", cpuMs, steps)), who: "frame", ctx: ctxBase, now: now) }
        for (key, a, dyn) in bodies {
            let mv = moveName(a.brain, asleep: a.asleep)
            var m = moves[key] ?? (mv, "(first)", now)
            if m.name != mv { m = (mv, m.name, now) }
            moves[key] = m
            var core = cores[key] ?? { var c = GlitchCore(); c.bars = bars; return c }()
            if sceneChanged || seenFrame[key] != frame - 1 { core.forget() }
            seenFrame[key] = frame
            let sk = a.skinner
            let (g, idx) = layout(sk, key: key)
            let s = Self.makeSample(sim: a.sim, skinner: sk, brain: a.brain, dyn: UnsafePointer(dyn), group: g, idx: idx)
            let evs = core.observe(s, steps: steps)
            cores[key] = core
            if evs.isEmpty { continue }
            let ctx = "\(ctxBase) move=\(m.name) prev=\(m.prev) since=\(Int((now - m.t) * 1000)) steps=\(steps) slept=\(a.asleep ? 1 : 0)"
            for e in evs { burst.add(e, who: "\(key)", ctx: ctx, now: now) }
        }
        for o in burst.flush(now: now) { emit(o) }
        if stepsSinceSum >= 600 {
            stepsSinceSum = 0
            let sc = sceneSteps.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            let cn = counts.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            NSLog("[glitch] sum steps %@ events %@", sc, cn)
        }
    }

    private func emit(_ o: GlitchBurst.Open) {
        counts[o.ev.kind, default: 0] += 1
        NSLog("[glitch] kind=%@ who=%@ size=%.3f step=%.3f n=%d %@ %@", o.ev.kind, o.who, o.ev.size, o.ev.perStep, o.n, o.ev.detail, o.ctx)
    }
}
#endif
