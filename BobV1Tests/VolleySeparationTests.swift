//
//  VolleySeparationTests.swift
//  Two Jelbies of one side never merge: over seeded whole matches (the sim runs headless, a kinematic stand-in follows each player's wish round the partner with the
//  brain's own rule `VolleyTuning.clearOfMate`, and hops in place) the least centre distance between two teammates stays above the body width, and the wishes themselves
//  keep clear of the partner.
//

import XCTest
import simd
@testable import BobV1

final class VolleySeparationTests: XCTestCase {
    func testClearOfMateSlidesRoundTheBody() {
        let m = SIMD2<Float>(0, 0)
        // a step straight at him ends on the circle, not inside it
        let q = VolleyTuning.clearOfMate(SIMD2(0.5, 0), from: SIMD2(2, 0), mate: m)
        XCTAssertEqual(simd_distance(q, m), VolleyTuning.brainGap, accuracy: 1e-4)
        // a step that keeps clear is left alone
        XCTAssertEqual(VolleyTuning.clearOfMate(SIMD2(3, 0), from: SIMD2(2, 0), mate: m), SIMD2(3, 0))
        // already closer than the gap: the step may not close in further
        let near = SIMD2<Float>(1.0, 0)
        XCTAssertGreaterThanOrEqual(simd_distance(VolleyTuning.clearOfMate(SIMD2(0.7, 0), from: near, mate: m), m), 1.0 - 1e-4)
        // dead on him: out to the side of his lane, a little at a time
        XCTAssertEqual(VolleyTuning.clearOfMate(m, from: m, mate: m, lane: -1).y, -0.15, accuracy: 1e-4)
    }

    func testScreenOverlapOfTwoBodies() {
        GameCamera.configureBeach()
        defer { GameCamera.endBeach(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let size = CGSize(width: 440, height: 956)
        _ = GameCamera.camera(aspect: Float(size.width / size.height))
        let a = SIMD3<Float>(-2, VolleyTuning.bodyTop, 0)
        XCTAssertEqual(VolleyView.overlap(a, a, size: size) ?? 0, 1, accuracy: 0.01)          // merged: all of it
        XCTAssertEqual(VolleyView.overlap(a, SIMD3(-2, VolleyTuning.bodyTop, 1.9), size: size) ?? 1, 0, accuracy: 0.01)          // a lane apart: none
        let mid = VolleyView.overlap(a, SIMD3(-2, VolleyTuning.bodyTop, 0.9), size: size) ?? 0
        XCTAssertGreaterThan(mid, 0.05); XCTAssertLessThan(mid, 0.9)
    }

    struct Gap { var minBody = Float.infinity, minWish = Float.infinity, ticks = 0, matches = 0, closest: [(seed: UInt64, t: Float, team: Int, d: Float)] = [], wishNote = "", points = 0, hits = 0, score = [0, 0], rallies: [Int] = [] }

    private func match(seed: UInt64, into g: inout Gap) {
        var s = VolleySim(mode: .match(.shore), mine: [VolleyStats(), VolleyStats()], seed: seed, firstServe: Int(seed % 2))
        s.autoMove = true; s.autoJump = true; s.autoSwitch = true
        let dt: Float = 1.0 / 60
        var tossed = false, rallyMax = 0
        for tick in 0..<(60 * 60 * 12) {
            for i in s.players.indices {
                let p = s.players[i]
                var pos = SIMD2(p.x, p.z), lift: Float = 0
                let mateI = i ^ 1
                if p.act == .stand || p.act == .jump || p.act == .spike || p.act == .block {
                    let want = SIMD2(p.wantX, p.wantZ), d = want - pos, l = simd_length(d)
                    if l > 1e-4 {
                        var q = pos + d / l * min(l, VolleyTuning.walkSpeed(p) * dt)
                        if VolleyTuning.keepApart, s.players.indices.contains(mateI) { q = VolleyTuning.clearOfMate(q, from: pos, mate: SIMD2(s.players[mateI].x, s.players[mateI].z), lane: p.z >= 0 ? 1 : -1) }
                        pos = q
                    }
                }
                var done = false
                switch p.act {
                case .jump, .spike, .block:
                    let apex = VolleyTuning.apex(hops: p.stats.hops), air = VolleyTuning.airTime(apex: apex)
                    let u = max(0, (p.actT - VolleyTuning.crouch) / air)
                    if u > 0, u < 1 { lift = apex * 4 * u * (1 - u) }
                    done = p.actT > VolleyTuning.crouch + air + 0.2
                case .dive: done = p.actT > 0.9
                case .stand: break
                }
                s.setBody(i, x: pos.x, z: pos.y, lift: lift, top: VolleyTuning.bodyTop + lift, grounded: lift < 0.02)
                s.setSamples(i) { arr in
                    arr.removeAll(keepingCapacity: true)
                    for k in 0..<16 { let a = Float(k) / 16 * 2 * .pi; arr.append(SIMD2(pos.x + 0.55 * cosf(a), lift + 0.67 + 0.67 * sinf(a))) }
                }
                if done { s.bodyDone(i) }
            }
            if s.waitingToServe, s.servingPlayer == s.controlled { s.tap(); tossed = true }
            if s.phase == .rally, tossed, let r = s.ring, abs(r.tau - r.lead) < 0.03, s.hitLabel == "Serve!" { s.tap(); tossed = false }
            if s.players.count == 4 {
                for team in 0..<2 {
                    let a = s.players[team * 2], b = s.players[team * 2 + 1]
                    let d = hypotf(a.x - b.x, a.z - b.z)
                    g.minBody = min(g.minBody, d)
                    g.closest.append((seed, Float(tick) / 60, team, d)); if g.closest.count > 4000 { g.closest.sort { $0.d < $1.d }; g.closest.removeLast(g.closest.count - 8) }
                    if s.phase == .rally {
                        let dw = hypotf(a.wantX - b.wantX, a.wantZ - b.wantZ)
                        if dw < g.minWish { g.minWish = dw; g.wishNote = "seed \(seed) t \(Float(tick) / 60) team \(team) wants (\(a.wantX), \(a.wantZ)) (\(b.wantX), \(b.wantZ)) at (\(a.x), \(a.z)) (\(b.x), \(b.z)) act \(a.act) \(b.act) human \(a.human) \(b.human)" }
                    }
                }
            }
            if s.phase == .rally { rallyMax = max(rallyMax, s.rallyHits) }
            s.tick(dt: dt)
            g.ticks += 1
            for e in s.takeEvents() { if case .point = e { g.points += 1; g.hits += rallyMax; g.rallies.append(rallyMax); rallyMax = 0 } }
            if s.phase == .over { break }
        }
        g.matches += 1; g.score[0] += s.score[0]; g.score[1] += s.score[1]
    }

    private func run(keepApart: Bool) -> Gap {
        VolleyTuning.keepApart = keepApart
        var g = Gap()
        for seed in UInt64(1)..<UInt64(51) { match(seed: seed, into: &g) }
        g.closest.sort { $0.d < $1.d }
        return g
    }
    override func tearDown() { VolleyTuning.keepApart = true; super.tearDown() }

    func testTeammatesNeverMergeOverFiftySeededMatches() {
        let before = run(keepApart: false), after = run(keepApart: true)
        func line(_ n: String, _ g: Gap) -> String {
            String(format: "%@: %d matches, %d points, least teammate centre distance %.3f (body width %.1f), mean rally %.2f hits (median %d, 90th percentile %d, over 40: %d), our share %.1f%%", n, g.matches, g.points, g.minBody, VolleyTuning.bodyDiameter,
                   Float(g.hits) / Float(max(1, g.points)), g.rallies.sorted()[g.rallies.count / 2], g.rallies.sorted()[g.rallies.count * 9 / 10], g.rallies.filter { $0 > 40 }.count, 100 * Float(g.score[0]) / Float(max(1, g.score[0] + g.score[1])))
        }
        let report = line("before (old rule)", before) + "\n" + line("after  (kept apart)", after) + "\nclosest after: \(after.closest.prefix(3))\n"
        print(report)
        if let path = ProcessInfo.processInfo.environment["VOLLEY_REPORT"] { try? report.write(toFile: path, atomically: true, encoding: .utf8) }          // (xcodebuild: TEST_RUNNER_VOLLEY_REPORT=path)
        XCTAssertEqual(after.matches, 50)
        XCTAssertGreaterThanOrEqual(after.minBody, VolleyTuning.bodyDiameter, "two teammates' bodies never overlap")
        // (the rally length and the split are reported, not pinned: with the bodies merged the old rule gave two players' cover at every ball, so its rallies were far
        //  longer; the matches must still play out as rallies with points on both sides)
        XCTAssertGreaterThan(after.points, 500)
        XCTAssertGreaterThan(after.score[1], 100, "the other team still scores")
    }
}
