//
//  ParkSlideProbe.swift
//  park-slide-r3 capture aid (`-SlideProbe 1`, simulator only, reads state and logs: no behaviour change). Every fixed step of the park, for every body (the Jelbies who came and the visitors):
//    [slide3] in    a body whose footprint is inside the park slide's box (centre `deep` inside the box, or the footprint over its edge by more than 5 cm, `overlap`), NOT while he
//                   uses the slide from the steps on (slide stage >= 1: the steps, the platform, the ride, the landing). One line when he goes in (his doing, decorIgnore, the last state changes)
//                   and the sample counts per tag in the summary.
//    [slide3] pair  two bodies whose drawn skins are sunk into each other by more than 2 cm (`ContactField.gap`, the keepApart wall's own measure), with both bodies' doing, near the
//                   hopscotch court or not. One line when it starts, sample counts per tag in the summary.
//    [slide3] sum   every 60 probe seconds: the counts (samples at the fixed step, 60 a second), the probe clock against the wall clock.
//

#if targetEnvironment(simulator)
import Foundation
import QuartzCore
import simd

enum ParkSlideProbe {
    nonisolated(unsafe) static var on = UserDefaults.standard.integer(forKey: "SlideProbe") != 0
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
        if b.poseW > 0 { s.append("pose") }
        return s.joined(separator: " ")
    }
}

extension GameCare {
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
            let fl = a.floor
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
        for (i, a) in bodies.enumerated() {
            guard let ba = a.brain else { continue }
            for c in bodies[(i + 1)...] {
                guard let bc = c.brain else { continue }
                let key = min(a.id, c.id) * 64 + max(a.id, c.id)
                let dist = simd_distance(a.floor, c.floor)
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
                let nearCourt = court.map { $0.distance(a.floor) < 0.8 || $0.distance(c.floor) < 0.8 } ?? false
                if dist < crudeAt { P.crude[tag, default: 0] += 1; if nearCourt { P.crudeCourt[tag, default: 0] += 1 } }
                if sunk {
                    P.pairs[tag, default: 0] += 1
                    if nearCourt { P.pairsCourt[tag, default: 0] += 1 }
                    if P.pairNow[key] != true {
                        P.pairNow[key] = true; P.pairEpisodes += 1
                        NSLog("[slide3] pair #%d t=%.1f bodies %d-%d dist=%.2f gap=%.3f gapFeat=%.3f court=%d A[%@]@(%.2f,%.2f) B[%@]@(%.2f,%.2f) histA %@ histB %@", P.pairEpisodes, P.t, a.id, c.id, dist, g, gf, nearCourt ? 1 : 0, P.doing(ba), a.floor.x, a.floor.y, P.doing(bc), c.floor.x, c.floor.y, (P.hist[a.id] ?? []).suffix(4).joined(separator: " > "), (P.hist[c.id] ?? []).suffix(4).joined(separator: " > "))
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
#endif
