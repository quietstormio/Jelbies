//
//  BlobSocial+Peak.swift
//  Motion warping for the touching emotes (2026-11-04, drive round 1): a lunge / bump / shove / lean-in must PEAK at skin contact, never past it. The drives write their lean as authored
//  amplitudes (0.2 rad = ~16 cm of skin travel per body at the cheek height), which sink the bodies 15 cm into each other whenever the pair stands at the hold gap or the wind-up was shorter than
//  the strike. This guard sits between the drive and the engine's lean trim (`socialTick`: socialDrive -> peakGuard -> contactApplyLean): it measures the live skin gap to the partner and
//  caps the TOWARD-partner part of the drive's lean at what the remaining gap allows (the current eased lean + the room still open, shared between both leaners). A wind-up (lean away) opens the
//  room, so the strike travels exactly the opened distance and lands at contact; at the hold gap the lean-in is simply zero. Lean away, sideways lean and everything with no profile are untouched.
//
import Foundation
import simd

enum PeakTuning {
    static func env(_ k: String, _ d: Float) -> Float { ProcessInfo.processInfo.environment[k].flatMap { Float($0) } ?? d }
    nonisolated(unsafe) static var logLines = 0
    static let log = ProcessInfo.processInfo.environment["PEAK_LOG"] != nil
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["PEAK_OFF"] != "1"
    /// The press / strike moves whose lean is the move itself (the hold kinds - sways, cuddles, hugs - close the last centimetres with the engine's own lean, so the guard leaves them alone: measured, it left them 3-4 cm short).
    static let strikeKinds: Set<SocialKind> = [.bump, .chestBump, .highFive, .bellyBounce, .squabble, .sneak, .cheekSquish, .whisperGiggle]
    /// A/B switches of the two mechanisms (env PEAK_NOGUARD / PEAK_NOARM = 1).
    nonisolated(unsafe) static var guardOn = ProcessInfo.processInfo.environment["PEAK_NOGUARD"] != "1"
    nonisolated(unsafe) static var armOn = ProcessInfo.processInfo.environment["PEAK_NOARM"] != "1"
    /// Skin travel toward the partner (m) per radian of lean, per body (measured: two bodies at 0.09 rad closed 15 cm at the cheek height).
    nonisolated(unsafe) static var reachPerRad: Float = env("PEAK_K", 0.8)
    /// Fraction of the open room one lean-in may use (the skin trails the lean by a few frames; the rest is margin).
    nonisolated(unsafe) static var gain: Float = env("PEAK_GAIN", 0.6)
    /// The widest the drive's own lean-away (wind-up / recoil) may open the skin gap (m): beyond it the stance's settle walks the pair back together, which is what made the bumps oscillate +-15 cm.
    nonisolated(unsafe) static var openCap: Float = env("PEAK_OPEN", 0.045)
    /// The hop / lunge kinds (bump, chestBump, highFive, bellyBounce, sneak): the strike stays AT contact - no wind-up gap beyond 1.5 cm, no squash bulge beyond the live gap, a small impact kick.
    static let pressKinds: Set<SocialKind> = [.bump, .chestBump, .highFive, .bellyBounce, .sneak]
    nonisolated(unsafe) static var pressOpenCap: Float = env("PEAK_POPEN", 0.015)
    static func openCap(for k: SocialKind) -> Float { pressKinds.contains(k) ? pressOpenCap : openCap }
    /// The strike of a press / bump move may start once the pair stands this close (skin gap, m) and is planted (a strike fired mid-walk adds its lean to the walk's closing speed).
    nonisolated(unsafe) static var armGap: Float = env("PEAK_ARM", 0.05)
    /// The most the drive may lean a body toward the partner (rad). A lean is GEOMETRY to the contact engine (a body leaning 0.3 rad reaches 25 cm further, so the stance walk backs the pair off, the lean eases, the walk comes back: the high five swung 3 ... 70 cm for 5 s):
    /// the strike's visible lean stays inside the few cm the approach gap leaves.
    nonisolated(unsafe) static var leanCap: Float = env("PEAK_CAP", 0.08)
    /// The skin gap the lean may close to (the stance's plush rest).
    /// Per-kind override of `openCap` (m). Empty: a squabble value of 1.2 cm was measured with NO effect on the hold (the +-2 cm pulse there is the jelly kick, not the guarded lean).
    static let openCapByKind: [SocialKind: Float] = [:]
    /// Largest impact kick (JellyJiggle units) a touching drive fires at the moment of contact (env PEAK_KICK).
    nonisolated(unsafe) static var kickMax: Float = env("PEAK_KICK", 0.8)
    /// Squash is width: a body squashed by s bulges ~s x its radius at the belly (0.12 sank a bump 2 cm into the partner). The squash the drive may use is `sqBase` + `sqPerM` per metre of live skin gap.
    nonisolated(unsafe) static var sqBase: Float = env("PEAK_SQ0", 0.015)
    nonisolated(unsafe) static var sqPerM: Float = env("PEAK_SQK", 1.5)
    static let rest: Float = -0.006          // (a hair deeper than the stance's -0.4 cm: the approach is asymptotic, and the touch gate fires at +0.5 cm)
    /// Per-kind rest: the bump's squash bulge and the skin trailing the lean add ~0.3 cm of press on top of the lean's rest (measured: deepest -0.88 cm with -0.6), so its lean stops at -0.3 and the deepest frame lands in the approved -0.3..-0.6 band.
    nonisolated(unsafe) static var bumpRest: Float = env("PEAK_BUMP_REST", -0.003)
    static func rest(for k: SocialKind) -> Float { k == .bump ? bumpRest : rest }

    /// The range the drive's toward-partner lean (rad, excluding the engine's own `trim`) may take when the body now leans `now` rad toward the partner with the live skin gap `gap` (m): in at most up to
    /// contact (`rest`), away at most up to `openCap`. Both bodies lean, so the skin travel per radian is twice `reachPerRad`.
    static func leanBounds(now: Float, trim: Float, gap: Float, openCap open: Float? = nil, rest: Float = PeakTuning.rest) -> (maxOut: Float, maxIn: Float) {
        let per = reachPerRad * 2
        let openCap = open ?? Self.openCap
        // (relaxing back to neutral is never blocked: the away bound only stops a lean that is already away from going further)
        return (min(0, now - gain * max(0, openCap - gap) / per - trim), now + gain * max(0, gap - rest) / per - trim)
    }
}

extension BlobBrain {
    /// True when a press / bump move may begin: the pair is planted and within `PeakTuning.armGap` skin to skin (or nothing can be measured). Callers add their own timeout.
    func peakArmed(_ o: BlobBrain) -> Bool {
        guard PeakTuning.enabled, PeakTuning.armOn, ContactField.enabled, ContactField.isValid(steerID), ContactField.isValid(o.steerID),
              var g = ContactField.gap(steerID, o.steerID, features: true) else { return true }
        if let sg = ContactField.skinGap(steerID, o.steerID) { g = min(g, sg) }
        return g <= PeakTuning.armGap && scriptIsNone && o.scriptIsNone && !gait.isBusy && !o.gait.isBusy && !feet.active && !o.feet.active
    }

    /// Keep the TOWARD-partner part of the drive that just ran (`socialBook.wantPitch / wantRoll`) inside what the live skin gap allows: in at most up to contact, away at most up to `openCap`.
    func peakGuard() {
        guard PeakTuning.enabled, PeakTuning.guardOn, ContactField.enabled, let s = social, s.end == nil, !s.kind.isGroup,
              PeakTuning.strikeKinds.contains(s.kind), let st = ContactStance.entry(s.kind), st.cls == .touching, st.step(at: s.phase) != nil,
              let o = s.a === self ? s.b : s.a, ContactField.isValid(steerID), ContactField.isValid(o.steerID),
              var gap = ContactField.gap(steerID, o.steerID, features: st.features) else { return }
        if let sg = ContactField.skinGap(steerID, o.steerID) { gap = min(gap, sg) }
        let local = rotXZ(o.position - position, -yaw), ln = simd_length(local)
        guard ln > 1e-3 else { return }
        let ux = local.x / ln, uy = local.y / ln          // the partner's direction in the body frame (contactApplyLean's convention: roll += -ux * m, pitch += uy * m)
        let book = socialBook
        let wantM = book.wantPitch * uy - book.wantRoll * ux
        let nowM = book.pitch * uy - book.roll * ux
        let b = PeakTuning.leanBounds(now: nowM, trim: book.leanTrim, gap: gap, openCap: PeakTuning.openCapByKind[s.kind] ?? PeakTuning.openCap(for: s.kind), rest: PeakTuning.rest(for: s.kind))
        var m = wantM
        if m > b.maxIn { m = b.maxIn }
        if m > PeakTuning.leanCap { m = PeakTuning.leanCap }
        if m < b.maxOut { m = b.maxOut }
        // squash: cap the drive's squash depth by the live gap (the squash bulge is part of the strike's travel)
        let allowed = PeakTuning.sqBase + PeakTuning.sqPerM * max(0, gap + 0.005)
        if PeakTuning.pressKinds.contains(s.kind), book.wantSquash < 1 - allowed { socialBook.wantSquash = 1 - allowed }
        guard abs(m - wantM) > 1e-5 else { return }
        if PeakTuning.log, PeakTuning.logLines < 600 { PeakTuning.logLines += 1; print(String(format: "[peak] guard %d %@ ph%d gap=%.1fcm want=%.3f now=%.3f trim=%.3f -> %.3f (in<=%.3f out>=%.3f)", steerID, s.kind.rawValue, s.phase, gap * 100, wantM, nowM, book.leanTrim, m, b.maxIn, b.maxOut)) }
        let cut = wantM - m
        socialBook.wantPitch -= cut * uy
        socialBook.wantRoll += cut * ux
    }
}

extension BlobBrain {
    /// The jelly's contact wobble is a skin displacement: a big kick at a bump / hug moves the drawn skin 2-3 cm into the partner for a frame or two. The hop / lunge kinds scale their impact kicks down to what the skin can take at contact.
    func impactKick(_ v: Float) -> Float { min(v, PeakTuning.kickMax) }
}

extension BlobBrain {
    /// A hop that lands where the body IS. `startHopPlay` eases the body from the sim's centroid to the brain's root (+ the distance): a pair standing skin to skin has its meshes 5-8 cm off the roots (the lean / shear that closes the
    /// last centimetres), so a hop "on the spot" to the root moved both bodies 7 cm apart at take-off (measured: 12 cm gap from 0 in one tick). Aim the hop at the centroid instead (its component along the facing; the hop goes the way he faces).
    func hopOnTheSpot(_ sim: SoftBody) {
        let c = sim.bodyPose(iterations: 6).centroid
        let fwd = SIMD2<Float>(sinf(yaw), cosf(yaw))
        let d = simd_dot(SIMD2(c.x, c.z) - position, fwd)
        startHopPlay(sim: sim, distance: max(0.0001, min(0.25, d)))
    }
}
