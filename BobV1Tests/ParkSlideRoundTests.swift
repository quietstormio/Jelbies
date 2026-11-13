//
//  ParkSlideRoundTests.swift
//  park-slide-r2: the walk round the park slide never stalls and never crosses the slide (T1, T2), and other code that picks a floor target
//  (zoomies, group hug, arrival trot) never picks one inside a solid park piece (T3). Numbers are printed (PSR lines).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkSlideRoundTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    static let portrait: Float = 440.0 / 956.0, landscape: Float = 956.0 / 440.0

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5; ContactTuning.lookAhead = true
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: Self.portrait)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(n: Int, seed: UInt64, aspect: Float, starts: [SIMD2<Float>]? = nil, quiet: Bool = true) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: aspect)
        let dflt: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(-1.2, 2.2), SIMD2(0.9, 2.4)]
        let lab = SocialTests.Lab(n: n, positions: Array((starts ?? dflt).prefix(n)), quiet: quiet, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy; r.brain.outingPlay = true }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }
    func place(_ r: MotionRig, _ p: SIMD2<Float>) {
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
    }
    /// The slide's box in floor coordinates (x lo/hi, z lo/hi), from the real foot.
    func box(_ sl: DecorFoot) -> (SIMD2<Float>, SIMD2<Float>) {
        let h: SIMD2<Float> = sl.quarter & 1 == 0 ? sl.spec.half : SIMD2(sl.spec.half.y, sl.spec.half.x)
        return (sl.centre - h, sl.centre + h)
    }
    /// How far the point is inside the box rectangle (0 = outside), the smallest distance to an edge.
    func insideDepth(_ b: (SIMD2<Float>, SIMD2<Float>), _ p: SIMD2<Float>) -> Float {
        let dx = min(p.x - b.0.x, b.1.x - p.x), dz = min(p.y - b.0.y, b.1.y - p.y)
        return min(dx, dz) > 0 ? min(dx, dz) : 0
    }

    // MARK: T1

    struct Solo {
        var label = "", skipped = false, started = false
        var legs: [String] = [], tLadder: Float?, maxDepth: Float = 0, depthAt = "", still: Float = 0, stillAt = "", endedBefore = false, endT: Float = 0
    }

    /// `afterRide`: the start is as right after a ride (the slide is soft for him until he is 0.55 clear of it: `decorIgnore` = the slide).
    func runSolo(_ label: String, _ p: SIMD2<Float>, aspect: Float, seed: UInt64 = 5, afterRide: Bool = false) -> Solo {
        var out = Solo(); out.label = label
        let lab = parkLab(n: 1, seed: seed, aspect: aspect)
        let sl = DecorField.shared.foot(ParkToys.slideUID)!
        let bx = box(sl)
        let r = lab.rigs[0], b = r.brain
        if afterRide { b.decorIgnore = ParkToys.slideUID }
        let q = b.fixed(p)
        if simd_distance(p, q) > 0.1 { out.skipped = true; return out }
        place(r, q)
        for _ in 0..<5 { lab.tick(watching: false) }
        if afterRide { b.decorIgnore = ParkToys.slideUID }
        if simd_distance(b.position, sl.centre + sl.turned(SIMD2(0, -DecorKind.slideApproach))) <= 0.35 { out.skipped = true; return out }          // (already on the climb spot: no walk to take)
        out.started = b.startCommandedDecor(.decorSlide, only: .slide, r.sim, r.skinner)
        if !out.started { return out }
        var t: Float = 0, lastStage = 99, lastTarget = SIMD2<Float>(99, 99)
        var ref = b.position, refT: Float = 0, still: Float = 0
        while t < 45 {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            let st = b.idleState
            guard st.kind == .decorSlide, st.decorUID == ParkToys.slideUID else { if t > 0.1 { out.endedBefore = out.tLadder == nil; break }; continue }
            if st.slideStage != lastStage || simd_distance(st.target, lastTarget) > 0.01 {
                out.legs.append(String(format: "[t%.1f st%d (%.2f,%.2f) from (%.2f,%.2f)]", t, st.slideStage, st.target.x, st.target.y, b.position.x, b.position.y))
                lastStage = st.slideStage; lastTarget = st.target
            }
            if st.slideStage >= 1 { out.tLadder = t; break }
            let d = insideDepth(bx, b.position)
            if d > out.maxDepth { out.maxDepth = d; out.depthAt = String(format: "t%.1f stage %d at (%.2f,%.2f)", t, st.slideStage, b.position.x, b.position.y) }
            if t - refT >= 0.5 {
                if simd_distance(b.position, ref) < 0.05 && st.slideStage < 0 { still += 0.5 } else { still = 0 }
                if still > out.still { out.still = still; out.stillAt = String(format: "t%.1f at (%.2f,%.2f) stage %d target (%.2f,%.2f)", t, b.position.x, b.position.y, st.slideStage, st.target.x, st.target.y) }
                ref = b.position; refT = t
            }
        }
        out.endT = t
        if !out.started || out.tLadder == nil { out.endedBefore = true }
        b.abortAll(r.sim, r.skinner)
        return out
    }

    func soloStarts() -> [(String, SIMD2<Float>)] {
        _ = parkLab(n: 1, seed: 1, aspect: Self.portrait)
        let c = DecorField.shared.foot(ParkToys.slideUID)!.centre
        var l: [(String, SIMD2<Float>)] = []
        for k in 0..<8 { let a = Float(k) * .pi / 4; l.append(("compass\(k)", c + SIMD2(sinf(a), cosf(a)) * 2.5)) }
        l.append(("foot", SIMD2(2.9, 3.24))); l.append(("corner1", SIMD2(3.13, 3.55))); l.append(("corner2", SIMD2(1.30, 3.55)))
        l.append(("C1real", SIMD2(1.86, 2.40)))
        l.append(("C1real2", SIMD2(1.30, 3.55)))
        l.append(("west0", SIMD2(1.2, 0.0))); l.append(("west1", SIMD2(1.5, 1.5))); l.append(("frontL", SIMD2(2.0, 3.3))); l.append(("northW", SIMD2(1.0, -1.0)))
        return l
    }

    func testWalkRoundNeverEntersTheSlide() {
        var bad: [String] = [], lines: [String] = []
        for (aname, aspect) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            var all: [(String, SIMD2<Float>)] = soloStarts()
            for s in soloStarts() where s.0 == "C1real" || s.0 == "foot" || s.0.hasPrefix("corner") || s.0 == "west1" || s.0 == "frontL" { all.append((s.0 + "+afterRide", s.1)) }
            for (name0, p) in all {
                let after = name0.hasSuffix("+afterRide"), name = name0
                var o = runSolo(name, p, aspect: aspect, afterRide: after)
                if o.skipped {
                    lines.append("PSR T1 \(aname) \(name) skipped (off the floor)"); continue
                }
                o.label = "\(aname) \(name)"
                lines.append(String(format: "PSR T1 %@ started %d ladder %@ depth %.2f (%@) still %.1f s (%@) legs %@", o.label, o.started ? 1 : 0, o.tLadder.map { String(format: "%.1f", $0) } ?? "NO", o.maxDepth, o.depthAt, o.still, o.stillAt, o.legs.joined(separator: " ")))
                if !o.started { bad.append("\(o.label): did not start"); continue }
                if o.maxDepth > 0.02 { bad.append("\(o.label): inside the box \(o.maxDepth) at \(o.depthAt)") }
                if o.tLadder == nil { bad.append("\(o.label): never reached the ladder (ended t \(o.endT))") }
                else if o.tLadder! > 25 { bad.append("\(o.label): ladder only at \(o.tLadder!) s") }
                if o.still > 1.5 { bad.append("\(o.label): stood still \(o.still) s at \(o.stillAt)") }
            }
        }
        for l in lines { print(l) }
        XCTAssertTrue(bad.isEmpty, "walk round the slide: " + bad.joined(separator: " | "))
    }

    // MARK: T2

    /// One line about body k: where, which slide stage and target, what the walk is doing, who is near.
    func diag(_ lab: SocialTests.Lab, _ k: Int) -> String {
        let b = lab.rigs[k].brain, st = b.idleState
        let near = lab.rigs.enumerated().filter { $0.offset != k }.map { String(format: "b%d@%.2f(%@/%@)", $0.offset, simd_distance($0.element.brain.position, b.position), "\($0.element.brain.activity)", "\(String(describing: $0.element.brain.idleState.kind))") }.joined(separator: " ")
        return String(format: "at (%.2f,%.2f) stage %d slideS %d retry %d target (%.2f,%.2f) act %@ commanded %d decorIgnore %@ route %d scriptT %.1f walkStallT %.1f stuckT %.1f steerWait %.1f | %@", b.position.x, b.position.y, st.slideStage, st.slideS, st.decorRetry, st.target.x, st.target.y, "\(b.activity)", b.commanded ? 1 : 0, "\(String(describing: b.decorIgnore))", b.route.count, b.scriptT, b.walkStallT, b.stuckT, b.steerWait, near)
    }

    func testWalkRoundWithFriendsRarelyDrops() {
        var attempts = 0, dropped = 0, still3 = 0, still6 = 0, boxSamples = 0, heldWp = 0, boxEpisodes = 0
        var deepest: Float = 0
        var notes: [String] = []
        for (aname, aspect) in [("portrait", Self.portrait), ("landscape", Self.landscape)] {
            for seed in UInt64(1)...6 {
                if let only = ProcessInfo.processInfo.environment["T2_ONLY"], only != "\(aname):\(seed)" { continue }          // (debug: one run, e.g. portrait:6)
                let lab = parkLab(n: 3, seed: seed, aspect: aspect, starts: [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, 2.4)], quiet: false)
                var simT: Float = 0
                if ProcessInfo.processInfo.environment["T2_ONLY"] != nil { BlobBrain.slideLog = { print("PSR REPLAN t\(String(format: "%.2f", simT)) \($0)") } }
                let sl = DecorField.shared.foot(ParkToys.slideUID)!
                let bx = box(sl)
                var open = [Bool](repeating: false, count: 3), reached = [Bool](repeating: false, count: 3)
                var ref = lab.rigs.map { $0.brain.position }, refT: Float = 0
                var still = [Float](repeating: 0, count: 3), stillCounted3 = [Bool](repeating: false, count: 3), stillCounted6 = [Bool](repeating: false, count: 3)
                var wpHold = [Float](repeating: 0, count: 3), wpTarget = [SIMD2<Float>](repeating: .zero, count: 3), wpCounted = [Bool](repeating: false, count: 3), wpRef = [SIMD2<Float>](repeating: .zero, count: 3)
                var t: Float = 0
                var inBox = [Bool](repeating: false, count: 3), boxMax = [Float](repeating: 0, count: 3)
                for i in 0..<(90 * 60) {
                    if i % 30 == 5 {
                        for (k, r) in lab.rigs.enumerated() where r.brain.idleState.kind == nil && !r.brain.isSocial && r.brain.pending == nil {
                            if r.brain.startCommandedDecor(.decorSlide, only: .slide, r.sim, r.skinner) { attempts += 1; open[k] = true; reached[k] = false }
                        }
                    }
                    lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60; simT = t
                    for (k, r) in lab.rigs.enumerated() {
                        let b = r.brain, st = b.idleState
                        let using = st.kind == .decorSlide && st.decorUID == ParkToys.slideUID
                        if using, st.slideStage >= 1 { reached[k] = true }
                        if open[k], !using { if !reached[k] { dropped += 1; notes.append("drop \(aname) s\(seed) body\(k) t\(String(format: "%.1f", t)) at (\(String(format: "%.2f,%.2f", b.position.x, b.position.y)))") }; open[k] = false }
                        if using, st.slideStage < 1, insideDepth(bx, b.position) > 0.02 {
                            boxSamples += 1
                            boxMax[k] = max(boxMax[k], insideDepth(bx, b.position))
                            if !inBox[k] { inBox[k] = true; boxEpisodes += 1; boxMax[k] = insideDepth(bx, b.position); if boxEpisodes <= 12 { notes.append("box \(aname) s\(seed) body\(k) t\(String(format: "%.1f", t)) \(diag(lab, k))") } }
                        } else if inBox[k] { inBox[k] = false; deepest = max(deepest, boxMax[k]); notes.append("boxend \(aname) s\(seed) body\(k) t\(String(format: "%.1f", t)) max depth \(boxMax[k]) stage \(st.slideStage) ignore \(String(describing: b.decorIgnore))") }
                        if using, st.slideStage == -1 || st.slideStage == -3 {
                            // a waypoint of the way round (a corner, the gate) held: not moving (under 0.1 in 1.5 s), nobody within 2.0
                            let near = lab.rigs.enumerated().contains { $0.offset != k && simd_distance($0.element.brain.position, b.position) < 2.0 }
                            if simd_distance(st.target, wpTarget[k]) > 0.01 || simd_distance(b.position, wpTarget[k]) > 99 { wpTarget[k] = st.target; wpHold[k] = 0; wpCounted[k] = false; wpRef[k] = b.position }
                            if simd_distance(b.position, wpRef[k]) > 0.1 || near { wpRef[k] = b.position; wpHold[k] = 0 }
                            else { wpHold[k] += 1.0 / 60; if wpHold[k] > 1.5, !wpCounted[k] { wpCounted[k] = true; heldWp += 1; notes.append("held wp \(aname) s\(seed) body\(k) t\(String(format: "%.1f", t)) \(diag(lab, k))") } }
                        } else { wpHold[k] = 0; wpRef[k] = b.position }
                    }
                    if t - refT >= 0.5 {
                        for (k, r) in lab.rigs.enumerated() {
                            let b = r.brain, st = b.idleState
                            let neg = st.kind == .decorSlide && st.decorUID == ParkToys.slideUID && st.slideStage < 0
                            if neg, simd_distance(b.position, ref[k]) < 0.05 { still[k] += 0.5 } else { still[k] = 0; stillCounted3[k] = false; stillCounted6[k] = false }
                            if still[k] > 3, !stillCounted3[k] { stillCounted3[k] = true; still3 += 1; notes.append("still3 \(aname) s\(seed) body\(k) t\(String(format: "%.1f", t)) \(diag(lab, k))") }
                            if still[k] > 6, !stillCounted6[k] { stillCounted6[k] = true; still6 += 1 }
                            ref[k] = b.position
                        }
                        refT = t
                    }
                }
                for r in lab.rigs { r.brain.abortAll(r.sim, r.skinner) }
            }
        }
        for n in notes.prefix(120) { print("PSR T2 note \(n)") }
        let rate = attempts > 0 ? Float(dropped) / Float(attempts) : 0
        print("PSR T2 attempts \(attempts) dropped \(dropped) (\(rate)) still>3s \(still3) still>6s \(still6) box samples \(boxSamples) (episodes \(boxEpisodes), deepest \(deepest)) waypoint held >1.5 s with nobody within 2.0: \(heldWp)")
        XCTAssertGreaterThan(attempts, 20, "enough attempts")
        XCTAssertLessThanOrEqual(rate, 0.2, "dropped before the ladder \(dropped) of \(attempts)")
        XCTAssertEqual(still6, 0, "no stand-still over 6 s")
        XCTAssertEqual(boxSamples, 0, "never inside the slide box")
        XCTAssertEqual(heldWp, 0, "no waypoint held over 1.5 s with nobody near")
    }
}
