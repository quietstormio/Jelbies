//
//  AnticsLabTests.swift
//  The 3-Jelly happy-mood lab (wired like the stage by SocialTests.Lab): 600 jelly-seconds of roaming, measured for
//   - how many social interactions and distinct behaviours happen, and how often something visible starts,
//   - STUCK windows: a Jelly that is trying to walk for >= 2 s without making progress,
//   - the closest two Jellies ever got outside a boop-like pair.
//  The measuring uses only the public brain state (script / idle / social), so the same file runs on any build.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class AnticsLabTests: XCTestCase {
    struct Report {
        var socials = 0, socialKinds: [String: Int] = [:]
        var behaviours: [String: Int] = [:]
        var starts: [Float] = []
        var stuck = 0, stuckTags: [String] = []
        var minPair: Float = 0, minTag = ""
        var maxGap: Float = 0
        var meanGap: Float = 0
        var fastOver2 = 0
        var maxQuiet: Float = 0           // the longest stretch in which none of the three was doing anything but walking or standing
    }

    static func label(_ b: BlobBrain) -> String? {
        if let s = b.social { return "social:\(s.kind.rawValue)" }
        if let k = b.idleState.kind { return "idle:\(k.rawValue)" }
        switch b.script {
        case .hopPlay: return "play:hop"
        case .spin: return "play:spin"
        case .rollPlay: return "play:roll"
        case .flipPlay: return "play:flip"
        case .wave: return "wave"
        default: return nil
        }
    }

    static func measure(seconds: Int, seed: UInt64, mood: BlobMood = .happy, realRoom: Bool = true, configure: (BlobBrain) -> Void = { _ in }) -> Report {
        if realRoom { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }          // the room as the game runs it (wide portrait camera, 3-Jelly floor)
        defer { if realRoom { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) } }
        let lab = SocialTests.Lab(quiet: false, seed: seed)
        for (i, r) in lab.rigs.enumerated() {
            r.brain.idleMood = mood; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9; r.brain.restTimer = 0.5 + Float(i)
            configure(r.brain)
        }
        var rep = Report()
        var prev = [String?](repeating: nil, count: 3)
        var anchor = lab.rigs.map { $0.brain.position }, anchorYaw = lab.rigs.map { $0.brain.yaw }, still = [Float](repeating: 0, count: 3), flagged = [Bool](repeating: false, count: 3)
        var lastLabelStart: Float = 0
        var quietFrom: Float = 0
        for f in 0..<(60 * seconds) {
            lab.tick(watching: false)
            lab.sampleGaps()
            let t = Float(f) / 60
            var fast = 0
            for (i, r) in lab.rigs.enumerated() {
                let b = r.brain
                let l = label(b)
                if let l, l != prev[i] {
                    rep.behaviours[l, default: 0] += 1
                    rep.starts.append(t)
                }
                prev[i] = l
                if let k = b.idleState.kind, [.run, .zoomies, .slide, .scoot, .jacks, .stumble].contains(k) { fast += 1 }
                // stuck: trying to walk, no progress
                var walking = false
                if case .walk = b.script, b.idleState.kind == nil { walking = true }
                if walking {
                    if simd_distance(b.position, anchor[i]) > 0.15 || abs(wrapAngle(b.yaw - anchorYaw[i])) > 0.3 { anchor[i] = b.position; anchorYaw[i] = b.yaw; still[i] = 0; flagged[i] = false }
                    else {
                        still[i] += 1.0 / 60
                        if still[i] > 2, !flagged[i] {
                            flagged[i] = true; rep.stuck += 1
                            var tag = "t \(Int(t)) rig\(i) at (\(String(format: "%.2f,%.2f", b.px, b.pz))) stall \(String(format: "%.1f", b.steerStall)) route \(b.route.count)"
                            for (j, o) in lab.rigs.enumerated() where j != i { tag += " d\(j)=\(String(format: "%.2f", simd_distance(b.position, o.brain.position)))" }
                            if case .walk(let tg, _) = b.script { tag += " goal (\(String(format: "%.2f,%.2f", tg.x, tg.y))) job \(String(describing: b.job))" }
                            rep.stuckTags.append(tag)
                        }
                    }
                } else { anchor[i] = b.position; anchorYaw[i] = b.yaw; still[i] = 0; flagged[i] = false }
            }
            if fast > 2 { rep.fastOver2 += 1 }
            if lab.rigs.contains(where: { label($0.brain) != nil }) { rep.maxQuiet = max(rep.maxQuiet, t - quietFrom); quietFrom = t }
            _ = lastLabelStart; lastLabelStart = t
        }
        for r in lab.rigs { for (k, v) in r.brain.socialStarts { rep.socialKinds[k.rawValue, default: 0] += v } }
        rep.socials = rep.socialKinds.values.reduce(0, +)
        rep.minPair = lab.minPair; rep.minTag = lab.minTag
        let s = rep.starts.sorted()
        var gaps = [Float](), last: Float = 0
        for x in s { gaps.append(x - last); last = x }
        gaps.append(Float(seconds) - last)
        rep.maxGap = gaps.max() ?? 0
        rep.meanGap = gaps.isEmpty ? 0 : gaps.reduce(0, +) / Float(gaps.count)
        return rep
    }

    func testMeasureHappyLab600() {
        var tot = Report()
        for seed in [101, 202] as [UInt64] {
            let r = Self.measure(seconds: 600, seed: seed, realRoom: ProcessInfo.processInfo.environment["LAB_OLDROOM"] == nil)
            MotionLog.write("ANTICS LAB seed \(seed) 600 s happy: socials \(r.socials) \(r.socialKinds.sorted { $0.key < $1.key }), distinct behaviours \(r.behaviours.count) \(r.behaviours.sorted { $0.key < $1.key }), behaviour starts \(r.starts.count), mean gap between starts \(r.meanGap) max gap \(r.maxGap), >2 fast-move frames \(r.fastOver2), stuck windows \(r.stuck), min pair gap \(r.minPair) [\(r.minTag)]")
            for t in r.stuckTags { MotionLog.write("ANTICS STUCK \(t)") }
            tot.stuck += r.stuck
        }
        MotionLog.write("ANTICS LAB stuck total \(tot.stuck)")
    }

    static func lively(_ b: BlobBrain) { b.anticsEnabled = true; b.watching = true; b.sleepEnabled = true }

    /// The room life as the stage runs it (antics, a watching player, sleep): 600 jelly-seconds, two seeds.
    func testMeasureLively600() {
        var socials = 0, distinct = Set<String>(), stuck = 0, over2 = 0
        var worstGap: Float = 0, worstMean: Float = 0, minPair: Float = 9, worstQuiet: Float = 0
        for seed in [101, 202] as [UInt64] {
            let r = Self.measure(seconds: 600, seed: seed, configure: Self.lively)
            MotionLog.write("ANTICS LIVELY seed \(seed) 600 s happy: socials \(r.socials) \(r.socialKinds.sorted { $0.key < $1.key }), distinct behaviours \(r.behaviours.count) \(r.behaviours.sorted { $0.key < $1.key }), behaviour starts \(r.starts.count), mean gap between starts \(r.meanGap) max gap \(r.maxGap), longest quiet stretch \(r.maxQuiet), >2 fast-move frames \(r.fastOver2), stuck windows \(r.stuck), min pair gap \(r.minPair) [\(r.minTag)]")
            for t in r.stuckTags { MotionLog.write("ANTICS LIVELY STUCK \(t)") }
            socials += r.socials; distinct.formUnion(r.behaviours.keys); stuck += r.stuck; over2 += r.fastOver2
            worstQuiet = max(worstQuiet, r.maxQuiet); worstGap = max(worstGap, r.maxGap); worstMean = max(worstMean, r.meanGap); minPair = min(minPair, r.minPair)
        }
        MotionLog.write("ANTICS LIVELY totals: socials \(socials) (2 x 600 s), distinct behaviours \(distinct.count), stuck \(stuck), fast>2 frames \(over2), worst max gap between starts \(worstGap), worst longest-quiet \(worstQuiet), worst mean gap \(worstMean), min pair gap \(minPair)")
        XCTAssertGreaterThanOrEqual(socials, 100, "roughly twice the socials of the old room (24...29 per 600 s)")
        XCTAssertGreaterThanOrEqual(distinct.count, 26, "much more variety (the old room showed 16 distinct behaviours)")
        XCTAssertLessThanOrEqual(worstMean, 3.6, "something visible starts every few seconds")
        XCTAssertLessThanOrEqual(worstQuiet, 10.5, "never a long dead stretch (nobody doing anything but walking or standing)")
        XCTAssertEqual(over2, 0, "never more than two Jellies in fast moves at once")
        XCTAssertEqual(stuck, 0, "nobody walks in place")
        XCTAssertGreaterThanOrEqual(minPair, 0.6 * 1.4 - 0.05, "no Jellies on top of each other (outside a bump / boop pair)")
    }

    /// Soak: 3 Jellies, 10 minutes, happy, the room as the game runs it: no Jelly tries to walk for 2 s without getting anywhere, and nobody ends up on top of another.
    func testSoakNobodyIsStuckOrOnTopOfAnother() {
        for seed in [7, 31] as [UInt64] {
            let r = Self.measure(seconds: 600, seed: seed, configure: Self.lively)
            MotionLog.write("ANTICS SOAK seed \(seed): stuck windows \(r.stuck), min pair gap \(r.minPair) [\(r.minTag)]")
            for t in r.stuckTags { MotionLog.write("ANTICS SOAK STUCK \(t)") }
            XCTAssertEqual(r.stuck, 0, "seed \(seed): a Jelly was stuck walking: \(r.stuckTags)")
            XCTAssertGreaterThanOrEqual(r.minPair, 0.6 * 1.4 - 0.05, "seed \(seed): two Jellies overlapped at [\(r.minTag)]")
        }
    }

    /// Debug aid (not a regression): the trajectory of one rig around a stuck window.
    func testTraceStuck() throws {
        guard let spec = ProcessInfo.processInfo.environment["TRACE_STUCK"] else { throw XCTSkip("TRACE_STUCK=seed,rig,from,to") }
        let p = spec.split(separator: ",").map { Double($0)! }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956)
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        let lab = SocialTests.Lab(quiet: false, seed: UInt64(p[0]))
        for (i, r) in lab.rigs.enumerated() { r.brain.idleMood = .happy; r.brain.socialBook.cooldown = 8; r.brain.idleState.cooldown = 9; r.brain.restTimer = 0.5 + Float(i) }
        let rig = Int(p[1])
        for f in 0..<Int(p[3] * 60) {
            lab.tick(watching: false)
            if Double(f) / 60 >= p[2], f % (p.count > 4 ? Int(p[4]) : 15) == 0 {
                let b = lab.rigs[rig].brain
                var s = "TRACE poseW \(b.poseW) stepLive \(b.stepLive) real (\(String(format: "%.2f,%.2f", lab.rigs[rig].root.x, lab.rigs[rig].root.y))) hold \(b.socialBook.hold) t \(String(format: "%.2f", Double(f) / 60)) pos (\(String(format: "%.2f,%.2f", b.px, b.pz))) yaw \(String(format: "%.2f", b.yaw)) act \(b.activity) feetActive \(b.feet.active) stuckT \(b.stuckT) stall \(b.steerStall) scriptT \(b.scriptT) wait \(b.steerWait) route \(b.route.count) script \(b.script) idle \(String(describing: b.idleState.kind)) soc \(String(describing: b.socialKind))"
                for (j, o) in lab.rigs.enumerated() where j != rig { s += " | o\(j) (\(String(format: "%.2f,%.2f", o.brain.px, o.brain.pz))) real (\(String(format: "%.2f,%.2f", o.root.x, o.root.y))) \(o.brain.activity) \(String(describing: AnticsLabTests.label(o.brain)))" }
                s += " label \(String(describing: AnticsLabTests.label(b)))"
                MotionLog.write(s)
            }
        }
    }
}
