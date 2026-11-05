//
//  RaceFeetTests.swift
//  "The legs fall off during the track meets and a hurdle" (user, 2026-11-04): a whole race with hurdles, three bodies (the player and two rivals), the glue
//  exactly as the game does it (RaceSim events -> BlobBrain.raceApply), and the FeetAttachTests harness on the DRAWN feet of every racer every tick.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RaceFeetTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func empty() -> FeetAttachTests.FootFrame { .init(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity) }


    /// Leg stretch of one body this frame: in the fitted body frame (rest coords, standing sole = 0) the lowest foot point (`sole`, + = foot lifted up
    /// into the body), the highest foot point (`top`), the foot centre's horizontal offset from the body axis (`off`), and in the world how far the body
    /// centroid is lifted above its standing height (`body`) and the lowest foot point above the floor (`foot`): body - foot is how far the legs trail the body.
    struct Leg { var sole: Float = -.infinity, top: Float = -.infinity, off: Float = 0, body: Float = -.infinity, foot: Float = -.infinity, trail: Float = -.infinity }
    static func leg(sim: SoftBody, ids: [[Int32]], dyn: [Float], standY: Float) -> Leg {
        let pose = sim.bodyPose(iterations: 4), c0 = sim.restCentroid
        var l = Leg(); l.body = sim.centroid().y - standY
        var lowW = Float.infinity
        for sd in 0..<2 where !ids[sd].isEmpty {
            var lo = Float.infinity, hi = -Float.infinity, cx: Float = 0, cz: Float = 0
            for id in ids[sd] {
                let o = 6 * Int(id), p = SIMD3(dyn[o], dyn[o + 1], dyn[o + 2])
                let q = c0 + pose.rotation.inverse.act(p - pose.centroid)
                lo = min(lo, q.y); hi = max(hi, q.y); cx += q.x; cz += q.z; lowW = min(lowW, p.y)
            }
            let m = Float(ids[sd].count)
            l.sole = max(l.sole, lo); l.top = max(l.top, hi); l.off = max(l.off, hypotf(cx / m, cz / m))
        }
        l.foot = lowW - sim.floorY; l.trail = l.body - l.foot
        return l
    }
    final class LegStats { var by: [String: Leg] = [:]
        func add(_ phase: String, _ l: Leg) {
            var w = by[phase] ?? Leg()
            w.sole = max(w.sole, l.sole); w.top = max(w.top, l.top); w.off = max(w.off, l.off); w.body = max(w.body, l.body); w.foot = max(w.foot, l.foot); w.trail = max(w.trail, l.trail)
            by[phase] = w }
        func dump(_ title: String) { for k in by.keys.sorted() { let w = by[k]!; MotionLog.write(String(format: "LEGSTRETCH %@ | %@ | max sole-in-body %.3f, max foot top %.3f, max foot offset from axis %.3f, max body lift %.3f, max foot lift %.3f, max body-minus-foot (trail) %.3f", title, k, w.sole, w.top, w.off, w.body, w.foot, w.trail)) } }
    }

    /// Reference: the hops the user already likes, in the room rig, same metrics.
    func testLegStretchReferenceRoomHops() {
        let moves: [(String, Float, (MotionRig) -> Void)] = [
            ("room hop (startHopPlay)", 3, { $0.brain.startHopPlay(sim: $0.sim) }),
            ("room hopscotch", 5, { $0.brain.idleForced = true; _ = $0.brain.idleStart(.hopscotch, $0.sim) }),
            ("room skipHop", 4, { $0.brain.idleForced = true; _ = $0.brain.idleStart(.skipHop, $0.sim) }),
            ("room bounce", 4, { $0.brain.idleForced = true; _ = $0.brain.idleStart(.bounce, $0.sim) }),
            ("room walk", 6, { $0.brain.request(.goTo(SIMD2(1.6, 0.4))) })]
        for (name, secs, start) in moves {
            let r = MotionRig(game: true); Self.keep.append(r); r.renderSamples = false
            let standY = r.sim.centroid().y
            let stats = LegStats()
            start(r)
            let ids = (0..<2).map { _ in [Int32]() }
            _ = ids
            r.run(secs) {
                r.render()
                let beans = r.skinner.beansActive && r.skinner.beanBlend > 0.05
                let l = Self.leg(sim: r.sim, ids: beans ? r.bean : r.core, dyn: r.dyn, standY: standY)
                stats.add("\(r.brain.gait.phase)\(beans ? " beans" : " embedded")", l)
            }
            stats.dump(name)
        }
    }

    /// What the stage does per fixed step with the race running (RaceTripTests.Room.step) plus what it does per frame: the bean refit and the skin pass
    /// (leash / tether observer armed), then the FeetAttachTests measurement of the DRAWN feet of each racer.
    private func race(_ name: String, course tier: CourseTier, seed: UInt64, taps: Float, jump: Bool, trip: Bool = false) {
        let room = RaceTripTests.Room()
        Self.keep.append(room)
        let care = room.care, rm = MotionRig.renderMesh
        for (k, f) in [JellyFeature.spines, .daisy, .wings].enumerated() {
            let a = room.actors[k]
            a.brain?.feature = f; a.skinner.configureTail(rm); a.skinner.tailOn = f == .spines; a.brain?.skinnerRef = a.skinner
            a.brain?.amplitude = 1
        }
        for b in CourseTier.allCases where b.index < tier.index { care.race.progress.records[b] = CourseProgress.Record(races: 1, wins: 1, topTwo: 1) }
        care.race.courseTier = tier
        care.race.rivalSource = LocalRivalSourceFixed(waddle: 0.7)
        care.race.autoRate = nil
        let legs = (0..<3).map { _ in LegStats() }, standY = room.actors.map { $0.sim.centroid().y }
        var dyn = room.actors.map { _ in [Float](repeating: 0, count: rm.vertexCount * 6) }
        let bean: [[[Int32]]] = room.actors.map { _ in [-1, 1].map { side in let f = rm.armCapsule!.beanFirst(side: side); return (f..<(f + FootBean.vertexCount)).map { Int32($0) } } }
        let core: [[[Int32]]] = room.actors.map { a in (0..<2).map { a.brain!.footCoreVertices($0, sim: a.sim, skinner: a.skinner) } }
        var cur = 0, guardHits = [0, 0, 0], guardPull = [Float](repeating: 0, count: 3), guardNote = ["", "", ""]
        Skinner.leashObserver = { s, pull, tether in guardHits[cur] += 1; if pull > guardPull[cur] { guardPull[cur] = pull; guardNote[cur] = "foot \(s) \(tether ? "tether" : "leash") \(String(format: "%.1f", pull * 100)) cm" } }
        defer { Skinner.leashObserver = nil }
        care.startRace(jelly: 0, seed: seed)
        var worst = (0..<6).map { _ in empty() }, frames = [Int](repeating: 0, count: 6), worstJ = (0..<6).map { _ in empty() }, framesJ = [Int](repeating: 0, count: 6)
        var run = [0, 0, 0], longest = [0, 0, 0], longestAt = ["", "", ""], note = ["", "", ""], foot = 0, tapT: Float = 0, jumps = 0, trips = 0, kicks = 0
        let dt = room.actors[0].sim.stepDt
        var n = 0
        while n < 60 * 120, care.race.active, !(care.race.hasResults && n > 0 && care.race.sim?.phase == .results) {
            n += 1
            // the player's fingers, as the HUD would: tap alternately, but let the hurdle's Jump press through (stop tapping near a bar, press Jump)
            if let sim = care.race.sim, care.race.phase == .racing, sim.phase == .running || sim.phase == .finishing {
                let nearBar = sim.course.hasHurdles && sim.racers[0].nextHurdle < sim.course.hurdles.count && sim.course.hurdles[sim.racers[0].nextHurdle] - sim.racers[0].dist < 1.0
                if nearBar && jump { _ = care.race.jump() }
                if !(nearBar && jump) || trip { tapT += dt; while tapT >= 1 / taps { tapT -= 1 / taps; _ = care.race.tap(foot: foot); foot = 1 - foot } }
            }
            room.step()
            for (k, a) in room.actors.enumerated() {
                a.brain?.refitBeans(a.sim, a.skinner)
                guard care.race.sim?.phase == .running || care.race.sim?.phase == .finishing, care.raceBook.racers.contains(k), let b = a.brain, b.race.active else { continue }
                cur = k
                a.skinner.update(x: a.sim.x, index: rm.index, into: &dyn[k])
                let jumping = b.race.jumping
                // measure (FeetAttachTests.drawnFootFrame on this actor)
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
                let slot = k + (beans ? 0 : 3)
                do {
                    let ph = b.race.stumbleT > 0 ? "trip (stumble)" : jumping ? "hop \(b.gait.phase)" : b.race.jumpQueued ? "jump queued" : "run/stand"
                    legs[k].add("\(ph)\(beans ? " beans" : " embedded")", Self.leg(sim: a.sim, ids: beans ? bean[k] : core[k], dyn: dyn[k], standY: standY[k]))
                }
                if beans { run[k] = 0 } else { run[k] += 1; if run[k] > longest[k] { longest[k] = run[k]; longestAt[k] = String(format: "ends t=%.2f script=%@ gait=%@ jumping=%d stumbleT=%.2f", Float(n) * dt, "\(b.script)", "\(b.gait.phase)", jumping ? 1 : 0, b.race.stumbleT) } }
                if f.overlap > worst[slot].overlap || f.soleRise > worst[slot].soleRise {
                    note[k] = String(format: "t=%.2f racer %d jumping=%d script=%@ gait=%@ sole %.3f centre %.3f radius %.3f overlap %.3f stretch %.2f beans=%d", Float(n) * dt, k, jumping ? 1 : 0, "\(b.script)", "\(b.gait.phase)", f.soleRise, f.centreHeight, f.radius, f.overlap, f.stretch, beans ? 1 : 0)
                }
                FeetAttachTests.accumulate(&worst[slot], f); frames[slot] += 1
                if jumping { FeetAttachTests.accumulate(&worstJ[slot], f); framesJ[slot] += 1 }
            }
        }
        jumps = care.race.sim?.racers[0].hurdlesCleared ?? 0; trips = care.race.sim?.racers[0].hurdlesHit ?? 0; kicks = 0
        MotionLog.write("RACEFEET \(name): player cleared \(jumps) hit \(trips); rivals cleared \((care.race.sim?.racers.dropFirst().map { $0.hurdlesCleared })  ?? []) hit \((care.race.sim?.racers.dropFirst().map { $0.hurdlesHit }) ?? [])")
        for k in 0..<3 { legs[k].dump("\(name) racer \(k)") }
        for k in 0..<3 {
            MotionLog.write("RACEFEET \(name) racer \(k): longest feet-in run \(longest[k]) steps (\(Float(longest[k]) * dt) s) \(longestAt[k]); guard hits \(guardHits[k]) (\(guardNote[k])); worst frame: \(note[k])")
            XCTAssertEqual(guardHits[k], 0, "\(name) racer \(k): the leash / tether moved a foot piece (\(guardNote[k]))")
            XCTAssertGreaterThan(frames[k] + frames[k + 3], 300, "\(name) racer \(k) ran")
            FeetAttachTests.check("race \(name) racer \(k) bean", worst[k], frames: frames[k])
            FeetAttachTests.check("race \(name) racer \(k) bean (jump)", worstJ[k], frames: framesJ[k])
            FeetAttachTests.check("race \(name) racer \(k) embedded", worst[k + 3], frames: frames[k + 3], core: true)
            FeetAttachTests.check("race \(name) racer \(k) embedded (jump)", worstJ[k + 3], frames: framesJ[k + 3], core: true)
        }
        // (finding 2026-11-04, not asserted here: through GameCare + the body every racer, rivals too, HITS every bar even while the body hops: cleared 0, hit 3 / 6; see the report)
    }

    func testRacersKeepTheirFeetOverHurdlesSplashJumping() { race("splash jumping", course: .splash, seed: 5, taps: 3, jump: true) }
    func testRacersKeepTheirFeetOverHurdlesWaveJumping() { race("wave jumping", course: .wave, seed: 9, taps: 3, jump: true) }
    func testRacersKeepTheirFeetWhenTheyHitHurdlesWave() { race("wave tripping", course: .wave, seed: 9, taps: 7, jump: false, trip: true) }
}
