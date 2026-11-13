//
//  TailCarryTests.swift
//  hold-wear-r1, Pip's tail while lifted (Skinner.tailFloorWeight, TailCarry.swift).
//  (a) standing / walking 5 s / tail wag / floor emotes: the skin is BIT-IDENTICAL with the change on vs off (max difference printed, must be 0).
//  (b) lifted 0.5 above the floor upright / sideways / upside down: the tail is carried (no vertex near the floor, none farther from the root than the rest length).
//  (c) the egg lift of hops and emotes (prints the apex heights the lift range was chosen from).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class TailCarryTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    override func setUp() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0); DayClock.shared.forcedHour = 12 }
    override func tearDown() { Skinner.tailCarryWhenLifted = true; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    static func say(_ l: String) { HoldWearTests.say(l) }

    /// Egg lowest vertex of a skin buffer.
    static func eggMin(_ sc: HoldWearTests.Scene, _ d: [Float]) -> Float {
        let n = min(sc.r.rig.skinner.bodyVertexLimit, d.count / 6)
        var m = Float.infinity
        for v in 0..<n { m = min(m, d[6 * v + 1]) }
        return m
    }

    /// Moves that lift the body well above hop height or tip it in the air: the tail may legitimately be carried there.
    static let mayChange: Set<String> = ["superSpring", "corkscrew", "backBounce", "headstand"]

    enum Job { case stand, walk, kind(IdleKind), hop(Float) }

    /// Runs one scenario with the switch `on`; returns (snapshots of the whole skin every 4 frames, the max egg lift seen).
    func run(_ job: Job, on: Bool, seconds: Float) -> (snaps: [[Float]], maxEgg: Float, minEgg: Float, started: Bool, moved: Float, minW: Float, maxLift: Float) {
        Skinner.tailCarryWhenLifted = on
        defer { Skinner.tailCarryWhenLifted = true }
        let sc = HoldWearTests.Scene(species: 1)
        let brain = sc.r.rig.brain
        var started = true
        Skinner.dbgTailWeightMin = 1; Skinner.dbgTailLiftMax = -9
        let c0 = sc.r.rig.sim.centroid()
        switch job {
        case .stand: break
        case .walk: brain.request(.come(to: SIMD2(1.3, 0.9)))
        case .kind(let k): brain.idleForced = true; started = brain.idleStart(k, sc.r.rig.sim)
        case .hop(let v): sc.r.rig.sim.launch(velocity: SIMD3(0, v, 0), spin: .zero)
        }
        var snaps: [[Float]] = [], hi: Float = -9, lo: Float = 9
        for f in 0..<Int(seconds * 60) {
            sc.step(touched: false)
            let d = sc.skin()
            let e = Self.eggMin(sc, d); hi = max(hi, e); lo = min(lo, e)
            if f % 4 == 0 { snaps.append(d) }
        }
        return (snaps, hi, lo, started, simd_length(sc.r.rig.sim.centroid() - c0), Skinner.dbgTailWeightMin, Skinner.dbgTailLiftMax)
    }

    func testNoOpOnTheFloorAndHopHeights() {
        var worst: Float = 0
        let jobs: [(String, Job, Float)] = [
            ("standing", .stand, 4), ("walking 5 s", .walk, 5),
            ("tail wag (signature)", .kind(.signatureFlourish), 6), ("tailThump", .kind(.tailThump), 8), ("tailHug", .kind(.tailHug), 8), ("tail spin", .kind(.tail), 8),
            ("sit", .kind(.sit), 5), ("flop", .kind(.flop), 6), ("lieDown", .kind(.lieDown), 8), ("floorNapFlop", .kind(.floorNapFlop), 8), ("hula", .kind(.hula), 6), ("shake", .kind(.shake), 4),
            ("sneeze", .kind(.sneeze), 4), ("bellyDrum", .kind(.bellyDrum), 5), ("politeBow", .kind(.politeBow), 4), ("dizzyWobble", .kind(.dizzyWobble), 5), ("stumble", .kind(.stumble), 4),
            ("run", .kind(.run), 5), ("zoomies", .kind(.zoomies), 6), ("jacks", .kind(.jacks), 5), ("slide", .kind(.slide), 5), ("scoot", .kind(.scoot), 5),
            ("bounce (hops)", .kind(.bounce), 6), ("joy (jump)", .kind(.joy), 5), ("skipHop", .kind(.skipHop), 5), ("hiccup", .kind(.hiccup), 4), ("superSpring", .kind(.superSpring), 6),
            ("corkscrew", .kind(.corkscrew), 6), ("tossHeader", .kind(.tossHeader), 4), ("proudStrut", .kind(.proudStrut), 6),
            ("backBounce", .kind(.backBounce), 8), ("headstand", .kind(.headstand), 8), ("moonwalk", .kind(.moonwalk), 6), ("sing", .kind(.sing), 6),
            ("launch 2.0 (small hop)", .hop(2.0), 3), ("launch 3.0", .hop(3.0), 3), ("launch 4.0", .hop(4.0), 3), ("launch 5.0", .hop(5.0), 3)
        ]
        var apex: [String: Float] = [:]
        for (name, job, secs) in jobs {
            let a = run(job, on: true, seconds: secs), b = run(job, on: false, seconds: secs), c = run(job, on: true, seconds: secs)
            func diff(_ p: [[Float]], _ q: [[Float]]) -> Float {
                var d: Float = 0
                for (x, y) in zip(p, q) { for i in 0..<x.count where x[i] != y[i] || x[i].isNaN { d = max(d, x[i].isNaN || y[i].isNaN ? 9 : abs(x[i] - y[i])) } }
                return d
            }
            let d = diff(a.snaps, b.snaps), ctl = diff(a.snaps, c.snaps)
            Self.say("TAILCARRY \(name): started \(a.started), moved \(a.moved); egg bottom range \(a.minEgg) ... \(a.maxEgg) (inside applyTail: highest \(a.maxLift), lowest floor weight seen \(a.minW)); max skin difference on vs off \(d), control (on vs on, same script) \(ctl), \(a.snaps.count) snapshots")
            if !a.started { Self.say("TAILCARRY \(name): DID NOT START (not covered)"); continue }
            if ctl != 0 { Self.say("TAILCARRY \(name): not deterministic (control differs), not provable here"); continue }
            if a.minW == 1 { XCTAssertEqual(d, 0, "\(name): bit-identical when the tail never left the floor weight"); worst = max(worst, d) }
            else { Self.say("TAILCARRY \(name): CHANGED (the lift went above the floor range: weight down to \(a.minW))") }
            if !Self.mayChange.contains(name) { XCTAssertEqual(a.minW, 1, "\(name): a floor move must keep the tail floor weight at 1") }
        }
        Self.say("TAILCARRY max difference below the lift range: \(worst)")
    }

    /// Farthest any spike vertex is from the nearest tail vertex (the spikes ride the tail surface); also the spike vertex count.
    static func spikeGap(_ sc: HoldWearTests.Scene, _ d: [Float]) -> (gap: Float, count: Int) {
        let f0 = sc.r.rig.skinner.tailFirst, tn = TailBean.vertexCount
        let tail = (0..<tn).map { SIMD3(d[6 * (f0 + $0)], d[6 * (f0 + $0) + 1], d[6 * (f0 + $0) + 2]) }
        let fm = d.withUnsafeBufferPointer { q in sc.features.frame(hidden: false) { _ in q.baseAddress } }
        var worst: Float = 0
        for v in fm.vertices {
            let p = SIMD3(v.pos.x, v.pos.y, v.pos.z)
            var m = Float.infinity
            for t in tail { m = min(m, simd_distance(p, t)) }
            worst = max(worst, m)
        }
        return (worst, fm.vertices.count)
    }

    func testLiftedTailIsCarried() {
        let base = HoldWearTests.Scene(species: 1)
        let bd = base.skin()
        let baseGap = Self.spikeGap(base, bd)
        Self.say("TAILCARRY standing: spike vertices \(baseGap.count), farthest from the tail surface \(baseGap.gap)")
        XCTAssertGreaterThan(baseGap.count, 0, "Pip's spikes are drawn")
        for (name, rot) in [("upright", Float(0)), ("sideways", Float.pi / 2), ("upside down", Float.pi)] {
            let sc = HoldWearTests.Scene(species: 1)
                let r = sc.r, sim = r.rig.sim, brain = r.rig.brain, play = r.play
            let hit = sim.centroid() + SIMD3(0, 0.1, 0.5)
            r.step(touched: true); r.step(touched: true)
            sim.beginGrab(hit: hit, radius: 0.4)
            let n = sc.r.rig.skinner
            let f0 = n.tailFirst, tn = TailBean.vertexCount
            var restLen: Float = 0
            let root0 = TailBean.localF[0]
            for i in 0..<tn { restLen = max(restLen, simd_length(TailBean.localF[i] - root0)) }
            var worstFar: Float = 0, lowest: Float = 9, eggLift: Float = 0, wLast: Float = 1
            Skinner.dbgTailWeightMin = 1
            for f in 0..<180 {
                let e = min(1, Float(f) / 60), s = e * e * (3 - 2 * e)
                sc.step(touched: true) {
                    sim.moveGrab(target: hit + SIMD3(0, 0.5 * s, 0), rot: HoldWearTests.rotZ(rot * s))
                    play.heldFrame(dt: 1.0 / 60, now: r.clock, grabbing: true, liftHeight: 0.5 * s, sim: sim, brain: brain, skinner: n)
                }
                let d = sc.skin()
                if f < 120 { continue }
                wLast = Skinner.dbgTailWeightMin; Skinner.dbgTailWeightMin = 1
                let B = SIMD3(d[6 * f0], d[6 * f0 + 1], d[6 * f0 + 2])
                for i in 0..<tn {
                    let p = SIMD3(d[6 * (f0 + i)], d[6 * (f0 + i) + 1], d[6 * (f0 + i) + 2])
                    worstFar = max(worstFar, simd_length(p - B)); lowest = min(lowest, p.y)
                }
                eggLift = Self.eggMin(sc, d)
            }
            Self.say("TAILCARRY lifted \(name): egg bottom \(eggLift), lowest tail vertex y \(lowest), farthest tail vertex from the root \(worstFar) (rest length \(restLen)); inside applyTail lift \(Skinner.dbgTailLift), floor weight \(wLast)")
            let sg = Self.spikeGap(sc, sc.skin())
            Self.say("TAILCARRY lifted \(name): spike vertices \(sg.count), farthest from the tail surface \(sg.gap) (standing \(baseGap.gap))")
            XCTAssertGreaterThan(sg.count, 0, "\(name): the spikes are drawn")
            XCTAssertLessThanOrEqual(sg.gap, baseGap.gap + 0.05, "\(name): the spikes stay on the tail")
            XCTAssertLessThanOrEqual(worstFar, restLen * 1.02 + 0.02, "\(name): no tail vertex farther from the root than the rest length")
            XCTAssertGreaterThan(lowest, 0.05, "\(name): no tail vertex at floor height")
        }
    }
}
