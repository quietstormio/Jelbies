//
//  ContactStance.swift
//  THE TABLE of the touching stances (2026-11-03, g-contactmig; catalogue in docs/CONTACT_EMOTES.md): for every social kind, what "touching" means for it and when.
//    class      touching (the skins meet: skin gap 0 +- 0.5 cm, one sound + haptic per touch) / proximity (they stand or move close, never overlap: gap >= 0) / none
//    steps      per session phase: the skin gap the settle controller (ContactSettle.swift) holds from that phase on (nil = off). An APPROACH step stands a few cm apart (above the 3 cm
//               re-arm of `contactTick`), so the touch - and its sound - happens when the emote's own press / bump phase starts, not when the walker arrives.
//    anchor     the partner who does not move (the booped one, the sneaked-up-on one); asleep / lying / held bodies are always anchored
//    features   the gap counts wings / tail / spikes / daisy at their current fold (back to back, sneak, peekaboo, leapfrog, the spins, the huddles)
//    sound      the emote's own contact sound + haptic, fired by `contactTick` at the touch (ONE per touch, none while apart); nil = the default squish
//  ONE call site: `BlobBrain.contactStanceTick` from the brain tick (BlobBrain.swift, just before the idle moves take the body), every step while a session is on. No drive is edited to hold a distance.
//

import Foundation
import simd

/// The haptic that rides on a touch besides the sound's own cue (AudioHub.play already sends the squish / boop / wobble cue).
enum ContactHaptic: Sendable { case none, emote(String), treat(String) }

struct ContactStance: Sendable {
    enum Class: Sendable { case touching, proximity, none }
    enum Anchor: Sendable { case none, a, b }
    struct Step: Sendable { var from: Int; var target: Float?; var onlySeparate = false }
    var cls: Class
    var steps: [Step]
    var anchor: Anchor = .none
    var features = false
    var sound: SFX? = nil
    var volume: Float = 0.25
    var haptic: ContactHaptic = .none
    /// Real re-touches inside the hold: (phase, from, to) in seconds of the phase - the pair eases `approach` apart (> the 3 cm re-arm) and meets again, so a second squeeze / press is a second
    /// touch with its own sound (the drives' old extra sounds, now on a real contact).
    var pulses: [(phase: Int, from: Float, to: Float)] = []

    /// The skin gap the settle holds in phase `p`: nil = the stance is off.
    func step(at p: Int) -> Step? {
        var r: Step?
        for s in steps where s.from <= p { r = s }
        guard let r, r.target != nil else { return nil }
        return r
    }

    // MARK: building blocks
    /// Plush rest point of a touch: 0.2 cm of press (inside the 0.5 cm sound window, far above the -1 cm limit).
    static let hold: Float = -0.004
    /// Where an approach stands before the press (above the 3 cm re-arm of contactTick, so the touch is a fresh one).
    static let approach: Float = 0.04
    /// Proximity: stay at least this far (above the 0.5 cm sound window, so a near miss never squishes).
    static let near: Float = 0.012

    /// Touching for the whole hold from phase `from`.
    static func holding(from: Int, until: Int? = nil, anchor: Anchor = .none, features: Bool = false, sound: SFX? = nil, volume: Float = 0.25, haptic: ContactHaptic = .none, pulses: [(phase: Int, from: Float, to: Float)] = []) -> ContactStance {
        var st = [Step(from: 0, target: near, onlySeparate: true), Step(from: from, target: hold)]
        if let u = until { st.append(Step(from: u, target: near, onlySeparate: true)) }
        return ContactStance(cls: .touching, steps: st, anchor: anchor, features: features, sound: sound, volume: volume, haptic: haptic, pulses: pulses)
    }
    /// Approach (stand `approach` apart) from `from`, press from `press`, off from `until`.
    static func pressing(from: Int, press: Int, until: Int? = nil, anchor: Anchor = .none, features: Bool = false, sound: SFX? = nil, volume: Float = 0.25, haptic: ContactHaptic = .none) -> ContactStance {
        var st = [Step(from: 0, target: near, onlySeparate: true), Step(from: from, target: approach), Step(from: press, target: hold)]
        if let u = until { st.append(Step(from: u, target: near, onlySeparate: true)) }
        return ContactStance(cls: .touching, steps: st, anchor: anchor, features: features, sound: sound, volume: volume, haptic: haptic)
    }
    /// Never overlap (and never squish): gap >= `near` from phase `from`.
    static func proximity(from: Int = 0, features: Bool = false) -> ContactStance {
        ContactStance(cls: .proximity, steps: [Step(from: from, target: near, onlySeparate: true)], features: features)
    }

    // MARK: the table
    static let table: [SocialKind: ContactStance] = [
        // press / bump kinds: stand a few cm apart, touch when the move presses
        .boop: .pressing(from: 1, press: 2, anchor: .b, sound: .squish, volume: 0.5),
        .squabble: .pressing(from: 1, press: 1, until: 2, sound: .squish, volume: 0.5),
        .bump: .pressing(from: 1, press: 2, sound: .boop, volume: 0.9),
        .sneak: .pressing(from: 1, press: 2, until: 3, anchor: .b, features: true, sound: .boop, volume: 0.9),
        .chestBump: .pressing(from: 1, press: 2, until: 3, sound: .squish, volume: 0.9),
        .highFive: .pressing(from: 1, press: 2, until: 3, sound: .highFiveBoop, volume: 0.85, haptic: .emote("highFive.bump")),
        .tag: .pressing(from: 1, press: 2, until: 3, sound: .boop, volume: 0.9),
        .noseBoop: .pressing(from: 1, press: 2, until: 3, sound: .boop, volume: 0.8),
        .bellyBounce: .pressing(from: 1, press: 2, until: 3, sound: .squish, volume: 0.9),
        .chase: .pressing(from: 2, press: 2, until: 3, sound: .boop, volume: 0.9),
        // holds
        .nuzzle: .holding(from: 2),
        .sitTogether: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true), Step(from: 2, target: hold)]),
        .hum: .holding(from: 2),
        .cheekSquish: .holding(from: 2, sound: .squish, volume: 0.7, pulses: [(2, 1.2, 1.7)]),
        .backToBack: .holding(from: 3, features: true),
        .cuddleLean: .holding(from: 2, sound: .squish, volume: 0.5),
        .swayHug: .holding(from: 2, sound: .squish, volume: 0.55),
        .whisperGiggle: .holding(from: 2),
        .ringAround: .holding(from: 2, features: true),
        .spinHug: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true), Step(from: 2, target: hold), Step(from: 3, target: near, onlySeparate: true)], features: true, sound: .emoteSpinHug, volume: 1, haptic: .treat("spinHug.press")),
        // groups
        .groupHug: .holding(from: 2, features: true, sound: .squish, volume: 0.7, pulses: [(2, 1.9, 2.4)]),
        .circleDance: .holding(from: 2, features: true),
        // proximity
        .twirl: .proximity(from: 1), .hopAlong: .proximity(from: 1), .littleRace: .proximity(), .leapfrog: .proximity(features: true),
        .peekaboo: .proximity(features: true), .mirrorDance: .proximity(from: 1), .danceOff: .proximity(from: 1), .shyWave: .proximity(from: 3),
        .groupCheer: .proximity(from: 1), .conga: .proximity(), .congaLine: .proximity(features: true), .ringDance: .proximity(features: true),
        .follow: .proximity(), .line: .proximity(), .dance: .proximity(from: 1), .greet: .proximity(), .keepAway: .proximity(),
    ]
    static func entry(_ k: SocialKind) -> ContactStance? { table[k] }
}

extension BlobBrain {
    /// The stance of the session `self` and `o` are both in (nil = not in the same session, or none for the kind).
    func contactStance(with o: BlobBrain) -> ContactStance? {
        guard let s = social, o.social === s, s.end == nil, let st = ContactStance.entry(s.kind), st.cls != .none else { return nil }
        return st
    }

    /// Called from `socialDrive` by the session's initiator, every step: hold the pair(s) of the session at the skin gap the stance table asks for in the current phase.
    func contactStanceTick(_ s: SocialSession) {
        guard ContactField.enabled, let st = ContactStance.entry(s.kind), st.cls != .none, let step = st.step(at: s.phase), let target = step.target else { return }
        if s.kind.isGroup {
            let mem = s.members
            guard mem.count >= 2 else { return }
            let target = st.pulses.contains { $0.phase == s.phase && s.phaseT >= $0.from && s.phaseT < $0.to } ? ContactStance.approach : target
            if s.kind == .groupHug || s.kind == .circleDance {          // a ring: each body with the two next to it (angle order), never the far side of the ring
                let order = mem.sorted { (s.slotAng[$0.steerID] ?? 0) < (s.slotAng[$1.steerID] ?? 0) }
                let n = order.count
                for i in 0..<n where n > 2 || i == 0 {
                    let a = order[i], b = order[(i + 1) % n]
                    contactSettlePair(a, b, st, step, target)
                }
            } else {
                for i in 0..<mem.count { for j in (i + 1)..<mem.count { contactSettlePair(mem[i], mem[j], st, step, target) } }
            }
            return
        }
        guard let a = s.a, let b = s.b else { return }
        contactSettlePair(a, b, st, step, st.pulses.contains { $0.phase == s.phase && s.phaseT >= $0.from && s.phaseT < $0.to } ? ContactStance.approach : target)
        if let c = s.c, s.kind == .line { contactSettlePair(a, c, st, step, target) }
    }

    private func contactSettlePair(_ a: BlobBrain, _ b: BlobBrain, _ st: ContactStance, _ step: ContactStance.Step, _ target: Float) {
        func fixed(_ x: BlobBrain, _ role: ContactStance.Anchor) -> Bool {
            return x.held || x.idleState.kind == .sleep || (st.anchor == role && st.anchor != .none)
        }
        guard let s = a.social else { return }
        let aa = fixed(a, s.a === a ? .a : .b), bb = fixed(b, s.a === b ? .a : .b)
        ContactSettle.step(a, b, target: target, anchoredA: aa, anchoredB: bb, onlySeparate: step.onlySeparate, features: st.features, urgent: true, support: true)
    }
}

extension BlobBrain {
    /// The root distance at which my skin and `o`'s just touch along the unit `u` (from him to me), from the two contact profiles (support reach of each toward the other); nil before a skin pass.
    /// The approach spots of the touching stances use it instead of a constant: `touchRadius(o, along: u).map { $0 + ContactStance.approach } ?? fallback`.
    func touchRadius(_ o: BlobBrain, along u: SIMD2<Float>) -> Float? {
        guard let ea = ContactField.supportExt(steerID, -u), let eb = ContactField.supportExt(o.steerID, u) else { return nil }
        return ea + eb
    }
}

extension BlobBrain {
    /// The root distance to stand from `o` for a close stance, along `u` (from him to me): `want` (the emote's old constant) but never closer than the skins touch + the approach margin
    /// (a stance that stands inside the partner is what made the touching emotes overlap). Never under 1.445 (side-by-side touch 1.405 + margin: bodies turn on the spot after arriving, and the widest axis must clear).
    func standGap(_ o: BlobBrain, along u: SIMD2<Float>, _ want: Float) -> Float {
        guard ContactField.enabled else { return want }
        let fallback: Float = 1.445          // (the widest axis, 1.405 + the margin: a body turning on the spot - squaring up to the camera - never ends up inside him)
        return max(want, fallback, touchRadius(o, along: u).map { $0 + ContactStance.approach } ?? 0)
    }
}

extension BlobBrain {
    /// After a session: for 1.5 s the partners are kept apart (gap >= 0) while the bodies turn back and the wobble dies out (`SocialBook.glow`: partner id -> seconds left).
    func contactGlowTick(_ dt: Float) {
        guard !socialBook.glow.isEmpty else { return }
        for (id, left) in socialBook.glow {
            if left <= dt || social != nil { socialBook.glow[id] = nil; continue }
            socialBook.glow[id] = left - dt
            if steerID < id, let o = socialBrain(id), o.social == nil { ContactSettle.step(self, o, target: ContactStance.near, onlySeparate: true, features: true) }
        }
    }
}

extension BlobBrain {
    /// The emote's own contact sound (+ haptic) when NO contact profile exists for the pair (a rig that never skins: the Lab, the room-sound counts, UI tests). With profiles - the app - this is a no-op:
    /// `contactTick` fires the same sound and haptic ONCE at the real touch instead (ContactStance.table). So no environment loses a sound.
    func contactCueFallback(_ o: BlobBrain, _ sfx: SFX, _ volume: Float, haptic: ContactHaptic = .none) {
        guard !ContactField.enabled || ContactField.gap(steerID, o.steerID) == nil else { return }
        AudioHub.shared.play(sfx, jelly: steerID, x: px, volume: volume)
        switch haptic {
        case .emote(let tag): emoteHaptic(tag, EmoteHaptic.tap)
        case .treat(let key): treatHaptic(key)
        case .none: break
        }
    }
}
