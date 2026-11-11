//
//  RacePullFlowTests.swift
//  Stage B1 of the race's pull-back-and-release control: a pull race runs start to finish in the real game with real bodies (GameCare + three Jellies ticked like the
//  stage does), driven by `RaceFlow.release(pull:)`. The player's script is the "steady green": every step, if no release is buffered, release at 0.80.
//  Each test prints its numbers (MotionLog).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RacePullFlowTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    /// A rival source whose racers lose focus easily (so a look-around pause happens).
    struct LowFocusSource: RivalSource {
        func rivals(count: Int, player: RacerStats, playerTint: SIMD3<Float>, seed: UInt64) -> [Rival] {
            LocalRivalSource().rivals(count: count, player: player, playerTint: playerTint, seed: seed).map { var r = $0; r.stats = RacerStats(waddle: 0.7, focus: 0.0); return r }
        }
    }

    /// One race with real bodies.
    @MainActor
    final class PullRace {
        let room = RaceTripTests.Room()
        var care: GameCare { room.care }
        let dt: Float
        var n = 0
        var log: [(n: Int, e: RaceEvent)] = []
        var script: Float? = 0.80
        var headless: RaceSim?
        var perStep: ((PullRace) -> Void)?
        let tier: CourseTier
        init(tier: CourseTier, seed: UInt64, source: RivalSource = LocalRivalSourceFixed(waddle: 0.7), amplitude: Float = 1, taps: Bool = false, playerFocus: Float? = nil) {
            RacePullFlowTests.keep.append(room)
            self.tier = tier
            dt = room.actors[0].sim.stepDt
            let care = room.care
            for b in CourseTier.allCases where b.index < tier.index { care.race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
            care.race.courseTier = tier
            care.race.rivalSource = source
            care.race.autoRate = nil
            if !taps { care.race.control = .pull }
            if let f = playerFocus { care.jelly(0)!.stats.set(focus: f) }
            for a in room.actors { a.brain?.amplitude = amplitude }
            care.race.eventTap = { [unowned self] e in self.log.append((self.n, e)) }
            care.startRace(jelly: 0, seed: seed)
            var k = 0
            while care.race.sim == nil, k < 900 { n += 1; room.step(); k += 1 }
            headless = care.race.sim          // (a copy, untouched: the flow does not tick the sim before the countdown)
        }
        var sim: RaceSim? { care.race.sim }
        func body(_ k: Int) -> JellyActor { room.actors[care.raceBook.racers[k]] }
        func step() {
            n += 1
            if let s = care.race.sim, care.race.phase == .racing, let p = script, !s.pullState(0).buffered { _ = care.race.release(pull: p) }
            room.step()
            perStep?(self)
        }
        /// Runs until the results (or `maxSeconds`); false = no results.
        @discardableResult
        func runToResults(maxSeconds: Float = 150, until: ((PullRace) -> Bool)? = nil) -> Bool {
            let end = n + Int(maxSeconds * 60)
            while n < end, care.race.active, !care.race.hasResults { step(); if let u = until, u(self) { break } }
            return care.race.hasResults
        }
        func events(_ racer: Int) -> [(n: Int, e: RaceEvent)] { log.filter { $0.e.racer == racer } }
    }

    /// The same race with no bodies: every sense true, the same script.
    static func headlessRun(_ h0: RaceSim, script: Float?, dt: Float) -> (sim: RaceSim, log: [(n: Int, e: RaceEvent)]) {
        var h = h0, n = 0
        var log: [(n: Int, e: RaceEvent)] = []
        while h.phase != .results, n < 60 * 150 {
            n += 1
            if h.phase == .running || h.phase == .finishing, let p = script, !h.pullState(0).buffered { _ = h.playerRelease(pull: p) }
            h.tick(dt: dt)
            for e in h.takeEvents() { log.append((n, e)) }
        }
        return (h, log)
    }

    /// Per hop of racer `r`: the seconds from `.hop` to `.landed` minus (crouch + air).
    static func excess(_ log: [(n: Int, e: RaceEvent)], racer r: Int, dt: Float) -> [(n: Int, crouch: Float, air: Float, extra: Float)] {
        var out: [(Int, Float, Float, Float)] = []
        var open: (n: Int, crouch: Float, air: Float)?
        for (n, e) in log {
            switch e {
            case .hop(let k, _, _, let air, let crouch, _, _) where k == r: open = (n, crouch, air)
            case .landed(let k) where k == r: if let o = open { out.append((o.n, o.crouch, o.air, Float(n - o.n) * dt - (o.crouch + o.air))); open = nil }
            default: break
            }
        }
        return out
    }

    // MARK: 1

    func testAPullRaceRunsToTheResultsOnEveryCourse() {
        let seeds: [CourseTier: UInt64] = [.puddle: 3, .ripple: 5, .splash: 7, .wave: 9, .tsunami: 11]
        for tier in CourseTier.allCases {
            let r = PullRace(tier: tier, seed: seeds[tier]!)
            XCTAssertTrue(r.runToResults(), "\(tier): results reached")
            guard let s = r.sim else { XCTFail("\(tier): no sim"); continue }
            let hops = r.events(0).filter { if case .hop = $0.e { return true } else { return false } }.count
            let time = s.racers[0].finishTime
            MotionLog.write(String(format: "PULLFLOW course %@ seed %d: results at step %d, player finished=%d time %@ s, %d hops, place %@; rivals finished %@", "\(tier)", Int(seeds[tier]!), r.n, s.playerFinished ? 1 : 0, time.map { String(format: "%.2f", $0) } ?? "-", hops, s.playerPlace.map { "\($0)" } ?? "-", "\(s.racers.dropFirst().map { $0.finished })"))
            XCTAssertTrue(s.playerFinished, "\(tier): the player finished")
            XCTAssertEqual(s.placings.count, s.racers.count, "\(tier): everybody is placed")
            for (k, p) in s.placings.enumerated() { XCTAssertTrue(p.time != nil || s.racers[p.racer].finished == false, "\(tier): placing \(k)") }
            XCTAssertTrue(s.racers.allSatisfy { $0.finished }, "\(tier): every racer finished")
            XCTAssertGreaterThan(hops, 5, "\(tier): the player hopped")
        }
    }

    // MARK: 2 and 10

    /// The player's finish time with bodies against the same race without; the per-hop lateness table.
    private func pace(_ tier: CourseTier, seed: UInt64, amplitude: Float = 1, label: String) {
        let r = PullRace(tier: tier, seed: seed, amplitude: amplitude)
        let h = Self.headlessRun(r.headless!, script: 0.80, dt: r.dt)
        XCTAssertTrue(r.runToResults(), "\(label): results reached")
        let tb = r.sim?.racers[0].finishTime ?? -1, th = h.sim.racers[0].finishTime ?? -1
        let ex = Self.excess(r.log, racer: 0, dt: r.dt), exh = Self.excess(h.log, racer: 0, dt: r.dt)
        func stats(_ a: [(n: Int, crouch: Float, air: Float, extra: Float)]) -> (mean: Float, max: Float) { (a.map(\.extra).reduce(0, +) / Float(max(a.count, 1)), a.map(\.extra).max() ?? 0) }
        let sb = stats(ex), sh = stats(exh)
        MotionLog.write(String(format: "PULLPACE %@: finish with bodies %.3f s, headless %.3f s, ratio %.4f (%+.2f %%); hops %d / %d; extra air-time per hop (s, over crouch + air): bodies mean %.4f max %.4f (%.2f steps), headless mean %.4f max %.4f", label, tb, th, tb / max(th, 1e-3), 100 * (tb / max(th, 1e-3) - 1), ex.count, exh.count, sb.mean, sb.max, sb.max / r.dt, sh.mean, sh.max))
        MotionLog.write("PULLPACE \(label) table (step, crouch, air, extra in steps):")
        for (i, x) in ex.enumerated() { MotionLog.write(String(format: "PULLPACE %@  hop %2d step %4d crouch %.3f air %.3f extra %+.4f s = %.2f steps", label, i, x.n, x.crouch, x.air, x.extra, x.extra / r.dt)) }
        XCTAssertGreaterThan(tb, 0, "\(label): the player finished with bodies")
        XCTAssertEqual(tb / max(th, 1e-3), 1, accuracy: 0.04, "\(label): finish time within 4 % of the headless race")
        XCTAssertLessThanOrEqual(sb.max, 2 * r.dt + 1e-4, "\(label): no hop lands more than 2 steps later than the model's crouch + air")
    }

    func testTheBodyKeepsTheModelsPace() {
        pace(.puddle, seed: 3, label: "puddle")
        pace(.ripple, seed: 5, label: "ripple (bends)")
        pace(.splash, seed: 7, label: "splash (bends + bars)")
    }

    func testReduceMotionKeepsThePace() { pace(.puddle, seed: 3, amplitude: 0.5, label: "puddle, Reduce Motion (amplitude 0.5)") }

    // MARK: 3 feet

    private func empty() -> FeetAttachTests.FootFrame { .init(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity) }

    private func feetRace(_ name: String, tier: CourseTier, seed: UInt64) {
        let r = PullRace(tier: tier, seed: seed)
        let room = r.room, care = r.care, rm = MotionRig.renderMesh
        for (k, f) in [JellyFeature.spines, .daisy, .wings].enumerated() {
            let a = room.actors[k]
            a.brain?.feature = f; a.skinner.configureTail(rm); a.skinner.tailOn = f == .spines; a.brain?.skinnerRef = a.skinner
        }
        var dyn = room.actors.map { _ in [Float](repeating: 0, count: rm.vertexCount * 6) }
        let bean: [[[Int32]]] = room.actors.map { _ in [-1, 1].map { side in let f = rm.armCapsule!.beanFirst(side: side); return (f..<(f + FootBean.vertexCount)).map { Int32($0) } } }
        let core: [[[Int32]]] = room.actors.map { a in (0..<2).map { a.brain!.footCoreVertices($0, sim: a.sim, skinner: a.skinner) } }
        var cur = 0, guardHits = [0, 0, 0], guardNote = ["", "", ""], guardPull = [Float](repeating: 0, count: 3)
        Skinner.leashObserver = { s, pull, tether in guardHits[cur] += 1; if pull > guardPull[cur] { guardPull[cur] = pull; guardNote[cur] = "foot \(s) \(tether ? "tether" : "leash") \(String(format: "%.1f", pull * 100)) cm" } }
        defer { Skinner.leashObserver = nil }
        var worst: [String: FeetAttachTests.FootFrame] = [:], frames: [String: Int] = [:]
        var prevJumping = [false, false, false], chainIdx = [0, 0, 0], sinceHop = [999, 999, 999], logSeen = 0
        r.perStep = { r in
            let sim = care.race.sim
            for e in r.log[logSeen...] {
                if case .hop(let ri, _, _, _, _, _, _) = e.e, let k = care.raceBook.racers.indices.contains(ri) ? care.raceBook.racers[ri] : nil, room.actors.indices.contains(k) {
                    if !prevJumping[k] { chainIdx[k] = 0 } else { chainIdx[k] += 1 }
                }
            }
            logSeen = r.log.count
            for (k, a) in room.actors.enumerated() {
                a.brain?.refitBeans(a.sim, a.skinner)
                guard sim?.phase == .running || sim?.phase == .finishing, let ri = care.raceBook.racers.firstIndex(of: k), let b = a.brain, b.race.active else { continue }
                cur = k
                a.skinner.update(x: a.sim.x, index: rm.index, into: &dyn[k])
                let beans = a.skinner.beansActive && a.skinner.beanBlend > 0.05
                let pose = a.sim.bodyPose(iterations: 4), c0 = a.sim.restCentroid
                var f = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity)
                for sd in 0..<2 {
                    let ids = beans ? bean[k][sd] : core[k][sd]
                    guard !ids.isEmpty else { continue }
                    var lo = Float.infinity, cx: Float = 0, cy: Float = 0, cz: Float = 0, deepest = Float.infinity, wm = SIMD3<Float>.zero
                    for id in ids {
                        let o = 6 * Int(id), p = SIMD3(dyn[k][o], dyn[k][o + 1], dyn[k][o + 2]); wm += p
                        let q = c0 + pose.rotation.inverse.act(p - pose.centroid)
                        lo = min(lo, q.y); cx += q.x; cy += q.y; cz += q.z
                        deepest = min(deepest, Float(BobForm.bodySDF(SIMD3(Double(abs(q.x)), Double(q.y), Double(q.z)))))
                    }
                    let m = Float(ids.count)
                    f.soleRise = max(f.soleRise, lo); f.centreHeight = max(f.centreHeight, cy / m); f.radius = max(f.radius, hypotf(cx / m, cz / m)); f.overlap = max(f.overlap, deepest)
                    if !beans {
                        wm /= m; var ext: Float = 0
                        for id in ids { let o = 6 * Int(id); ext = max(ext, simd_distance(SIMD3(dyn[k][o], dyn[k][o + 1], dyn[k][o + 2]), wm)) }
                        f.stretch = max(f.stretch, ext / FeetAttachTests.coreRestExtent[sd])
                    }
                }
                let jumping = b.race.jumping
                if jumping { sinceHop[k] = 0 } else { sinceHop[k] += 1 }
                var tag: String
                if b.race.stumbleT > 0 { tag = "trip" }
                else if b.race.pullDone { tag = "coast" }
                else if jumping { tag = chainIdx[k] == 0 ? "first hop" : "chain hop" }
                else if sinceHop[k] < 40 { tag = "stands after a hop" }
                else { tag = "stands" }
                prevJumping[k] = jumping
                _ = ri
                let key = "\(k) \(tag) \(beans ? "bean" : "embedded")"
                var w = worst[key] ?? self.empty()
                FeetAttachTests.accumulate(&w, f); worst[key] = w; frames[key, default: 0] += 1
            }
        }
        XCTAssertTrue(r.runToResults(), "\(name): results reached")
        for k in worst.keys.sorted() { FeetAttachTests.check("pull race \(name) racer \(k)", worst[k]!, frames: frames[k]!, core: k.hasSuffix("embedded")) }
        for k in 0..<3 { MotionLog.write("PULLFEET \(name) racer \(k): guard hits \(guardHits[k]) (\(guardNote[k]))"); XCTAssertEqual(guardHits[k], 0, "\(name) racer \(k): the leash / tether moved a foot piece (\(guardNote[k]))") }
        for tag in ["first hop", "chain hop", "coast"] { XCTAssertGreaterThan((frames["0 \(tag) bean"] ?? 0) + (frames["0 \(tag) embedded"] ?? 0), 0, "\(name): the player's frames in '\(tag)' were measured") }
        MotionLog.write("PULLFEET \(name): frames per phase (player): " + frames.filter { $0.key.hasPrefix("0 ") }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
    }

    func testFeetStayAttachedThroughAPullRace() {
        feetRace("puddle", tier: .puddle, seed: 3)
        feetRace("splash (bars)", tier: .splash, seed: 7)
    }

    // MARK: 4

    func testHopsLandOnTheLaneAndFaceAlongIt() {
        let r = PullRace(tier: .wave, seed: 9)
        var seen = 0
        var pending: [(k: Int, n: Int)] = []
        var worstLat: (d: Float, note: String) = (0, ""), worstYaw: (d: Float, note: String) = (0, "")
        var landings = 0, faced = 0
        r.perStep = { r in
            guard let sim = r.sim else { return }
            for e in r.log[seen...] {
                if case .landed(let k) = e.e { pending.append((k, e.n)) }
            }
            seen = r.log.count
            for p in pending where r.n == p.n {
                let c = r.body(p.k).sim.centroid(), pos = SIMD2(c.x, c.z)
                let lane = sim.racers[p.k].lane
                let s = sim.course.progress(of: pos, lane: lane, near: sim.racers[p.k].dist)
                let lat = abs(sim.course.lateral(of: pos, lane: lane, at: s))
                landings += 1
                if lat > worstLat.d { worstLat = (lat, String(format: "racer %d step %d s %.2f", p.k, p.n, s)) }
            }
            for p in pending where r.n == p.n + 18 {
                let a = r.body(p.k)
                let yaw = a.sim.bodyPose(iterations: 4).yaw, c = a.sim.centroid()
                let lane = sim.racers[p.k].lane
                let s = sim.course.progress(of: SIMD2(c.x, c.z), lane: lane, near: sim.racers[p.k].dist)
                let d = abs(wrapAngle(yaw - sim.course.pose(at: s).heading)) * 180 / .pi
                faced += 1
                if d > worstYaw.d { worstYaw = (d, String(format: "racer %d landing step %d s %.2f turn radius %@", p.k, p.n, s, "\(String(describing: sim.course.turnRadius(at: s)))")) }
            }
            pending.removeAll { r.n >= $0.n + 18 }
        }
        XCTAssertTrue(r.runToResults())
        MotionLog.write(String(format: "PULLLANE wave: %d landings, worst distance from the lane line %.3f u (%@); %d facings 0.3 s later, worst %.1f deg (%@)", landings, worstLat.d, worstLat.note, faced, worstYaw.d, worstYaw.note))
        XCTAssertGreaterThan(landings, 20)
        XCTAssertLessThanOrEqual(worstLat.d, 0.06, "a landing is on his lane: \(worstLat.note)")
        XCTAssertLessThanOrEqual(worstYaw.d, 20, "0.3 s after a landing he faces along the lane: \(worstYaw.note)")
    }

    // MARK: 5

    func testNoTeleportAndNoSpin() {
        for (tier, seed) in [(CourseTier.puddle, UInt64(3)), (.wave, 9)] {
            let r = PullRace(tier: tier, seed: seed)
            var prevPos = [SIMD2<Float>?](repeating: nil, count: 3), prevYaw = [Float?](repeating: nil, count: 3), prevSpot = [SIMD2<Float>?](repeating: nil, count: 3)
            var wMove: (d: Float, note: String) = (0, ""), wYaw: (d: Float, note: String) = (0, ""), wSpot: (d: Float, note: String) = (0, "")
            r.perStep = { r in
                guard r.care.race.phase == .racing, !r.care.race.hasResults, r.care.race.wipe == 0 else { return }
                for k in 0..<3 {
                    let a = r.body(k), c = a.sim.centroid(), pos = SIMD2(c.x, c.z)
                    let yaw = a.sim.bodyPose(iterations: 4).yaw, spot = a.brain!.raceSpot
                    let note = "\(tier) racer \(k) step \(r.n) script \(a.brain!.script) gait \(a.brain!.gait.phase)"
                    if let p = prevPos[k], simd_distance(p, pos) > wMove.d { wMove = (simd_distance(p, pos), note) }
                    if let y = prevYaw[k], abs(wrapAngle(yaw - y)) * 180 / .pi > wYaw.d { wYaw = (abs(wrapAngle(yaw - y)) * 180 / .pi, note) }
                    if let p = prevSpot[k], simd_distance(p, spot) > wSpot.d { wSpot = (simd_distance(p, spot), note) }
                    prevPos[k] = pos; prevYaw[k] = yaw; prevSpot[k] = spot
                }
            }
            XCTAssertTrue(r.runToResults(), "\(tier)")
            MotionLog.write(String(format: "PULLSMOOTH %@: worst centroid move per step %.4f u (%@); worst facing change per step %.2f deg (%@); worst raceSpot move per step %.4f u (%@)", "\(tier)", wMove.d, wMove.note, wYaw.d, wYaw.note, wSpot.d, wSpot.note))
            XCTAssertLessThanOrEqual(wMove.d, 0.06, "centroid teleport: \(wMove.note)")
            XCTAssertLessThanOrEqual(wYaw.d, 8, "spin: \(wYaw.note)")
            XCTAssertLessThanOrEqual(wSpot.d, 0.06, "raceSpot (the camera's point) jumps: \(wSpot.note)")
        }
    }

    // MARK: 6

    func testAfterTheLineHeCoastsAndStands() {
        let r = PullRace(tier: .splash, seed: 7)
        var fin: [Int: Int] = [:]
        var checked: [Int: String] = [:]
        r.perStep = { r in
            for e in r.log where fin[e.e.racer ?? -1] == nil { if case .finished(let k, _) = e.e { fin[k] = e.n } }
            for (k, n0) in fin where r.n == n0 + 180 {
                let b = r.body(k).brain!
                var script = "\(b.script)"
                var ok = false
                if case .race = b.script { ok = !b.feet.active && b.feetInit && b.race.pendingFoot == nil }
                script += " feetActive=\(b.feet.active) feetInit=\(b.feetInit) pending=\(b.race.pendingFoot != nil) jumping=\(b.race.jumping)"
                checked[k] = (ok ? "ok " : "NOT standing ") + script
            }
        }
        XCTAssertTrue(r.runToResults())
        var late: [String] = []
        for k in 0..<3 {
            guard let f = fin[k] else { XCTFail("racer \(k) never finished"); continue }
            for e in r.events(k) where e.n > f { if case .hop = e.e { late.append("racer \(k) hop at step \(e.n) after finishing at \(f)") } }
        }
        MotionLog.write("PULLCOAST finished at steps \(fin.sorted { $0.key < $1.key }), state 3 s after the line: \(checked.sorted { $0.key < $1.key })")
        XCTAssertTrue(late.isEmpty, "no hop after the line: \(late)")
        for k in 0..<3 {
            if let c = checked[k] { XCTAssertTrue(c.hasPrefix("ok"), "racer \(k) 3 s after the line: \(c)") }
            else { MotionLog.write("PULLCOAST racer \(k): results arrived before 3 s after his line (checked at the results instead)") }
        }
        XCTAssertTrue(r.care.race.hasResults)
    }

    // MARK: 7

    func testAReleaseInTheAirIsKept() {
        let r = PullRace(tier: .puddle, seed: 3)
        r.script = nil
        // wait for the race
        while r.n < 60 * 20, !(r.care.race.phase == .racing && r.sim?.phase == .running && r.care.race.buttonsLive) { r.step() }
        XCTAssertTrue(r.care.race.buttonsLive)
        // below the minimum pull: nothing
        XCTAssertEqual(r.care.race.release(pull: 0.10), .ignored, "a release below minPull does nothing")
        XCTAssertFalse(r.sim!.pullState(0).buffered)
        for _ in 0..<40 { r.step() }
        XCTAssertFalse(r.events(0).contains { if case .hop = $0.e { return true } else { return false } }, "no hop of the player after a weak release")
        // a real release hops
        guard case .hopped = r.care.race.release(pull: 0.80) else { return XCTFail("a release on the ground hops") }
        var sawHop = false
        var hop1 = 0
        for _ in 0..<10 { r.step(); if r.events(0).contains(where: { if case .hop = $0.e { return true } else { return false } }) { sawHop = true; hop1 = r.n; break } }
        XCTAssertTrue(sawHop, "the hop leaves")
        // release in the air
        var buffered: RaceRelease = .ignored
        for _ in 0..<60 {
            r.step()
            if r.sim!.pullState(0).inHop, r.body(0).brain!.gait.phase == .air { buffered = r.care.race.release(pull: 0.80); break }
        }
        XCTAssertEqual(buffered, .buffered, "a release in the flight is kept")
        var landedAt = 0, nextHop = 0
        for _ in 0..<120 {
            r.step()
            for e in r.events(0) where e.n >= hop1 {
                if case .landed = e.e, landedAt == 0 { landedAt = e.n }
                if case .hop = e.e, e.n > hop1, nextHop == 0 { nextHop = e.n }
            }
            if nextHop > 0 { break }
        }
        let gap = nextHop - landedAt
        MotionLog.write("PULLBUFFER first hop at step \(hop1), landed at \(landedAt), buffered release hops at \(nextHop): \(gap) steps after landing (landHold \(r.sim!.pullTuning.landHold) s = \(Int((r.sim!.pullTuning.landHold / r.dt).rounded(.up))) steps + 2 allowed)")
        XCTAssertGreaterThan(landedAt, 0); XCTAssertGreaterThan(nextHop, 0)
        XCTAssertLessThanOrEqual(gap, Int((r.sim!.pullTuning.landHold / r.dt).rounded(.up)) + 2, "the kept release leaves within landHold + 2 steps of the landing")
    }

    // MARK: 8

    func testATripShowsAStumbleAndHeGoesOn() {
        var found = false
        for seed in UInt64(1)...UInt64(14) where !found {
            let r = PullRace(tier: .wave, seed: seed)
            r.script = 0.5
            var trip: (n: Int, landed: Int)?
            var kickAt = 0, stumbleAt = 0, landedN = 0
            var yTrip: [Float] = [], yNormal: [Float] = []
            var allowedAt = 0, hopAfter = 0
            var tripSteps: [Int] = []
            r.perStep = { r in
                let b = r.body(0).brain!
                for e in r.log.suffix(6) where e.n == r.n {
                    if case .landed(0) = e.e { landedN = r.n }
                    if case .trip(0) = e.e, trip == nil { trip = (r.n, landedN); tripSteps.append(r.n) }
                }
                if let t = trip {
                    if kickAt == 0, b.jellyKick >= 2.3 { kickAt = r.n }
                    if stumbleAt == 0, b.race.stumbleT > 0 { stumbleAt = r.n }
                    if allowedAt == 0, r.n > t.n, r.sim?.racers[0].tap.stumbling == false { allowedAt = r.n }
                    if hopAfter == 0, r.n > t.n { for e in r.log.suffix(6) where e.n == r.n { if case .hop(0, _, _, _, _, _, _) = e.e { hopAfter = r.n } } }
                    if r.n - t.n < 30 { yTrip.append(r.body(0).sim.centroid().y) }
                }
            }
            r.runToResults(until: { _ in trip != nil && hopAfter > 0 })
            guard let t = trip, hopAfter > 0 else { continue }
            found = true
            let spread: ([Float]) -> Float = { a in (a.dropFirst(6).max() ?? 0) - (a.dropFirst(6).min() ?? 0) }
            _ = yNormal
            MotionLog.write(String(format: "PULLTRIP seed %d: trip event at step %d (landed at %d); stumble timer running at step %d, skin kick >= 2.3 at step %d; model allows a hop at step %d, next hop at step %d (%.3f s after); the centroid height moves %.4f u over the stumble", Int(seed), t.n, t.landed, stumbleAt, kickAt, allowedAt, hopAfter, Float(hopAfter - allowedAt) * r.dt, spread(yTrip)))
            XCTAssertEqual(t.landed, t.n, "the trip arrives with the landing")
            XCTAssertLessThanOrEqual(stumbleAt - t.landed, 3, "the stumble shows within 3 steps of the landing")
            XCTAssertLessThanOrEqual(kickAt - t.landed, 3, "the heavier landing kick is there")
            XCTAssertGreaterThanOrEqual(Float(hopAfter - t.n) * r.dt, RaceTuning.stumbleTime - r.dt - 1e-4, "no hop starts while the model's stumble lasts")
            XCTAssertLessThanOrEqual(Float(hopAfter - allowedAt) * r.dt, 0.15, "the next green release hops at most 0.15 s after the model allows it")
        }
        XCTAssertTrue(found, "a player trip happened in 14 seeds")
    }

    // MARK: 9

    func testALookAroundStillHappens() {
        var found = false
        for seed in UInt64(1)...UInt64(30) where !found {
            let r = PullRace(tier: .puddle, seed: seed, source: LowFocusSource(), playerFocus: 0.0)
            var began: (k: Int, n: Int, looks: Int)?
            var lookAt = 0, ended = 0, hopAfter = 0
            r.perStep = { r in
                for e in r.log.suffix(8) where e.n == r.n {
                    if began == nil, case .pauseBegan(let k) = e.e { began = (k, r.n, r.body(k).brain!.race.looks) }
                    if let b = began, case .pauseEnded(let k) = e.e, k == b.k, ended == 0 { ended = r.n }
                    if ended > 0, case .hop(let k, _, _, _, _, _, _) = e.e, k == began!.k, hopAfter == 0 { hopAfter = r.n }
                }
                if let b = began, lookAt == 0, r.body(b.k).brain!.race.looks > b.looks { lookAt = r.n }
            }
            r.runToResults(until: { _ in hopAfter > 0 })
            guard let b = began else { continue }
            found = true
            MotionLog.write("PULLLOOK seed \(seed): racer \(b.k) pause began at step \(b.n); his look started at step \(lookAt) (\(Float(lookAt - b.n) * r.dt) s later); pause ended at step \(ended); his next hop at step \(hopAfter)")
            XCTAssertGreaterThan(lookAt, 0, "the body looks around")
            XCTAssertLessThanOrEqual(Float(lookAt - b.n) * r.dt, 1.0, "the look starts within 1 s of the pause")
            XCTAssertGreaterThan(ended, 0, "the pause ends")
            XCTAssertGreaterThan(hopAfter, 0, "and he hops again")
        }
        XCTAssertTrue(found, "a pause happened in 30 seeds")
    }

    // MARK: 11

    func testTheTapsRaceIsUntouched() {
        let r = PullRace(tier: .puddle, seed: 3, taps: true)
        XCTAssertEqual(r.care.race.control, .taps)
        r.script = nil
        var foot = 0, tapT: Float = 0, taps = 0
        while r.n < 60 * 25, r.care.race.active, !r.care.race.hasResults {
            if r.care.race.buttonsLive { tapT += r.dt; while tapT >= 1 / 3 { tapT -= 1 / 3; if r.care.race.tap(foot: foot) != .ignored { taps += 1 }; foot = 1 - foot } }
            if r.care.race.buttonsLive { XCTAssertEqual(r.care.race.release(pull: 0.8), .ignored, "release(pull:) is ignored in a taps race"); XCTAssertFalse(r.care.race.ui.pull) }
            r.step()
        }
        let hops = r.log.filter { if case .hop = $0.e { return true } else { return false } }.count
        let steps = r.log.filter { if case .step = $0.e { return true } else { return false } }.count
        MotionLog.write("PULLTAPS taps race: \(taps) taps accepted, \(steps) step events, \(hops) hop events, ui.pull=\(r.care.race.ui.pull), steps of the player's body \(r.room.actors[0].brain!.race.steps), pull flag \(r.room.actors[0].brain!.race.pull)")
        XCTAssertEqual(hops, 0, "no hop event in a taps race")
        XCTAssertGreaterThan(taps, 20)
        XCTAssertGreaterThan(steps, 20)
        XCTAssertFalse(r.room.actors[0].brain!.race.pull)
        XCTAssertFalse(r.care.race.ui.pull)
    }

    // MARK: sounds

    /// What is heard per second in a pull race (clips that got past every guard; the clock is the sim's).
    func testSoundsInAPullRace() {
        let hub = AudioHub.shared
        hub._openForTest(); AudioHub.dryRun = true
        defer { AudioHub.dryRun = false; AudioHub.firedTap = nil; AudioHub.firedVolumeTap = nil; AudioHub.clock = { CACurrentMediaTime() } }
        let r = PullRace(tier: .puddle, seed: 3)
        var fired: [(n: Int, name: String, vol: Float)] = []
        AudioHub.clock = { Double(r.n) / 60 }
        AudioHub.firedVolumeTap = { name, vol in fired.append((r.n, name, vol)) }
        var t0 = 0
        r.perStep = { r in if t0 == 0, r.sim?.phase == .running { t0 = r.n } }
        XCTAssertTrue(r.runToResults())
        let t1 = r.sim?.racers.compactMap(\.finishTime).max().map { t0 + Int($0 * 60) } ?? r.n
        let race = fired.filter { $0.n >= t0 && $0.n <= t1 }
        let secs = Float(t1 - t0) / 60
        var byName: [String: Int] = [:]
        for f in race { byName[f.name, default: 0] += 1 }
        let hops = r.log.filter { if case .hop = $0.e { return $0.n >= t0 && $0.n <= t1 } else { return false } }.count
        MotionLog.write(String(format: "PULLSOUND puddle race of %.1f s: %d clips fired (%.2f per s), %d hop events (%.2f per s, all racers); by clip: %@", secs, race.count, Float(race.count) / secs, hops, Float(hops) / secs, "\(byName.sorted { $0.value > $1.value })"))
        let jumpVol = race.filter { $0.name.hasPrefix("jump") }.map(\.vol)
        MotionLog.write("PULLSOUND jump clip volumes: \(jumpVol.prefix(8)) (count \(jumpVol.count))")
        _ = hub
    }
}
