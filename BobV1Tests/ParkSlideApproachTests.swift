//
//  ParkSlideApproachTests.swift
//  The park slide: nobody walks THROUGH the chute and the frame on the way to the ladder behind it (the slide is solid for him while he walks to it), the hops start only from behind it,
//  and the rider does not land into bodies at the foot. Numbers (the home start rate, the landing measurement, the bench / seesaw check) are printed.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class ParkSlideApproachTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    nonisolated(unsafe) static var cache: [Run]?

    override func setUp() {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0
    }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    func parkLab(n: Int, seed: UInt64 = 5, quiet: Bool = true) -> SocialTests.Lab {
        DecorField.shared.clear(); DecorField.shared.toys = ToyBook()          // (r8: no slide left taken by the previous run)
        RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark(); _ = GameCamera.refreshRoam(aspect: 440.0 / 956.0)
        let starts: [SIMD2<Float>] = [SIMD2(-2.1, -1.35), SIMD2(-0.7, 0.2), SIMD2(0.4, -0.4), SIMD2(-1.2, 2.2), SIMD2(0.9, 2.4)]
        let lab = SocialTests.Lab(n: n, positions: Array(starts.prefix(n)), quiet: quiet, seed: seed)
        for r in lab.rigs { r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius; r.brain.anticsEnabled = true; r.brain.idleMood = .happy }
        DecorField.shared.set(ParkToys.placed)
        DecorField.shared.toys.news.removeAll()
        return lab
    }

    // MARK: the slide's frame

    /// Half extents in the slide's own frame (x across, z along the chute).
    func localHalf(_ sl: DecorFoot) -> SIMD2<Float> { sl.quarter & 1 == 0 ? sl.spec.half : SIMD2(sl.spec.half.y, sl.spec.half.x) }
    func localPoint(_ sl: DecorFoot, _ p: SIMD2<Float>) -> SIMD2<Float> { sl.local(p - sl.centre) }
    func climbSpot(_ sl: DecorFoot) -> SIMD2<Float> { sl.centre + sl.turned(SIMD2(0, -DecorKind.slideApproach)) }
    /// How far behind the back edge line the point is (positive = behind).
    func behind(_ sl: DecorFoot, _ p: SIMD2<Float>) -> Float { -localPoint(sl, p).y - localHalf(sl).y }

    func place(_ r: MotionRig, _ p: SIMD2<Float>) {
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: p)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
    }

    struct Run {
        var label: String, n: Int, seed: UInt64
        var skipped = false, started = false
        var worstDepth: Float = .infinity, worstWhere = ""
        var firstHop: Bool?, hopInfo = ""
        var t4: Float?, saw5 = false, saw6 = false, endT: Float?, endedOutside = false
        var last = ""
        var minFriend: Float = .infinity          // (smallest centre distance to a parked friend while he walked)
        var finalDist: Float = .infinity          // (distance of his root from the slide's footprint when the run ends)
        var rode: Bool { (t4 ?? 99) <= 30 && saw5 && saw6 && endedOutside }
        /// r8: what the ride itself needs. He really slid: stage 5 (the ride) ran to the end of the chute (`idleState.slideS` reached `BlobBrain.slideLength`, which is what moves the ride on to stage 6).
        var maxSlideS: Float = 0, t6: Float?, offLandingAt: Float?, restAt: Float?
        var slid: Bool { saw5 && maxSlideS >= BlobBrain.slideLength - 0.05 }
        var rodeNew: Bool { (t4 ?? 99) <= 30 && saw6 && slid }
        /// The walk-out kept honest: off the landing (beyond 0.6) within 3 s of landing and at rest (no behaviour, no script) within 8 s of landing.
        var walkOutHonest: Bool { guard t6 != nil else { return true }; return (offLandingAt ?? 99) <= 3 && (restAt ?? 99) <= 8 }
    }

    func starts(_ sl: DecorFoot) -> [(String, SIMD2<Float>)] {
        let h = localHalf(sl)
        let l: [(String, SIMD2<Float>)] = [("front", SIMD2(0, h.y + 0.9)), ("frontLeft", SIMD2(-(h.x + 0.5), h.y + 0.4)), ("frontRight", SIMD2(h.x + 0.5, h.y + 0.4)),
                                           ("midLeft", SIMD2(-(h.x + 0.7), 0)), ("midRight", SIMD2(h.x + 0.7, 0)), ("behindLeft", SIMD2(-(h.x + 0.6), -h.y - 0.6))]
        return l.map { ($0.0, sl.centre + sl.turned($0.1)) }
    }

    /// One forced slide start from `p` (park lab, `n` bodies, the others wander or, with `peerOnClimb`, one stands on the climb spot).
    func runStart(_ label: String, _ p: SIMD2<Float>, n: Int, seed: UInt64, peerOnClimb: Bool = false, friendAt: SIMD2<Float>? = nil) -> Run {
        var out = Run(label: label, n: n, seed: seed)
        let lab = parkLab(n: n, seed: seed)
        let sl = DecorField.shared.foot(ParkToys.slideUID)!
        let r = lab.rigs[0], b = r.brain
        if let friendAt { place(lab.rigs[1], friendAt); lab.rigs[1].brain.restTimer = 1e6 }
        else if peerOnClimb { place(lab.rigs[1], climbSpot(sl)) }
        else { for k in 1..<n { lab.rigs[k].brain.restTimer = 0.5 } }
        let q = b.fixed(p)
        if simd_distance(p, q) > 0.1 { out.skipped = true; return out }
        place(r, q)
        for _ in 0..<5 { lab.tick(watching: false) }
        b.idleForced = true
        out.started = b.decorStart(.decorSlide, r.sim, only: .slide, uid: nil)
        if !out.started { return out }
        let climb = climbSpot(sl), need = b.footprint * sl.spec.reach - 0.08
        let landing = b.slideLanding(sl)
        var t: Float = 0, outsideChecked = false
        while t < 45 {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            if friendAt != nil, out.endT == nil { out.minFriend = min(out.minFriend, simd_distance(b.position, lab.rigs[1].brain.position)) }
            let st = b.idleState
            if st.kind == .decorSlide, st.decorUID == ParkToys.slideUID {
                let d = simd_distance(b.position, climb)
                if st.slideStage < 1, d > 0.9 {
                    let depth = sl.distance(b.position) - need
                    if depth < out.worstDepth { out.worstDepth = depth; out.worstWhere = "t=\(t) stage \(st.slideStage) at \(b.position) (slide distance \(sl.distance(b.position)))" }
                }
                if st.slideStage == 1, out.firstHop == nil {
                    out.firstHop = d <= 0.9 && behind(sl, b.position) > 0
                    out.hopInfo = "first hop from \(b.position): \(d) from the climb spot, \(behind(sl, b.position)) behind the back edge"
                }
                if st.slideStage == 4, out.t4 == nil { out.t4 = t }
                if st.slideStage == 5 { out.saw5 = true; out.maxSlideS = max(out.maxSlideS, st.slideS) }
                if st.slideStage == 6 { out.saw6 = true; if out.t6 == nil { out.t6 = t } }
            }
            if st.kind == nil, out.endT == nil { out.endT = t; b.idleForced = false; b.autonomy = false }          // (r8: the run now goes on to 8 s after the landing: he must not start another behaviour and leave the slide taken for the next run)
            if let t6 = out.t6 {
                if out.offLandingAt == nil, simd_distance(b.position, landing) > 0.6 { out.offLandingAt = t - t6 }
                if out.restAt == nil, st.kind == nil, case .none = b.script { out.restAt = t - t6 }
            }
            if let e = out.endT, !outsideChecked, t >= e + 1.5 { outsideChecked = true; out.endedOutside = sl.distance(b.position) >= b.footprint * sl.spec.reach - 0.05 }
            if let e = out.endT, t >= e + 1.5, out.t6 == nil || t - out.t6! >= 8 { break }
        }
        out.finalDist = sl.distance(b.position)
        out.last = "kind \(String(describing: b.idleState.kind)) stage \(b.idleState.slideStage) retry \(b.idleState.decorRetry) go \(b.idleState.decorGo) at \(b.position) target \(b.idleState.target) script \(b.script) ignore \(String(describing: b.decorIgnore))"
        return out
    }

    func sweep() -> [Run] {
        if let c = Self.cache { return c }
        var all: [Run] = []
        for n in [1, 3] {
            for seed in UInt64(1)...4 {
                _ = parkLab(n: 1, seed: seed)
                let sl = DecorField.shared.foot(ParkToys.slideUID)!
                for (name, p) in starts(sl) { all.append(runStart(name, p, n: n, seed: seed)) }
            }
        }
        Self.cache = all
        return all
    }

    // MARK: tests

    func testApproachGoesRoundTheSlide() {
        let runs = sweep()
        var skipped: [String] = [], worst: Float = .infinity, where_ = ""
        for r in runs {
            if r.skipped { skipped.append("\(r.label) n\(r.n) s\(r.seed)"); continue }
            if r.label == "front", r.n == 1 { XCTAssertTrue(r.started, "the front start is not refused (n \(r.n) seed \(r.seed))") }
            if r.worstDepth < worst { worst = r.worstDepth; where_ = "\(r.label) n\(r.n) s\(r.seed): \(r.worstWhere)" }
            XCTAssertGreaterThanOrEqual(r.worstDepth, 0, "\(r.label) n\(r.n) seed \(r.seed): walked into the slide, \(r.worstWhere)")
        }
        print("SLIDEAPPROACH skipped (no floor): \(skipped)")
        print("SLIDEAPPROACH worst depth margin \(worst) at \(where_) (negative = inside the footprint by more than a walker can be)")
    }

    func testHopsStartBehindTheSlide() {
        for r in sweep() where r.started {
            if let ok = r.firstHop { XCTAssertTrue(ok, "\(r.label) n\(r.n) seed \(r.seed): \(r.hopInfo)") }
        }
        // a friend parked exactly on the climb spot: either no start, or the same rule
        var checked = 0, refused = 0
        for seed in UInt64(1)...4 {
            _ = parkLab(n: 1, seed: seed)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            for (name, p) in starts(sl) where name.hasPrefix("front") || name == "midLeft" {
                let r = runStart(name, p, n: 2, seed: seed, peerOnClimb: true)
                if r.skipped { continue }
                if !r.started { refused += 1; continue }
                checked += 1
                if let ok = r.firstHop { XCTAssertTrue(ok, "peer on the climb spot, \(r.label) seed \(seed): \(r.hopInfo)") }
                XCTAssertGreaterThanOrEqual(r.worstDepth, 0, "peer on the climb spot, \(r.label) seed \(seed): walked into the slide, \(r.worstWhere)")
            }
        }
        print("SLIDEHOPS with a peer on the climb spot: \(checked) starts checked, \(refused) refused")
    }

    func testHeStillRidesFromEveryStart() {
        let runs = sweep().filter { !$0.skipped }
        let times = runs.map { String(format: "%@/n%d/s%d:%@", $0.label, $0.n, Int($0.seed), $0.t4.map { String(format: "%.1f", $0) } ?? "-") }.joined(separator: " ")
        for r in runs where !r.rode { print("SLIDEFAIL \(r.label) n\(r.n) s\(r.seed) started \(r.started) \(r.last)") }
        let one = runs.filter { $0.n == 1 }, three = runs.filter { $0.n == 3 }
        let rode1 = one.filter { $0.rode }.count, rode3 = three.filter { $0.rode }.count
        let refused = three.filter { !$0.started }.count
        let dropped = three.filter { $0.started && !$0.rode && $0.finalDist >= 0.55 - 0.05 }.count
        print("SLIDERIDES n1 \(rode1) of \(one.count), n3 \(rode3) of \(three.count) (refused at start \(refused), dropped on the way \(dropped)); platform times: \(times)")
        XCTAssertEqual(rode1, one.count, "alone he rides from every start")
        print("SLIDERIDES3 time to the platform per n3 run: " + three.map { String(format: "%@/s%d:%@", $0.label, Int($0.seed), $0.t4.map { String(format: "%.1f", $0) } ?? "-") }.joined(separator: " "))
        let rodeNew3 = three.filter { $0.rodeNew }.count, dishonest = three.filter { !$0.walkOutHonest }
        print("SLIDERIDES-R8 n3 old counting (stage 5 and 6 and out of the zone 1.5 s after the ride) \(rode3) of \(three.count); new counting (really slid to the end of the chute, stage 6 reached) \(rodeNew3) of \(three.count); walk-out honest (off the landing > 0.6 within 3 s, at rest within 8 s): " + three.filter { $0.t6 != nil }.map { String(format: "%@/s%d:off %@ rest %@", $0.label, Int($0.seed), $0.offLandingAt.map { String(format: "%.1f", $0) } ?? "-", $0.restAt.map { String(format: "%.1f", $0) } ?? "-") }.joined(separator: " "))
        XCTAssertGreaterThanOrEqual(rodeNew3, 9, "with friends around he really slides from at least 9 of \(three.count) starts (slid and reached stage 6: \(rodeNew3); old counting \(rode3))")
        XCTAssertTrue(dishonest.isEmpty, "the walk-out after the ride is off the landing within 3 s and at rest within 8 s: " + dishonest.map { "\($0.label)/s\(Int($0.seed)) off \(String(describing: $0.offLandingAt)) rest \(String(describing: $0.restAt))" }.joined(separator: ", "))
    }

    /// A friend PARKED beside the way round (0.6 left of the leg, half way between the two left corners), rider from the front, 4 seeds: he still rides, never inside the footprint.
    func testParkedFriendOnTheWayRound() {
        var rode = 0, tried = 0
        var times: [String] = [], mins: [Float] = []
        for seed in UInt64(1)...4 {
            _ = parkLab(n: 1, seed: seed)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            let h = localHalf(sl)
            let lat = h.x + 0.55 + 0.1
            let friend = sl.centre + sl.turned(SIMD2(-(lat + 0.6), 0))
            guard let front = starts(sl).first(where: { $0.0 == "front" }) else { continue }
            let r = runStart("front", front.1, n: 2, seed: seed, friendAt: friend)
            if r.skipped { continue }
            tried += 1
            if r.rode { rode += 1 } else { print("SLIDEFAIL parked-friend s\(seed) started \(r.started) \(r.last)") }
            times.append(String(format: "s%d:%@", Int(seed), r.t4.map { String(format: "%.1f", $0) } ?? "-")); mins.append(r.minFriend)
            XCTAssertGreaterThanOrEqual(r.worstDepth, 0, "parked friend, seed \(seed): walked into the slide, \(r.worstWhere)")
        }
        print("SLIDEPARKED friend at left of the way round: rode \(rode) of \(tried); time to the platform \(times); smallest centre distance to the friend while walking \(mins) (jellyGap \(MelonController.jellyGap))")
        XCTAssertEqual(rode, tried, "he still rides with a friend parked beside the way round")
    }

    /// The home room's slide runs the same code: how many of 40 seeded starts from spread-out floor spots succeed (printed; compared base against fix in the report).
    func testHomeSlideStartRate() throws {
        _ = OnePieceInvariantTests.configured
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 603.0 / 1311.0)
        defer { DecorField.shared.clear() }
        let r = MotionRig(game: true, settle: 0.5)
        Self.keep.append(r)
        var seedState: UInt64 = 12345
        func rnd() -> Float { seedState = seedState &* 6364136223846793005 &+ 1442695040888963407; return Float((seedState >> 33) & 0xFFFFFF) / Float(0xFFFFFF) }
        var ok = 0, tried = 0, line = ""
        for _ in 0..<40 {
            let p = SIMD2<Float>(-1.8 + 3.6 * rnd(), -1.0 + 3.4 * rnd())
            DecorField.shared.clear(); DecorField.shared.set([PlacedDecor(uid: 7, kind: .slide, x: 1.0, z: -0.2)])
            let q = r.brain.fixed(p)
            if simd_distance(p, q) > 0.1 { continue }
            place(r, q)
            tried += 1
            r.brain.idleForced = true
            let s = r.brain.decorStart(.decorSlide, r.sim, only: .slide, uid: nil)
            if s { ok += 1 }
            line += s ? "1" : "0"
            r.brain.abortAll(r.sim, r.skinner)
        }
        print("HOMESLIDE start rate \(ok) of \(tried) (\(line))")
        XCTAssertGreaterThan(tried, 15, "enough floor spots")
    }

    /// Part B: the rider and the landing. 5 bodies, 8 seeds x 120 s, someone forced onto the slide every 20 s. Prints; asserts only the platform cap.
    func testLandingMeasure() {
        var rides = 0, pushedIntoPeer = 0, longest: Float = 0
        var minAfter: Float = .infinity, minAfterTag = ""
        for seed in UInt64(1)...8 {
            let lab = parkLab(n: 5, seed: seed, quiet: false)
            let sl = DecorField.shared.foot(ParkToys.slideUID)!
            let landing = sl.centre + sl.turned(SIMD2(0, BlobBrain.slideAt(BlobBrain.slideLength).z))
            var prev = [Int](repeating: 0, count: 5), kindPrev = [Bool](repeating: false, count: 5)
            var platformT = [Float](repeating: 0, count: 5), afterT = [Float](repeating: -1, count: 5)
            for i in 0..<(120 * 60) {
                if i % (20 * 60) == 60 {
                    for (k, r) in lab.rigs.enumerated() where r.brain.idleState.kind == nil && !r.brain.isSocial && r.brain.pending == nil && !kindPrev.contains(true) {
                        r.brain.idleForced = true
                        if r.brain.decorStart(.decorSlide, r.sim, only: .slide, uid: nil) { _ = k; break }
                    }
                }
                lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                for (k, r) in lab.rigs.enumerated() {
                    let b = r.brain, st = b.idleState
                    let using = st.kind == .decorSlide && st.decorUID == ParkToys.slideUID
                    if using, st.slideStage == 4 { platformT[k] += 1.0 / 60; longest = max(longest, platformT[k]) }
                    if using, st.slideStage == 5, prev[k] != 5 {
                        rides += 1
                        let near = lab.rigs.enumerated().contains { $0.offset != k && simd_distance($0.element.brain.position, landing) < b.peerGap }
                        if near { pushedIntoPeer += 1 }
                    }
                    if using, st.slideStage != 4 { platformT[k] = 0 }
                    if using, st.slideStage == 6 { afterT[k] = 0 }
                    if afterT[k] >= 0 {
                        afterT[k] += 1.0 / 60
                        for (j, o) in lab.rigs.enumerated() where j != k {
                            let d = simd_distance(b.position, o.brain.position)
                            if d < minAfter { minAfter = d; minAfterTag = "seed \(seed) t=\(Float(i) / 60) rider \(k) peer \(j)" }
                        }
                        if afterT[k] > 1.5 { afterT[k] = -1 }
                    }
                    prev[k] = using ? st.slideStage : 0; kindPrev[k] = using
                }
            }
        }
        print("SLIDELANDING rides \(rides), pushed off with a peer inside peerGap of the landing \(pushedIntoPeer), smallest rider-peer centre distance in the 1.5 s after the ride \(minAfter) (\(minAfterTag)), longest platform wait \(longest) s")
        XCTAssertGreaterThan(rides, 0, "someone rode")
    }

    /// Report only: does the bench / seesaw approach (decorIgnore set at the start of the walk) go through the piece from a front start?
    func testReportSitApproachFromTheFront() {
        var lines: [String] = []
        for (name, kind, uid) in [("seesaw", DecorKind.seesaw, ParkToys.seesawUID)] {
            var worstOverall: Float = .infinity, started = 0, tried = 0
            for seed in UInt64(1)...4 {
                let lab = parkLab(n: 1, seed: seed)
                guard let pc = DecorField.shared.foot(uid) else { continue }
                let h = localHalf(pc)
                let ring: [SIMD2<Float>] = [SIMD2(0, h.y + 0.9), SIMD2(-(h.x + 0.5), h.y + 0.4), SIMD2(h.x + 0.5, h.y + 0.4), SIMD2(0, -h.y - 0.9)]
                for loc in ring {
                    let p = pc.centre + pc.turned(loc)
                    let r = lab.rigs[0], b = r.brain
                    let q = b.fixed(p)
                    if simd_distance(p, q) > 0.1 { continue }
                    place(r, q); for _ in 0..<5 { lab.tick(watching: false) }
                    tried += 1
                    b.idleForced = true
                    guard b.decorStart(.decorSit, r.sim, only: kind, uid: nil) else { continue }
                    started += 1
                    var worst: Float = .infinity
                    for _ in 0..<(60 * 20) {
                        lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
                        if b.idleState.kind == .decorSit, b.idleState.decorUID == uid, b.idleState.bagStage == 0, b.idleState.decorGo {
                            worst = min(worst, pc.distance(b.position) - (b.footprint * pc.spec.reach - 0.08))
                        }
                        if b.idleState.kind == nil { break }
                    }
                    worstOverall = min(worstOverall, worst)
                    b.abortAll(r.sim, r.skinner)
                }
            }
            lines.append("\(name): \(started) of \(tried) front/back starts began; worst depth margin while walking to the seat \(worstOverall) (negative = through the piece)")
        }
        print("SITAPPROACH " + lines.joined(separator: " | "))
    }
}
