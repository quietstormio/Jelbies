//
//  ParkSlideProbe.swift
//  park-slide-r3 capture aid (`-SlideProbe 1`, simulator only, reads state and logs: no behaviour change). Every fixed step of the park, for every body (the Jelbies who came and the visitors):
//    [slide3] in    a body whose footprint is inside the park slide's box (centre `deep` inside the box, or the footprint over its edge by more than 5 cm, `overlap`), NOT while he
//                   uses the slide from the steps on (slide stage >= 1: the steps, the platform, the ride, the landing). One line when he goes in (his doing, decorIgnore, the last state changes)
//                   and the sample counts per tag in the summary.
//    [slide3] pair  two bodies whose drawn skins are sunk into each other by more than 2 cm (`ContactField.gap`, the keepApart wall's own measure), with both bodies' doing, near the
//                   hopscotch court or not. One line when it starts, sample counts per tag in the summary.
//    [slide3] sum   every 60 probe seconds: the counts (samples at the fixed step, 60 a second), the probe clock against the wall clock.
//    [arrive]       park-arrive-r1, the first 5 s after the swap into the park, every body: his root (the brain's position) against his drawn body (the pose centroid the brain
//                   reads), the drawn centre's distance to the slide's box, the floor rules' pieces at his spot, and every root step over 8 cm with the feet and the step;
//                   `[arrive] sum` per body at 5 s. `[arrive] spot` at the swap: each arrival spot against the walk's own rules.
//

#if targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

enum ParkSlideProbe {
    nonisolated(unsafe) static var on = UserDefaults.standard.integer(forKey: "SlideProbe") != 0
    /// `-SlideBusy 1` (capture aid, park-slide-r4): every 0.5 s each free body that stands idle in the park (the ones who came and the visitors) is sent to the slide.
    nonisolated(unsafe) static var busy = UserDefaults.standard.integer(forKey: "SlideBusy") != 0
    nonisolated(unsafe) static var busySteps = 0
    nonisolated(unsafe) static var t: Double = 0, wall0: Double = 0, lastSum: Double = 0, steps = 0
    nonisolated(unsafe) static var deep: [String: Int] = [:], overlap: [String: Int] = [:], ride: [String: Int] = [:], pairs: [String: Int] = [:], pairsCourt: [String: Int] = [:]
    nonisolated(unsafe) static var inNow: [Int: Bool] = [:], pairNow: [Int: Bool] = [:]
    nonisolated(unsafe) static var lastState: [Int: String] = [:], hist: [Int: [String]] = [:]
    nonisolated(unsafe) static var ignoreSince: [Int: (t: Double, doing: String)] = [:]
    nonisolated(unsafe) static var deepest: [Int: Float] = [:]
    nonisolated(unsafe) static var episodes = 0, pairEpisodes = 0, poolLogged = false, validLogged = false
    /// The crude pair measure (centre distance under the two standing radii, `BobForm.halfW` each, less 2 cm) next to the skin gap, and how many near pairs had both profiles (the skin gap was measured).
    nonisolated(unsafe) static var crude: [String: Int] = [:], crudeCourt: [String: Int] = [:], pairMeasured = 0, pairNear = 0
    /// Riding samples inside the box per slide stage: count, the largest |x| off the chute's centre line (slide frame), the longest continuous dwell (s) in that stage.
    nonisolated(unsafe) static var rideStage: [Int: (n: Int, maxX: Float, dwell: Double)] = [:], rideSince: [Int: (stage: Int, t: Double)] = [:]

    /// What the body is doing, without positions (the tag the counts are kept by).
    static func doing(_ b: BlobBrain) -> String {
        var s: [String] = []
        if let so = b.social { s.append("soc:\(so.kind.rawValue)/p\(so.phase)") }
        if let k = b.idleState.kind {
            var i = "idle:\(k)"
            if BlobBrain.decorKinds.contains(k) { i += "#\(b.idleState.decorUID)/st\(b.idleState.slideStage)\(b.idleState.decorGo ? "/go" : "")" }
            s.append(i)
        }
        s.append("scr:\(b.scriptKindName)")
        s.append("act:\(b.activity)")
        s.append("ign:\(b.decorIgnore == ParkToys.slideUID ? "slide" : b.decorIgnore.map { String($0) } ?? "-")")
        if b.pending != nil { s.append("pending") }
        if b.hurry { s.append("hurry") }          // (the run-out's hurry: it came along into the park until the outing's tidy, see GameCare.outingLanded)
        if b.poseW > 0 { s.append("pose") }
        return s.joined(separator: " ")
    }
}

extension GameCare {
    /// `-SlideBusy 1`: the DENSE soak in the real app (every free body to the slide, every 0.5 s).
    func parkSlideBusy(_ bodies: [JellyActor]) {
        ParkSlideProbe.busySteps += 1
        guard ParkSlideProbe.busySteps % 30 == 5 else { return }
        for a in bodies { if let b = a.brain, b.idleState.kind == nil, !b.isSocial, b.pending == nil, b.scriptIsNone { _ = b.startCommandedDecor(.decorSlide, only: .slide, a.sim, a.skinner) } }          // (standing bodies only: a command aborts the walk he is on, a walk off the slide's foot included)
    }
    func parkSlideProbe(_ bodies: [JellyActor], dt: Float) {
        typealias P = ParkSlideProbe
        guard let sf = DecorField.shared.foot(ParkToys.slideUID) else { return }
        let now = CACurrentMediaTime()
        if P.steps == 0 { P.wall0 = now; P.lastSum = 0 }
        P.steps += 1; P.t += Double(dt)
        if !P.poolLogged {
            P.poolLogged = true
            let book = parkBook
            NSLog("[slide3] cast %@ bodies %@", book.cast.map { "\($0):\(book.visitor($0)?.name ?? "?")" }.joined(separator: ","), bodies.map { "\($0.id)" }.joined(separator: ","))
            var pool: [String] = []
            for id in 0..<ParkTuning.fullPoolSize { if let v = book.visitor(id) { pool.append("\(id):\(v.name):\(v.colour.rawValue)") } }
            NSLog("[slide3] pool %@", pool.joined(separator: " "))
        }
        let court = DecorField.shared.foot(ParkToys.hopscotchUID)
        for a in bodies {
            guard let b = a.brain else { continue }
            let st = P.doing(b)
            if P.lastState[a.id] != st {
                P.lastState[a.id] = st
                var h = P.hist[a.id] ?? []
                h.append(String(format: "%.1f[%@]@(%.2f,%.2f)", P.t, st, b.position.x, b.position.y))
                if h.count > 8 { h.removeFirst(h.count - 8) }
                P.hist[a.id] = h
            }
            if b.decorIgnore == ParkToys.slideUID { if P.ignoreSince[a.id] == nil { P.ignoreSince[a.id] = (P.t, st) } } else { P.ignoreSince[a.id] = nil }
            let cen = a.sim.centroid(), fl = SIMD2<Float>(cen.x, cen.z)          // (the DRAWN body: `a.floor` is the home spot (`outingHome`) until the run-out's tidy, and the root lags while a pose holds)
            let d = min(sf.distance(fl), sf.distance(b.position))
            let riding = b.idleState.kind == .decorSlide && b.idleState.decorUID == ParkToys.slideUID && b.idleState.slideStage >= 1
            let isIn = d < b.footprint * sf.spec.reach - 0.05
            if isIn, riding {
                P.ride[st, default: 0] += 1
                let stg = b.idleState.slideStage
                if P.rideSince[a.id]?.stage != stg { P.rideSince[a.id] = (stg, P.t) }
                var r = P.rideStage[stg] ?? (0, 0, 0)
                r.n += 1; r.maxX = max(r.maxX, abs(sf.local(fl - sf.centre).x)); r.dwell = max(r.dwell, P.t - (P.rideSince[a.id]?.t ?? P.t))
                P.rideStage[stg] = r
            } else { P.rideSince[a.id] = nil }
            if isIn, !riding {
                P.overlap[st, default: 0] += 1
                if d < 0 { P.deep[st, default: 0] += 1 }
                P.deepest[a.id] = min(P.deepest[a.id] ?? 9, d)
                if P.inNow[a.id] != true {
                    P.inNow[a.id] = true; P.episodes += 1
                    let ig = P.ignoreSince[a.id].map { String(format: "since %.1f (%.1f s ago) while [%@]", $0.t, P.t - $0.t, $0.doing) } ?? "-"
                    NSLog("[slide3] in #%d t=%.1f body=%d d=%.2f root=(%.2f,%.2f) floor=(%.2f,%.2f) doing [%@] ignoreSlide %@ hist %@", P.episodes, P.t, a.id, d, b.position.x, b.position.y, fl.x, fl.y, st, ig, (P.hist[a.id] ?? []).joined(separator: " > "))
                }
            } else if P.inNow[a.id] == true {
                P.inNow[a.id] = false
                NSLog("[slide3] out t=%.1f body=%d deepest d=%.2f now [%@] at (%.2f,%.2f)", P.t, a.id, P.deepest[a.id] ?? 9, st, fl.x, fl.y)
                P.deepest[a.id] = nil
            }
        }
        if !P.validLogged, P.t > 5 {
            P.validLogged = true
            NSLog("[slide3] profiles %@", bodies.map { "\($0.id):\(ContactField.isValid($0.id) ? "ok" : "NONE")" }.joined(separator: " "))
        }
        // pairs: drawn skins sunk into each other by more than 2 cm (and the crude centre-distance measure beside it)
        let crudeAt = Float(2 * BobForm.halfW) - 0.02
        let drawn = Dictionary(bodies.map { ($0.id, { (c: SIMD3<Float>) in SIMD2<Float>(c.x, c.z) }($0.sim.centroid())) }, uniquingKeysWith: { x, _ in x })
        for (i, a) in bodies.enumerated() {
            guard let ba = a.brain else { continue }
            for c in bodies[(i + 1)...] {
                guard let bc = c.brain else { continue }
                let key = min(a.id, c.id) * 64 + max(a.id, c.id)
                let pa = drawn[a.id] ?? a.floor, pc = drawn[c.id] ?? c.floor
                let dist = simd_distance(pa, pc)
                var sunk = false
                var g: Float = 9, gf: Float = 9
                if dist < 1.4 {
                    P.pairNear += 1
                    if let v = ContactField.gap(a.id, c.id, features: false) {
                        P.pairMeasured += 1
                        g = v; gf = ContactField.gap(a.id, c.id, features: true) ?? v
                        sunk = g < -0.02
                    }
                }
                guard dist < crudeAt || sunk || P.pairNow[key] == true else { continue }
                let same = ba.social != nil && ba.social === bc.social
                let tag = same ? "SAME \(ba.social!.kind.rawValue)/p\(ba.social!.phase)" : [P.doing(ba), P.doing(bc)].sorted().joined(separator: " x ")
                let nearCourt = court.map { $0.distance(pa) < 0.8 || $0.distance(pc) < 0.8 } ?? false
                if dist < crudeAt { P.crude[tag, default: 0] += 1; if nearCourt { P.crudeCourt[tag, default: 0] += 1 } }
                if sunk {
                    P.pairs[tag, default: 0] += 1
                    if nearCourt { P.pairsCourt[tag, default: 0] += 1 }
                    if P.pairNow[key] != true {
                        P.pairNow[key] = true; P.pairEpisodes += 1
                        NSLog("[slide3] pair #%d t=%.1f bodies %d-%d dist=%.2f gap=%.3f gapFeat=%.3f court=%d A[%@]@(%.2f,%.2f) B[%@]@(%.2f,%.2f) histA %@ histB %@", P.pairEpisodes, P.t, a.id, c.id, dist, g, gf, nearCourt ? 1 : 0, P.doing(ba), pa.x, pa.y, P.doing(bc), pc.x, pc.y, (P.hist[a.id] ?? []).suffix(4).joined(separator: " > "), (P.hist[c.id] ?? []).suffix(4).joined(separator: " > "))
                    }
                } else if P.pairNow[key] == true {
                    P.pairNow[key] = false
                    NSLog("[slide3] pairend t=%.1f bodies %d-%d dist=%.2f gap=%.3f", P.t, a.id, c.id, dist, g)
                }
            }
        }
        if P.t - P.lastSum >= 60 {
            P.lastSum = P.t
            func fmt(_ m: [String: Int]) -> String { m.sorted { $0.value > $1.value }.prefix(12).map { "\($0.value)x{\($0.key)}" }.joined(separator: " ; ") }
            NSLog("[slide3] sum t=%.0f wall=%.0f steps=%d episodes=%d deepSamples=%d overlapSamples=%d rideSamples=%d pairEpisodes=%d pairSamples=%d pairCourtSamples=%d", P.t, now - P.wall0, P.steps, P.episodes, P.deep.values.reduce(0, +), P.overlap.values.reduce(0, +), P.ride.values.reduce(0, +), P.pairEpisodes, P.pairs.values.reduce(0, +), P.pairsCourt.values.reduce(0, +))
            NSLog("[slide3] sum overlap %@", fmt(P.overlap))
            NSLog("[slide3] sum deep %@", fmt(P.deep))
            NSLog("[slide3] sum pairs %@", fmt(P.pairs))
            NSLog("[slide3] sum pairsCourt %@", fmt(P.pairsCourt))
            NSLog("[slide3] sum crude near=%d measured=%d crudeSamples=%d crudeCourtSamples=%d", P.pairNear, P.pairMeasured, P.crude.values.reduce(0, +), P.crudeCourt.values.reduce(0, +))
            NSLog("[slide3] sum crudeTags %@", fmt(P.crude))
            NSLog("[slide3] sum crudeCourtTags %@", fmt(P.crudeCourt))
            NSLog("[slide3] sum rideByStage %@", P.rideStage.sorted { $0.key < $1.key }.map { String(format: "st%d n=%d maxX=%.2f dwell=%.1f", $0.key, $0.value.n, $0.value.maxX, $0.value.dwell) }.joined(separator: " ; "))
        }
    }
}
extension ParkSlideProbe {
    /// park-arrive-r1: seconds since the swap into the park (nil: no arrival being watched). Two windows: the arrival (0-5 s) and a control later in the same visit (10-15 s).
    nonisolated(unsafe) static var arriveT: Double?
    nonisolated(unsafe) static var arriveSteps = 0
    nonisolated(unsafe) static var arriveLastRoot: [Int: SIMD2<Float>] = [:], arriveLastStep: [Int: SIMD2<Float>] = [:]
    struct ArriveWorst { var misPosed: Float = 0, misPosedAt: Double = 0, box: Float = 99, boxAt: Double = 0, rootStep: Float = 0, rootStepAt: Double = 0, stride: Float = 0, strideAt: Double = 0, inBox = 0 }
    nonisolated(unsafe) static var arriveWorst: [Int: ArriveWorst] = [:]
    static func arriveWindow(_ t: Double) -> String? { t < 5 ? "early" : (t >= 10 && t < 15 ? "late" : nil) }
}

extension GameCare {
    /// park-arrive-r1 capture aid (`-SlideProbe 1`): from the swap (`parkSwap(.park)` sets `arriveT` = 0), every step, every body: his root (the brain's position) against his drawn
    /// body (the pose centroid the brain reads), the drawn centre's distance to the slide's box, every walk step's length and every root move in one fixed step. Per body and window
    /// (`early` 0-5 s, `late` 10-15 s, the control) one `[arrive] sum` line. Detail lines (every 0.1 s, on a mismatch over 0.2 m, on a root step over 8 cm) in the early window.
    func parkArriveProbe(_ bodies: [JellyActor], dt: Float) {
        typealias P = ParkSlideProbe
        guard var t = P.arriveT else { return }
        let sf = DecorField.shared.foot(ParkToys.slideUID)
        P.arriveSteps += 1
        let win = P.arriveWindow(t), early = win == "early"
        if early, P.arriveSteps % 6 == 1 { NSLog("[arrive] care t=%.2f phase=%@ dining=%@ wanted=%d trayOut=%d meal=%d", t, "\(park.phase)", "\(dining.phase)", wanted != nil ? 1 : 0, trayOut ? 1 : 0, meal != nil ? 1 : 0) }
        for a in bodies {
            guard let b = a.brain else { continue }
            let c = a.sim.bodyPose(iterations: 4).centroid, drawn = SIMD2<Float>(c.x, c.z), root = b.position          // (the drawn body as the brain reads it: `currentPose` sets the root from this centroid)
            let mis = simd_distance(root, drawn)
            let riding = b.idleState.kind == .decorSlide && b.idleState.decorUID == ParkToys.slideUID
            let dBox = sf.map { $0.distance(drawn) } ?? 99, dBoxRoot = sf.map { $0.distance(root) } ?? 99
            let last = P.arriveLastRoot[a.id] ?? root
            let jump = simd_distance(root, last)
            P.arriveLastRoot[a.id] = root
            var stride: Float = 0
            if b.stepLive, P.arriveLastStep[a.id] != b.stepRoot0 { P.arriveLastStep[a.id] = b.stepRoot0; stride = simd_length(b.stepRootD) }          // (a new walk step: its root move)
            if win != nil {
                var w = P.arriveWorst[a.id] ?? P.ArriveWorst()
                if b.poseW > 0, mis > w.misPosed { w.misPosed = mis; w.misPosedAt = t }
                if !riding, dBox < w.box { w.box = dBox; w.boxAt = t }
                if !riding, dBox <= 0 { w.inBox += 1 }
                if jump > w.rootStep { w.rootStep = jump; w.rootStepAt = t }
                if stride > w.stride { w.stride = stride; w.strideAt = t }
                P.arriveWorst[a.id] = w
            }
            if win != nil, jump > 0.08 || stride > 0.6 {
                let f = b.fixed(root), fl = b.fixed(last)
                NSLog("[arrive] jump %@ t=%.2f body=%d from=(%.2f,%.2f) to=(%.2f,%.2f) stride=%.2f walkRulesAtFrom=(%.2f,%.2f) movedFrom=%.2f walkRulesAtTo=(%.2f,%.2f) movedTo=%.2f poseW=%.2f feetInit=%d stepRoot0=(%.2f,%.2f) stepRootD=(%.2f,%.2f) doing [%@]", win ?? "-", t, a.id, last.x, last.y, root.x, root.y, stride, fl.x, fl.y, simd_distance(fl, last), f.x, f.y, simd_distance(f, root), b.poseW, b.feetInit ? 1 : 0, b.stepRoot0.x, b.stepRoot0.y, b.stepRootD.x, b.stepRootD.y, P.doing(b))
            }
            guard early else { continue }
            var tgt = "-"
            if case .walk(let target, _) = b.script { tgt = String(format: "(%.2f,%.2f)", target.x, target.y) }
            if P.arriveSteps % 30 == 1 {
                let q3 = SIMD3(root.x, 0, root.y)
                let cam = GameCamera.constrain(q3, radius: b.footprint, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: b.decorIgnore)
                let lay = RoomLayout.resolve(position: q3, radius: b.footprint, lowPropScale: RoomLayout.lowPropRadiusScale, ignoreDecor: b.decorIgnore)
                let tray = trayObstacle(q3, radius: b.footprint, id: a.id), f = b.fixed(root)
                NSLog("[arrive] rules t=%.2f body=%d at=(%.2f,%.2f) camera=(%.2f,%.2f) layout=(%.2f,%.2f) tray=(%.2f,%.2f) walkRules=(%.2f,%.2f) roamZ=%.2f..%.2f keepOut=%d rowOpen=%d ign=%d", t, a.id, root.x, root.y, cam.x, cam.z, lay.x, lay.z, tray.x, tray.z, f.x, f.y, GameCamera.roamMinZ, GameCamera.roamMaxZ, focusKeepOutFor(a.id) != nil ? 1 : 0, focusGroup.rowOpen ? 1 : 0, b.decorIgnore ?? -1)
            }
            if P.arriveSteps % 6 == 1 || mis > 0.2 || jump > 0.08 {
                NSLog("[arrive] t=%.2f phase=%@ body=%d root=(%.2f,%.2f) drawn=(%.2f,%.2f) mis=%.2f jump=%.3f dBox=%.2f dBoxRoot=%.2f poseW=%.2f stepLive=%d feet=%d lifted=%d arena=(%.2f,%.2f r%.2f%@) floor=(%.2f,%.2f) target=%@ doing [%@]",
                      t, "\(park.phase)", a.id, root.x, root.y, drawn.x, drawn.y, mis, jump, dBox, dBoxRoot, b.poseW, b.stepLive ? 1 : 0, b.feet.active ? 1 : 0, outing.lifted.contains(a.id) ? 1 : 0,
                      a.sim.arenaCenter.x, a.sim.arenaCenter.y, a.sim.arenaRadius, a.sim.arenaSuspended ? " SUSP" : "", a.floor.x, a.floor.y, tgt, P.doing(b))
            }
        }
        let next = t + Double(dt)
        func sums(_ name: String) {
            for (id, w) in P.arriveWorst.sorted(by: { $0.key < $1.key }) {
                NSLog("[arrive] sum %@ body=%d maxMismatchPosed=%.2f@%.2f minBoxDrawn=%.2f@%.2f boxSamples=%d maxStride=%.2f@%.2f maxRootStep=%.3f@%.2f", name, id, w.misPosed, w.misPosedAt, w.box, w.boxAt, w.inBox, w.stride, w.strideAt, w.rootStep, w.rootStepAt)
            }
            P.arriveWorst = [:]
        }
        if t < 5, next >= 5 { sums("early") }
        if next >= 15 { sums("late"); P.arriveT = nil; P.arriveLastRoot = [:]; P.arriveLastStep = [:] } else { t = next; P.arriveT = t }
    }
}
extension ParkSlideProbe {
    /// park-arrive-r2: which trip's arrival is watched (`park`, `race`, `show`, `cafe`, `groom`) and, for the trips other than the park, the bodies that ran out to it (the outing's runners).
    nonisolated(unsafe) static var arriveTrip = "park", arriveIDs: Set<Int> = []
    /// `-StartTrip race|show|cafe` (capture aid, park-arrive-r2): that trip for Jelly 0 once the room is up, asked again every ~0.75 s until it runs (as `-StartPark`).
    nonisolated(unsafe) static var startTrip = UserDefaults.standard.string(forKey: "StartTrip"), startTripFrames = 0
}

extension GameCare {
    /// park-arrive-r2: the park's arrival probe at another trip's swap. Every body of the trip is watched (the runners' ids are listed: `outingHome` is theirs).
    func tripArriveStart(_ name: String) {
        typealias P = ParkSlideProbe
        guard P.on else { return }
        P.arriveT = 0; P.arriveSteps = 0; P.arriveWorst = [:]; P.arriveLastRoot = [:]; P.arriveLastStep = [:]
        P.arriveTrip = name; P.arriveIDs = Set(outing.runners.keys)
        NSLog("[arrive] trip=%@ runners=%@", name, P.arriveIDs.sorted().map { String($0) }.joined(separator: ","))
    }
    func tripArriveTick(_ name: String, _ bodies: [JellyActor], dt: Float) {
        guard ParkSlideProbe.on, ParkSlideProbe.arriveT != nil, ParkSlideProbe.arriveTrip == name else { return }
        parkArriveProbe(bodies, dt: dt)
    }
    /// `-StartTrip` (see `ParkSlideProbe.startTrip`).
    func tickStartTrip() {
        typealias P = ParkSlideProbe
        guard let k = P.startTrip else { return }
        if tripActive { P.startTrip = nil; return }
        P.startTripFrames += 1
        guard P.startTripFrames > 90, P.startTripFrames % 45 == 0, !outing.running else { return }
        switch k {
        case "race": startRace(jelly: 0)
        case "show": startShow(jelly: 0)
        case "cafe": requestCafe()
        default: P.startTrip = nil
        }
    }
}
#endif
