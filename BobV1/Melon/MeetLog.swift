//
//  MeetLog.swift
//  meet-natural-r1: the measurement of HOW a pair / group gets into a shared moment (dev capture, `-EmoteLog 1`): one `[meetmoment]` line per moment that reached its emote (session phase >= 2).
//  Fields: kind, who (n bodies), t0 (the pick), te (the emote phase), gap (spread of the bodies' arrival times = the last time each translated before te; a body that never moved arrived at t0),
//  wait (seconds the first arrival stood before the last one arrived), side (lateral metres in the 0.6 s before each body's own arrival, relative to its facing), turn (degrees turned on the spot between a body's
//  arrival and te), pre (pick -> session start). Nothing here changes behaviour.
//

import Foundation
import simd

@MainActor
final class MeetRec {
    struct S { var t: Float; var p: SIMD2<Float>; var yaw: Float }
    let kind: SocialKind
    var ids: [Int]
    let t0: Float
    var samples: [Int: [S]] = [:]
    var sessionT: Float = -1
    var how: String
    init(kind: SocialKind, ids: [Int], t0: Float, how: String) { self.kind = kind; self.ids = ids; self.t0 = t0; self.how = how }
}

@MainActor
enum MeetLog {
    nonisolated(unsafe) static var on: Bool { EmoteSpot.logOn }
    static var recs: [Int: MeetRec] = [:]          // by body id
    static var count: [String: Int] = [:]

    static func pick(_ a: BlobBrain, _ o: BlobBrain, _ kind: SocialKind, how: String) {
        guard on else { return }
        drop(a.steerID); drop(o.steerID)
        let r = MeetRec(kind: kind, ids: [a.steerID, o.steerID], t0: a.variety.now, how: how)
        recs[a.steerID] = r; recs[o.steerID] = r
    }
    /// A session began (any path): start a record if the pick did not.
    static func began(_ s: SocialSession, _ crew: [BlobBrain]) {
        guard on else { return }
        let ids = crew.map(\.steerID)
        if let r = recs[ids[0]], r.kind == s.kind, r.sessionT < 0 { r.sessionT = crew[0].variety.now; r.ids = ids; for i in ids { recs[i] = r }; return }
        for i in ids { drop(i) }
        let r = MeetRec(kind: s.kind, ids: ids, t0: crew[0].variety.now, how: "direct")
        r.sessionT = r.t0
        for i in ids { recs[i] = r }
    }
    static func drop(_ id: Int) {
        guard let r = recs[id] else { return }
        for i in r.ids where recs[i] === r { recs[i] = nil }
    }
    /// Every brain tick (socialTick).
    static func sample(_ b: BlobBrain) {
        guard on, let r = recs[b.steerID] else { return }
        let now = b.variety.now
        r.samples[b.steerID, default: []].append(MeetRec.S(t: now, p: b.position, yaw: b.yaw))
        guard b.steerID == r.ids[0] else { return }
        if now - r.t0 > 40 { finish(r, ok: false, now: now, why: "timeout"); return }
        if let s = b.social {
            if r.sessionT < 0, s.kind == r.kind { r.sessionT = now }
            if s.phase >= 2 { finish(r, ok: true, now: now, why: "ok") }
            else if s.end != nil { finish(r, ok: false, now: now, why: "ended") }
        } else if r.sessionT >= 0 { finish(r, ok: false, now: now, why: "aborted") }
    }
    private static func wrap(_ a: Float) -> Float { var x = a; while x > .pi { x -= 2 * .pi }; while x < -.pi { x += 2 * .pi }; return x }
    static func finish(_ r: MeetRec, ok: Bool, now te: Float, why: String) {
        for i in r.ids where recs[i] === r { recs[i] = nil }
        var arr: [Float] = [], side: [Float] = [], turn: [Float] = [], moved: [Float] = []
        for id in r.ids {
            let ss = r.samples[id] ?? []
            var tarr = r.t0, idx = -1
            for i in 0..<ss.count {
                var j = i; while j > 0, ss[i].t - ss[j].t < 0.25 { j -= 1 }
                let dt = ss[i].t - ss[j].t
                if dt > 0.1, simd_distance(ss[i].p, ss[j].p) / dt > 0.08 { tarr = ss[i].t; idx = i }
            }
            arr.append(tarr)
            moved.append(ss.count > 1 ? simd_distance(ss.first!.p, ss.last!.p) : 0)
            if idx >= 0 {
                var k = idx; while k > 0, ss[idx].t - ss[k].t < 0.6 { k -= 1 }
                let d = ss[idx].p - ss[k].p, y = ss[idx].yaw
                side.append(abs(d.x * cosf(y) - d.y * sinf(y)))
                turn.append(abs(wrap(ss.last!.yaw - ss[idx].yaw)) * 180 / .pi)
            } else { side.append(0); turn.append(abs(wrap((ss.last?.yaw ?? 0) - (ss.first?.yaw ?? 0))) * 180 / .pi) }
        }
        let lo = arr.min() ?? 0, hi = arr.max() ?? 0
        let ref = r.sessionT >= 0 ? r.sessionT : r.t0
        NSLog("[meetmoment] kind=%@ n=%d ok=%d why=%@ how=%@ t0=%.1f te=%.2f pre=%.2f gap=%.2f wait=%.2f side=%@ turn=%@ moved=%@ arr=%@", r.kind.rawValue, r.ids.count, ok ? 1 : 0, why, r.how, r.t0, te, r.sessionT >= 0 ? r.sessionT - r.t0 : -1, hi - lo, hi - lo,
              side.map { String(format: "%.3f", $0) }.joined(separator: ","), turn.map { String(format: "%.0f", $0) }.joined(separator: ","), moved.map { String(format: "%.2f", $0) }.joined(separator: ","), arr.map { String(format: "%.2f", $0 - ref) }.joined(separator: ","))
        if ok { count[r.kind.rawValue, default: 0] += 1 }
    }
}
