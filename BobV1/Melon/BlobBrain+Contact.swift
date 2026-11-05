//
//  BlobBrain+Contact.swift
//  Soft meetings (2026-10-26): Jelbies that walk into or past each other used to be pushed apart hard. Now
//    - the room's peer separation is a spring (MelonStage.keepApart: a continuous, partial push, no pop),
//    - an autonomous walker whose straight leg would pass a Jelly closer than the gap curves round him EARLY (a side-step waypoint on the side away from him,
//      his right if he is dead ahead, so two walkers meeting head on pass each other),
//    - bodies that press touch with a small squish and a wobble (a jelly kick, a faint lean away), once per contact, never a buzz.
//  All of it rides on existing mechanisms (the route waypoints, the jelly kick, the social overlay): the walk, the feet and the arms are untouched.
//

import Foundation
import simd

enum ContactTuning {
    nonisolated(unsafe) static var lookAhead = true
    nonisolated(unsafe) static var leanLimiter = true          // the lean toward a partner never grows past skin contact (ContactSettle.swift: contactApplyLean)
    static let hopWarpMax: Float = 0.30          // a scripted ring / circle hop may be warped this far off its own line by the settle (ContactSettle.swift: contactNudge)
    static let lookDistance: Float = 2.4          // how far ahead along the leg a Jelly counts
    static let contactFrac: Float = 0.97          // closer than this fraction of the gap = the bodies touch
    static let cooldown: Float = 1.6
    static let walkerSpeed: Float = 0.8           // what a walker is assumed to cover per second when predicting where two will meet
    static let lookTime: Float = 3.0              // how far ahead (s) the meeting of two walkers is looked for
    static let leanBudget: Float = 0.11          // rad of lean a planted body spends on a residual gap (~ 2.7 cm at the cheeks, measured: 0.08 rad closed 1.8 cm in the boop trace); beyond it: one shuffle step
    static let leanPerMetre: Float = 3.2          // rad per metre to close (measured 2026-11-04: a lean of 1 rad moves the skin contact ~ 0.22 m)
    static let rearmHold: Float = 0          // seconds apart before the next touch counts
    static let touchGap: Float = 0.005, rearmGap: Float = 0.03, eventGap: Float = 0.35          // the skin gap that counts as touching (+0.5 cm), the gap that arms the next touch, the least time between two events of one body
    static let yieldMax: Float = 1.2              // the longest a walker with the lower priority waits for a crossing one before going round
}

/// What the look-ahead says about the next leg: nobody in the way, give way for a moment (a crossing walker with the right of way), or curve round via a waypoint.
enum LookAhead { case clear, wait, via(SIMD2<Float>) }

extension BlobBrain {
    /// Kept for the callers that only want a waypoint.
    func lookAheadSidestep(_ root: SIMD2<Float>, _ target: SIMD2<Float>) -> SIMD2<Float>? {
        if case .via(let w) = lookAhead(root, target) { return w }
        return nil
    }

    /// Every other Jelbie - standing AND walking - is a moving obstacle (2026-11-01: "one will walk right through another"). For the leg root -> target, each peer's
    /// position now and where he will be when I am closest to him (his velocity over the last 0.3 s) is compared with the gap:
    ///  - a standing Jelbie in the way: curve round him early, to the side away from him (his right if he is dead ahead);
    ///  - a walker coming head on: both curve to their own right, the lower id (who gives way) by more;
    ///  - a walker crossing my path: the lower id waits a beat (at most `yieldMax` s, then goes round), the higher id walks on - unless it is about to touch;
    ///  - a faster walker coming up behind a slower one: goes round.
    /// This is steering only: the bodies are never pushed apart (`MelonStage.keepApart` stays the last-resort spring).
    func lookAhead(_ root: SIMD2<Float>, _ target: SIMD2<Float>) -> LookAhead {
        let probe = PerfProbe.begin(); defer { PerfProbe.end("lookAheadSidestep", probe) }
        guard ContactTuning.lookAhead, !race.active else { yieldT = max(0, yieldT - runDt); return .clear }
        let d = target - root, L = simd_length(d)
        guard L > 0.8 else { return .clear }
        let dir = d / L, right = SIMD2(dir.y, -dir.x)
        let clear = peerGap * 0.97
        let vSelf = ContactTuning.walkerSpeed
        let horizon = min(L / vSelf, ContactTuning.lookTime)
        struct Hit { var tc: Float; var pos: SIMD2<Float>; var vel: SIMD2<Float>; var id: Int; var walking: Bool; var dmin: Float }
        var hit: Hit?
        for p in steerPeers() {
            let walking = p.id < Int.max / 4
            let vel = walking ? (peerVel[p.id] ?? .zero) : .zero
            let moving = simd_length(vel) > 0.18
            if !moving, simd_distance(p.pos, target) < clear * 1.3 { continue }          // (he stands where I am going: a social walk-up, a meal)
            let rel = p.pos - root
            let vrel = dir * vSelf - (moving ? vel : .zero)
            let vv = simd_dot(vrel, vrel)
            guard vv > 1e-3 else { continue }
            let closing = simd_dot(rel, vrel)
            guard closing > 0.05 else { continue }          // (not closing in: behind me, or walking off faster than I come)
            let tc = min(max(closing / vv, 0), horizon)
            let dmin = simd_length(rel - vrel * tc)
            guard dmin < clear * 0.85 else { continue }
            if !moving { guard simd_dot(rel, dir) < min(L, ContactTuning.lookDistance) else { continue } }
            if hit == nil || tc < hit!.tc { hit = Hit(tc: tc, pos: p.pos, vel: moving ? vel : .zero, id: p.id, walking: moving, dmin: dmin) }
        }
        guard let h = hit else { yieldT = max(0, yieldT - runDt); return .clear }
        let speed = simd_length(h.vel)
        var share: Float = 1.0          // how much of the gap I swing out by
        if h.walking {
            let cosA = simd_dot(dir, h.vel / speed)
            let iYield = steerID < h.id
            if abs(cosA) < 0.6 {          // crossing: the lower id swings out well, the other only when it is about to touch
                if !iYield { if h.tc < 1.2 && h.dmin < clear * 0.75 { share = 0.6 } else { return .clear } }
            } else if cosA < 0 { share = iYield ? 0.85 : 0.55 }          // head on
            else if !iYield || h.dmin > clear * 0.6 { share = 0.8 }          // overtaking
        }
        let q = h.pos + h.vel * h.tc          // where he is when we are closest
        let m = root + dir * (vSelf * h.tc)
        let side = simd_dot(q - m, right)
        let first: Float = side > 0.12 ? -1 : (side < -0.12 ? 1 : 1)          // away from him; dead ahead: my right
        // the floor is narrow (a phone in portrait): a waypoint past the wall is pulled back onto the floor, and the swing may shrink, as long as it still clears him by most of the gap
        // (a narrow floor: when no waypoint clears him by the whole gap, one that clears him by 0.8 of it - the steering floor of `keepApart` - is taken)
        let gap0 = peerGap
        defer { peerGap = gap0 }
        for scale: Float in [1.0, 0.8] {
            peerGap = gap0 * scale
            for sgn in [first, -first] {
                for k: Float in [1.0, 1.15, 0.85, 0.7] {
                    let w0 = q + right * (sgn * clear * share * k)
                    let w = fixed(w0)
                    guard abs(simd_dot(w - q, right)) >= clear * share * 0.62 * scale, simd_distance(w, q) >= clear * share * 0.8 * scale else { continue }
                    if scale >= 1 { guard intrusion(w, margin: steerMargin) < 0.01, legClear(root, w, margin: steerMargin) else { continue } }
                    else { guard simd_distance(w, w0) < 0.2, softLegClear(root, w, r: gap0 * scale) else { continue } }
                    yieldT = max(0, yieldT - runDt)
                    return .via(w)
                }
            }
        }
        peerGap = gap0
        // no room to swing out: give way for a moment (the other walks on), then carry on
        if h.walking, yieldT < ContactTuning.yieldMax { yieldT += runDt; return .wait }
        return .clear
    }

    /// A leg that keeps `r` from every other Jelbie (a Jelbie already closer than that only has to not get closer), whose floor points need at most the soft push of
    /// `keepApart` (< 0.2) - the passing leg of a narrow floor, where the full-gap checks (`legClear`) refuse every way past.
    func softLegClear(_ a: SIMD2<Float>, _ b: SIMD2<Float>, r: Float) -> Bool {
        let ab = b - a, l2 = max(simd_dot(ab, ab), 1e-6)
        for p in steerPeers() {
            if simd_distance(p.pos, b) < r { continue }          // (he is at my destination)
            let t = min(max(simd_dot(p.pos - a, ab) / l2, 0), 1)
            let d = simd_distance(p.pos, a + ab * t), d0 = simd_distance(p.pos, a)
            if d < r && !(d0 < r && d >= d0 - 0.02) { return false }
        }
        let n = max(2, Int(sqrtf(l2) / 0.2))
        for i in 1...n { let p = a + ab * (Float(i) / Float(n)); if simd_distance(fixed(p), p) > 0.2 { return false } }
        return true
    }

    /// A soft meeting: the moment the DRAWN skins first meet (the contact profile's skin gap <= +1 cm, ContactProfile.swift) the bodies kick a little (a jelly kick each, the squish sound,
    /// the contact haptic): once per touch (armed again when the skins part by 3 cm), in a stance as in a brush while roaming; the settle controller's last mm of press never fires again.
    /// Without profiles (a rig that never skins) the old rule stands: closer than 0.97 x the gap and closing, nothing while a social drives the pair.
    func contactTick(_ dt: Float) {
        socialBook.contactCool -= dt
        for (k, v) in socialBook.contactCoolPer where v > 0 { socialBook.contactCoolPer[k] = v - dt }
        guard attached, !held else { return }
        for o in socialOthers() where o !== self {
            if var gap = ContactField.gap(steerID, o.steerID, features: social == nil) {          // (inside a session the drawn body decides, as the harness does; wings only count for a roaming / lying brush)
                if let sg = ContactField.skinGap(steerID, o.steerID) { gap = min(gap, sg) }          // (the support gap of the catalogue: the harness's ground truth for "touching")          // (a wing / tail touched is a touch: the folded wing between two lying backs still squishes)
                let prev = socialBook.contactArmed[o.steerID]
                var armed = prev ?? (gap > ContactTuning.rearmGap)          // (touching when first seen: no event, the touch began before)
                if gap > ContactTuning.rearmGap { let t = (socialBook.contactAwayT[o.steerID] ?? 0) + dt; socialBook.contactAwayT[o.steerID] = t; if t >= ContactTuning.rearmHold || prev == nil { armed = true } }          // (apart by 3 cm for 0.15 s: a one-frame spike of a bounce is not a new touch)
                else { socialBook.contactAwayT[o.steerID] = 0 }
                if armed, gap <= ContactTuning.touchGap, (socialBook.contactCoolPer[o.steerID] ?? 0) <= 0 {
                    armed = false
                    socialBook.contactCoolPer[o.steerID] = ContactTuning.eventGap
                    let press = min(1, max(0, -gap) / 0.03 + 0.4)
                    jellyKick = max(jellyKick, 0.9 + 0.9 * press)
                    if steerID < o.steerID || !(o.attached && !o.held) {          // (one sound + one haptic a touch, not one a body: the lower id, or whoever is left when he cannot)
                        // the emote's own contact sound (ContactStance.table: boop, squish, highfive_boop ...) or the default squish; AudioHub.play sends the sound's haptic cue too
                        // (only while the stance is HOLDING the touch - the press phase; an approach brush or a part is the default squish)
                        let st = contactStance(with: o).flatMap { st in social.flatMap { st.step(at: $0.phase)?.target == ContactStance.hold ? st : nil } }
                        AudioHub.shared.play(st?.sound ?? .squish, jelly: steerID, x: px, volume: st?.sound != nil ? st!.volume : 0.25)
                        if let sess = social { sess.contactTouches += 1 }
                        if (social?.contactTouches ?? 1) <= 1 {          // (the emote's own haptic: once a session, with its first touch; AudioHub.play already sent the sound's cue)
                            switch st?.haptic ?? .none {
                            case .emote(let tag): emoteHaptic(tag, EmoteHaptic.tap)
                            case .treat(let key): treatHaptic(key)
                            case .none: break
                            }
                        }
                        if let sess = social, let any = contactStance(with: o), any.cls == .touching {          // the heart / shove event rides on the touch too (it used to fire on the drive's timer)
                            if sess.kind == .squabble { onSocial?(.shove(partner: o.steerID)); o.onSocial?(.shove(partner: steerID)) }
                            else if !sess.kind.isGroup { onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID)) }
                        }
                        contactEvents += 1
                    }
                }
                socialBook.contactArmed[o.steerID] = armed
                continue
            }
            guard social == nil else { continue }
            let d = simd_distance(o.position, position)
            let prev = socialBook.contactPrev[o.steerID] ?? d
            socialBook.contactPrev[o.steerID] = d
            guard o.social == nil, socialBook.contactCool <= 0, d < peerGap * ContactTuning.contactFrac, d < prev - 0.002 else { continue }          // (closing in)
            socialBook.contactCool = ContactTuning.cooldown
            let press = min(1, (peerGap - d) / (peerGap * 0.25) + 0.4)
            jellyKick = max(jellyKick, 0.9 + 0.9 * press)
            AudioHub.shared.play(.squish, jelly: steerID, x: px, volume: 0.25)
        }
    }
}


extension BlobBrain {
    /// A stance that is walking up / pressing owns the squaring-up turn at its spot (the spot was chosen for the posture the pair ends in, ContactStance.facing): the turn happens in place, it does not back the body off (the
    /// parting retreat of BlobSocial+Part.swift is for walking AWAY - a part, a step apart - and keeps those).
    var contactStanceOwnsTurns: Bool {
        guard ContactField.enabled, let s = social, s.end == nil, let st = ContactStance.entry(s.kind), st.cls == .touching, let step = st.step(at: s.phase) else { return false }
        return step.retargets && socialBook.partFrom < 0
    }
}
