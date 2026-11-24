//
//  ShowLineTests.swift
//  show-line-r1 (2026-11-24, the owner: "They still get very stuck when getting back in line during show that can not happen ever"): the Trick round's line.
//  Whole Trick rounds on the real GameCare / brains / sims (the headless room), random trick picks and seeds. Measures, at 60 Hz:
//  overlaps (centres closer than 1.0), hidden bodies (another body in front of one), returns slower than 2 s, and turns that start with the line not formed.
//  `SHOWLINE_LOG` (env, via TEST_RUNNER_) names a file: a 10 Hz position / slot log of every body.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ShowLineTests: XCTestCase {
    struct Stats {
        var placed = 0, overlaps = 0, hidden = 0, slowReturns = 0, notFormed = 0, turns = 0, returns = 0
        var worstReturn: Float = 0, minGap: Float = 99
        var notes: [String] = []
        mutating func add(_ o: Stats) {
            placed += o.placed
            overlaps += o.overlaps; hidden += o.hidden; slowReturns += o.slowReturns; notFormed += o.notFormed; turns += o.turns; returns += o.returns
            worstReturn = max(worstReturn, o.worstReturn); minGap = min(minGap, o.minGap); notes += o.notes
        }
    }
    struct RNG { var s: UInt64; mutating func next() -> Float { s = s &* 6364136223846793005 &+ 1442695040888963407; return Float((s >> 40) & 0xFFFF) / 65536 } }

    private var logHandle: FileHandle?
    private func log(_ s: String) { logHandle?.write((s + "\n").data(using: .utf8)!) }

    /// One whole Show (look, dance, trick x3, results) with `per` entrants per turn; returns what went wrong.
    func oneShow(seed: UInt64, per: Int, sideways: Bool, tag: String = "") -> Stats {
        GameCamera.aspect = sideways ? 956.0 / 440.0 : 440.0 / 956.0
        defer { GameCamera.aspect = 440.0 / 956.0 }
        let room = RaceThreeTests.Room(count: 1)
        RaceThreeTests.keep.append(room)
        let care = room.care
        care.show.songClock = { _ in nil }; care.show.audioReady = { _ in true }; care.show.cue = { _ in }
        care.show.entrantsPerTurn = per
        var wrapped = false
        var peers: [(pos: SIMD2<Float>, walking: Bool)] = []
        func step() {
            let dt = room.actors[0].sim.stepDt
            let all = room.actors + room.park
            if !wrapped, !room.park.isEmpty {          // the stage's rule under every body's steering (MelonStage.keepApart through `peers`), as the app wires it
                wrapped = true
                for (i, a) in all.enumerated() {
                    guard let b = a.brain else { continue }
                    let floorRules = b.resolve
                    b.resolve = { p, r in MelonController.keepApart(floorRules(p, r), id: i, peers: peers) }
                }
            }
            peers = all.map { (pos: $0.floor, walking: $0.isWalking) }
            for a in all {
                if a.id < room.actors.count, care.tripFrozen(a.id) { continue }
                a.brain?.tick(sim: a.sim, skinner: a.skinner, dt: dt, touched: false)
                a.skinner.jelly.tick(brain: a.brain!, sim: a.sim, dt: dt)
            }
            care.tickRace(room.actors, dt: dt)
            care.tickShow(room.actors, dt: dt)
            for a in all where !(a.id < room.actors.count && care.tripFrozen(a.id)) { a.sim.step() }
        }
        var st = Stats()
        UserDefaults.standard.set(20261100 + Int(seed % 28), forKey: "ShowDay")
        defer { UserDefaults.standard.removeObject(forKey: "ShowDay") }
        care.startShow(jelly: 0, rank: .puddle, seed: seed)
        for _ in 0..<(6 * 60) { step(); if care.show.onStage { break } }
        guard care.show.onStage else { st.notes.append("never on stage"); return st }
        care.show.auto = true
        let book = care.showBook
        var rng = RNG(s: seed &* 7919 &+ 13)
        var t: Float = 0, lastLog: Float = -1, nextPick: Float = 0
        var prevStage = care.show.trickStage, prevStep = care.show.rivalStep, prevEntering = false
        var pickedInEntrance = false, skipAt: Float? = nil, skippedAll = false
        let stress = ProcessInfo.processInfo.environment["SHOWLINE_STRESS"] == "1" || tag.hasSuffix("!")
        var returnStart: [Int: Float] = [:]          // body id -> when its return began
        var hiddenNow = false, overlapNow = false, hidT: Float = 0
        func seat(_ id: Int) -> SIMD2<Float>? {          // where body `id` is meant to stand while nobody is walking (nil = in transit)
            let sw = sideways
            let player = room.actors[0].id
            let f = care.show
            if id == player {
                if f.trickStage == .rivals { return f.rivalStep == .playerBack ? ShowStage.playerSpot : ShowStage.playerAside(sideways: sw) }
                return ShowStage.playerSpot
            }
            guard let k = book.rivalBody.first(where: { $0.value == id })?.key else { return nil }
            if f.trickStage == .rivals, f.rivalTurn == k, f.rivalStep == .walkIn || f.rivalStep == .perform { return ShowStage.playerSpot }
            return ShowStage.rivalRest(k, sideways: sw)
        }
        func bodies() -> [JellyActor] { [room.actors[0]] + book.extra }
        func atSeat(_ a: JellyActor) -> Bool {
            guard let s = seat(a.id) else { return true }
            let c = a.sim.centroid()
            return simd_distance(SIMD2(c.x, c.z), s) < 0.5
        }
        func formed(except: Int? = nil) -> Bool { bodies().allSatisfy { $0.id == except || atSeat($0) } }
        let maxSteps = 500 * 60
        for _ in 0..<maxSteps {
            step(); t += 1 / 60
            let f = care.show
            if f.round == .dance || f.round == .look { continue }
            if stress, f.round == .trick, f.trickEntering, !pickedInEntrance, rng.next() < 0.01 { pickedInEntrance = true; if let s = f.sim, let tr = s.knownTricks.first { f.pick(tr) } }          // (a tap during the walk-on)
            if stress, f.round == .trick, f.trickStage == .rivals {
                if f.rivalStep == .walkIn || f.rivalStep == .perform {
                    if skipAt == nil, rng.next() < 0.004 { skipAt = t }
                    if let sa = skipAt, t - sa > 0.1 { skipAt = nil; f.skipCurrentRival() }          // (a tap on the banner)
                }
                if !skippedAll, f.rivalStep == .walkIn, f.rivalTurn == 2, rng.next() < 0.002 { skippedAll = true; f.skipRivals() }          // (Skip)
            }
            if f.trickStage == .pick { skippedAll = false }
            if f.round == .trick, f.trickStage == .pick, !f.trickEntering, let s = f.sim, !s.tricksDone, t >= nextPick, f.auto {
                // random pick (the auto player always picks the first unused): random lengths
                let pool = s.knownTricks.filter { !s.usedTricks.contains($0) }
                if !pool.isEmpty { let tr = pool[Int(rng.next() * Float(pool.count)) % pool.count]; f.pick(tr) }
                nextPick = t + rng.next() * 1.5
            }
            let inTrick = f.round == .trick || (f.round == .results && f.trickStage != .pick)
            guard inTrick, book.trickSet else { if f.round == .results && f.trickStage == .pick { break }; continue }
            let all = bodies()
            // overlaps / hidden
            var ov = false, hid = false
            for i in all.indices { for j in all.indices where j > i {
                let g = simd_distance(all[i].floor, all[j].floor); st.minGap = min(st.minGap, g)
                if g < 1.0 { ov = true }
                for (a, b) in [(all[i], all[j]), (all[j], all[i])] {          // b hidden by a: a nearer the camera (greater z), side by side within 0.6, and close in depth
                    let d = a.floor - b.floor
                    if d.y > 0 && d.y < 1.1 && abs(d.x) < 1.0 && abs(a.floor.x) < 3 && abs(b.floor.x) < 3 { hid = true }
                }
            } }
            if ov && !overlapNow { st.overlaps += 1; st.notes.append(String(format: "[%@] overlap at t=%.1f turn %d step %@ %@", tag, t, f.rivalRound, "\(f.rivalStep)", all.map { String(format: "%d@(%.2f,%.2f)", $0.id, $0.floor.x, $0.floor.y) }.joined(separator: " "))) }
            hidT = hid ? hidT + 1 / 60 : 0          // (a body passing in front of another for a moment is not hiding it: only 0.7 s or more counts)
            let hidNow = hidT > 0.7
            if hidNow && !hiddenNow { st.hidden += 1; st.notes.append(String(format: "[%@] hidden at t=%.1f turn %d step %@ %@", tag, t, f.rivalRound, "\(f.rivalStep)", all.map { String(format: "%d@(%.2f,%.2f)", $0.id, $0.floor.x, $0.floor.y) }.joined(separator: " "))) }
            overlapNow = ov; hiddenNow = hidNow
            // returns: a body starts returning when its seat changes to somewhere it is not
            for a in all {
                let there = atSeat(a)
                if !there, returnStart[a.id] == nil, !f.trickEntering { returnStart[a.id] = t }
                if there, let t0 = returnStart[a.id] { returnStart[a.id] = nil; let d = t - t0; st.returns += 1; st.worstReturn = max(st.worstReturn, d); if d > 2.0 { st.slowReturns += 1; st.notes.append(String(format: "[%@] slow return body %d %.1f s (turn %d)", tag, a.id, d, f.rivalRound)) } }
            }
            // turn starts with the line not formed: the player's go opens (rivals -> pick), and each entrant's perform
            if f.trickStage == .pick && prevStage == .rivals && f.round == .trick {
                st.turns += 1
                if !formed() { noteNotFormed(&st, "player's go opens with the line not formed", all, tag, t, seat) }
            }
            if f.trickStage == .rivals && f.rivalStep == .perform && prevStep != .perform {
                st.turns += 1
                if !formed() { noteNotFormed(&st, "an entrant performs with the line not formed", all, tag, t, seat) }
            }
            prevStage = f.trickStage; prevStep = f.rivalStep; prevEntering = f.trickEntering
            if t - lastLog >= 0.1 {
                lastLog = t
                log(String(format: "%@ t=%.1f r%d %@/%@ turn=%@ ", tag, t, f.rivalRound, "\(f.trickStage)", "\(f.rivalStep)", "\(String(describing: f.rivalTurn))") + all.map { a in let s = seat(a.id); return String(format: "[%d (%.2f,%.2f) -> %@%@]", a.id, a.floor.x, a.floor.y, s.map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-", book.via[a.id] != nil ? " via" : "") }.joined(separator: " "))
            }
            if f.round == .results && f.trickStage == .pick { break }
        }
        _ = prevEntering
        st.placed = book.placements
        care.show.abort()
        return st
    }

    private func report(_ name: String, _ st: Stats) {
        print("[ShowLine] \(name): turns \(st.turns) returns \(st.returns) worstReturn \(String(format: "%.2f", st.worstReturn)) minGap \(String(format: "%.2f", st.minGap)) placed \(st.placed) overlaps \(st.overlaps) hidden \(st.hidden) slowReturns \(st.slowReturns) notFormed \(st.notFormed)")
        for n in st.notes.prefix(30) { print("[ShowLine]   \(n)") }
    }
    private func openLog() {
        if let p = ProcessInfo.processInfo.environment["SHOWLINE_LOG"], !p.isEmpty {
            FileManager.default.createFile(atPath: p, contents: nil); logHandle = FileHandle(forWritingAtPath: p)
        }
    }
    private var stressOn: Bool { ProcessInfo.processInfo.environment["SHOWLINE_STRESS"] == "1" }
    private func runMany(_ name: String, seeds: Range<UInt64>, per: Int, sideways: Bool) -> Stats {
        var all = Stats()
        for s in seeds { all.add(oneShow(seed: s, per: per, sideways: sideways, tag: "\(name)#\(s)" + (stressOn ? "!" : ""))) }
        report(name, all)
        return all
    }

    func testBaselineMeasure() {
        openLog()
        if ProcessInfo.processInfo.environment["SHOWLINE_OFF"] == "1" { UserDefaults.standard.set(1, forKey: "ShowLineKeepOff") }
        defer { UserDefaults.standard.removeObject(forKey: "ShowLineKeepOff") }
        let n = UInt64(ProcessInfo.processInfo.environment["SHOWLINE_N"] ?? "") ?? 3
        var tot = Stats()
        tot.add(runMany("portrait4", seeds: 1..<(1 + n), per: 3, sideways: false))
        tot.add(runMany("landscape4", seeds: 100..<(100 + max(n / 2, 1)), per: 3, sideways: true))
        tot.add(runMany("portrait2", seeds: 200..<(200 + max(n / 3, 1)), per: 1, sideways: false))
        tot.add(runMany("portrait3", seeds: 300..<(300 + max(n / 3, 1)), per: 2, sideways: false))
        XCTAssertEqual(tot.overlaps, 0, "no overlaps")
        XCTAssertEqual(tot.hidden, 0, "no hidden bodies")
        XCTAssertEqual(tot.notFormed, 0, "every turn starts with the line formed")
        XCTAssertEqual(tot.slowReturns, 0, "every return within 2 s")
    }

    private func noteNotFormed(_ st: inout Stats, _ what: String, _ all: [JellyActor], _ tag: String, _ t: Float, _ seat: (Int) -> SIMD2<Float>?) {
        st.notFormed += 1
        st.notes.append(String(format: "[%@] %@ at t=%.1f: ", tag, what, t) + all.map { a in String(format: "%d@(%.2f,%.2f)->%@", a.id, a.floor.x, a.floor.y, seat(a.id).map { String(format: "(%.2f,%.2f)", $0.x, $0.y) } ?? "-") }.joined(separator: " "))
    }
}
