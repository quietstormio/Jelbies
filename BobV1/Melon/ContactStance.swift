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
    /// `walks`: the stance owns the walk-up in this step (the walker's destination is re-derived from the touch distance, ContactSettle.swift), even while the settle only separates (phase 0: the drive's own walk-up
    /// used to stop 60 cm short of the touch and the next phases patched it with hurried shuffles).
    struct Step: Sendable { var from: Int; var target: Float?; var onlySeparate = false; var walks: Bool? = nil
        var retargets: Bool { walks ?? !onlySeparate } }
    /// How the pair stands once the stance is on (what the drive squares up to): face to face, or both facing the camera (side by side). The walk-up predicts the touch distance for THAT posture.
    enum Facing: Sendable { case each, camera }
    var facing: Facing = .each
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
    /// Where a walk ends relative to the touch (the lean closes the rest, <= the lean budget).
    static let arrive: Float = 0.015
    /// Where a pressing stance stands before the press (skin gap): the walk's last step lands here, the press closes the last centimetre with the lean (budget 3.4 cm), no shuffle. Within the 1.5 cm arrival bar.
    static let ready: Float = 0.012
    /// A stance walk aims this much SHORT of the touch (total; a meeting pair shares it): a walk's last step lands up to ~6 cm off its target (measured overshoots: 7 - 15 cm for two walkers) (planWalkStep's arrival radius) and a walker cannot step backward without turning round,
    /// so a short stop is closed by a forward shuffle / the lean, an overshoot is not.
    static let walkShort: Float = 0.0
    /// Proximity: stay at least this far (above the 0.5 cm sound window, so a near miss never squishes).
    static let near: Float = 0.012

    /// Touching for the whole hold from phase `from`.
    static func holding(from: Int, facing: Facing = .each, walk0: Bool = true, until: Int? = nil, anchor: Anchor = .none, features: Bool = true, sound: SFX? = nil, volume: Float = 0.25, haptic: ContactHaptic = .none, pulses: [(phase: Int, from: Float, to: Float)] = []) -> ContactStance {
        var st = [Step(from: 0, target: near, onlySeparate: true, walks: walk0), Step(from: from, target: hold)]
        if let u = until { st.append(Step(from: u, target: near, onlySeparate: true)) }
        return ContactStance(facing: facing, cls: .touching, steps: st, anchor: anchor, features: features, sound: sound, volume: volume, haptic: haptic, pulses: pulses)
    }
    /// Approach (stand `approach` apart) from `from`, press from `press`, off from `until`.
    static func pressing(from: Int, press: Int, walk0: Bool = true, facing: Facing = .each, until: Int? = nil, anchor: Anchor = .none, features: Bool = true, sound: SFX? = nil, volume: Float = 0.25, haptic: ContactHaptic = .none) -> ContactStance {
        var st = [Step(from: 0, target: walk0 ? ready : near, onlySeparate: true, walks: walk0), Step(from: from, target: ready), Step(from: press, target: hold)]
        if let u = until { st.append(Step(from: u, target: near, onlySeparate: true)) }
        return ContactStance(facing: facing, cls: .touching, steps: st, anchor: anchor, features: features, sound: sound, volume: volume, haptic: haptic)
    }
    /// Never overlap (and never squish): gap >= `near` from phase `from`.
    static func proximity(from: Int = 0, features: Bool = true) -> ContactStance {
        ContactStance(cls: .proximity, steps: [Step(from: from, target: near, onlySeparate: true)], features: features)
    }

    // MARK: the table
    static let table: [SocialKind: ContactStance] = [
        // press / bump kinds: stand a few cm apart, touch when the move presses
        // boop (user rule 2): side by side at HAND REACH. The booper's arm is up (in its canonical pose) from the first step, so the outline the walk-up measures is hand to the partner's arm and the last steps land the HAND there; the press closes the last cm. The bodies (eggs) never touch: the hand is the contact.
        .boop: ContactStance(facing: .camera, cls: .touching, steps: [Step(from: 0, target: HandReach.stand, onlySeparate: true, walks: true), Step(from: 1, target: HandReach.stand, onlySeparate: true), Step(from: 2, target: hold)], anchor: .b, sound: .squish, volume: 0.5),
        .squabble: .pressing(from: 1, press: 1, walk0: true, until: 2, sound: .squish, volume: 0.5),
        .bump: .pressing(from: 1, press: 2, until: 4, sound: .boop, volume: 0.9),          // (phase 4 = the happy bounces AFTER the bump: the pair may part and hop)
        .sneak: .pressing(from: 1, press: 2, until: 3, anchor: .b, features: true, sound: .boop, volume: 0.9),
        .chestBump: .pressing(from: 1, press: 2, until: 3, sound: .squish, volume: 0.9),
        // high five (user rule 2): side by side, both arms are up from the first step (canonical pose) so the walk lands the hands together and the hands meet tip to tip (hand to hand, ready), the hold squeezes them to the press; phase 3: the arms go down, they part.
        .highFive: ContactStance(facing: .camera, cls: .touching, steps: [Step(from: 0, target: HandReach.stand, onlySeparate: true, walks: true), Step(from: 1, target: HandReach.stand, onlySeparate: true), Step(from: 2, target: hold), Step(from: 3, target: near, onlySeparate: true)], anchor: .b, sound: .highFiveBoop, volume: 0.85, haptic: .emote("highFive.bump")),
        .tag: .pressing(from: 1, press: 2, walk0: false, until: 3, sound: .boop, volume: 0.9),
        .bellyBounce: .pressing(from: 1, press: 2, facing: .camera, until: 3, sound: .squish, volume: 0.9),
        .chase: .pressing(from: 2, press: 2, walk0: false, until: 3, sound: .boop, volume: 0.9),
        // holds
        .nuzzle: .holding(from: 2, facing: .camera),
        .sitTogether: ContactStance(facing: .camera, cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true), Step(from: 2, target: hold)], features: true),
        .bagSit: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true)], features: true),          // (the second Jelbie sits on the floor beside a seated one / on a second piece: never inside, never moving a seated body)
        .cuddle: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true)], features: true),          // (loveseat: the two seats are the decor's; the table only keeps them apart)
        .cheekSquish: .holding(from: 1, facing: .camera, sound: .squish, volume: 0.7),          // (one continuous press: the second squish is a lean + squash, not a back-off and a second touch)
        .backToBack: .holding(from: 3, facing: .camera, features: true),
        .cuddleLean: .holding(from: 2, facing: .camera, sound: .squish, volume: 0.5),
        .swayHug: .holding(from: 2, facing: .camera, sound: .squish, volume: 0.55),
        .whisperGiggle: .holding(from: 1, facing: .camera),
        .ringAround: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true), Step(from: 1, target: hold), Step(from: 2, target: near, onlySeparate: true)], features: true),          // (nose to nose in the greeting; the hop ring is a proximity move: the hops turn the bodies side on, so the ring is wider than the touch)
        .spinHug: ContactStance(cls: .touching, steps: [Step(from: 0, target: near, onlySeparate: true), Step(from: 2, target: hold), Step(from: 3, target: near, onlySeparate: true)], features: true, sound: .emoteSpinHug, volume: 1, haptic: .treat("spinHug.press")),
        // groups
        .groupHug: .holding(from: 2, walk0: false, features: true, sound: .squish, volume: 0.7, pulses: [(2, 1.9, 2.4)]),
        .circleDance: .holding(from: 2, walk0: false, features: true),
        // proximity
        .twirl: .proximity(from: 1), .hopAlong: .proximity(from: 1), .littleRace: .proximity(), .leapfrog: .proximity(features: true),
        .peekaboo: .proximity(features: true), .mirrorDance: .proximity(from: 1), .danceOff: .proximity(from: 1), .shyWave: .proximity(from: 3),
        .groupCheer: .proximity(from: 1), .conga: .proximity(), .congaLine: .proximity(features: true), .ringDance: .proximity(features: true),
        .follow: .proximity(), .line: .proximity(), .dance: .proximity(from: 1), .greet: .proximity(), .keepAway: .proximity(),
        // (explicit rows for the rest: a new interactive SocialKind with no row fails ContactTableTests.testEveryKindHasAnExplicitRowAndIsMeasured)
        // (explicit since 2026-11-04, user rule 3: EVERY kind has a row - a new emote without one fails ContactSettleTests.testEveryInteractiveKindHasAStanceRow)
        .look: .proximity(), .zoomies: .proximity(), .pass: .proximity(),
    ]
    static func entry(_ k: SocialKind) -> ContactStance? { table[k] }
}

extension BlobBrain {
    /// The stance of the session `self` and `o` are both in (nil = not in the same session, or none for the kind).
    func contactStance(with o: BlobBrain) -> ContactStance? {
        guard let s = social, o.social === s, s.end == nil, let st = ContactStance.entry(s.kind), st.cls != .none else { return nil }
        return st
    }

    /// The steerIDs of the bodies `self` is in a stance session with (touching-class stances only; and, for 1.5 s after it, the ones it just left: the spring must not snap back on a pair standing at the touch). Used by the room's
    /// peer wall (`MelonStage.keepApart`): for these the skin wall replaces the circle spring.
    func contactPartnerIDs() -> Set<Int> {
        var r = Set<Int>()
        if let s = social, s.end == nil, let st = ContactStance.entry(s.kind), st.cls == .touching { for id in (s.kind.isGroup ? s.crewIDs : [s.idA, s.idB, s.idC]) where id >= 0 && id != steerID { r.insert(id) } }
        for id in socialBook.glow.keys { r.insert(id) }
        if stanceStepFree { for id in r where id >= 0 { r.insert(-(id + 1)) } }          // (the final step of a stance walk: MelonStage.keepApart skips these partners for this one call)
        return r
    }

    /// Called from `socialDrive` by the session's initiator, every step: hold the pair(s) of the session at the skin gap the stance table asks for in the current phase.
    func contactStanceTick(_ s: SocialSession) {
        ContactTouchMemory.begin(s)
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
            return x.held || x.idleState.kind == .sleep || x.idleState.kind == .decorSit || (st.anchor == role && st.anchor != .none)
        }
        guard let s = a.social else { return }
        a.contactStanceWalk(partner: b, gapWanted: target, features: st.features, retarget: step.retargets); b.contactStanceWalk(partner: a, gapWanted: target, features: st.features, retarget: step.retargets)
        let aa = fixed(a, s.a === a ? .a : .b), bb = fixed(b, s.a === b ? .a : .b)
        ContactSettle.step(a, b, target: target, anchoredA: aa, anchoredB: bb, onlySeparate: step.onlySeparate, features: st.features, urgent: ContactSettleTuning.stanceUrgent, support: true)
    }
}

extension BlobBrain {
    /// The touch distance for the posture the pair will STAND in (`ContactStance.facing`), not the one they have now: the profiles are the bodies' current outlines, so a body that is still to turn is rotated
    /// first (the extent after turning by d is the extent before along the direction turned back by d). Side-on the pair touches at ~1.4 m, face to face at ~0.75 m: a destination from the current outline stops
    /// the walker 60 cm short, or a pair that has to turn after arriving sweeps its wide axis through the partner.
    func touchRadiusFacing(_ o: BlobBrain, along u: SIMD2<Float>, _ f: ContactStance.Facing) -> Float? {
        let mine: Float, his: Float
        switch f {
        case .each: mine = atan2f(-u.x, -u.y); his = atan2f(u.x, u.y)
        case .camera: mine = faceCameraYaw(); his = o.faceCameraYaw()
        }
        let d1 = wrapAngle(mine - yaw), d2 = wrapAngle(his - o.yaw)
        guard let ea = ContactField.supportExt(steerID, rotXZ(-u, -d1)), let eb = ContactField.supportExt(o.steerID, rotXZ(u, -d2)) else { return nil }
        return ea + eb
    }

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

extension BlobBrain {
    /// The heart / shove event of a touching emote. With profiles `contactTick` posts it at the real touch; this is the old drive-timer path for rigs with no profile.
    func contactBoopFallback(_ o: BlobBrain, shove: Bool = false) {
        guard !ContactField.enabled || ContactField.gap(steerID, o.steerID) == nil else { return }
        if shove { onSocial?(.shove(partner: o.steerID)); o.onSocial?(.shove(partner: steerID)) }
        else { onSocial?(.boop(partner: o.steerID)); o.onSocial?(.boop(partner: steerID)) }
    }
}

extension BlobBrain {
    /// The widest root distance at which my skin and `o`'s touch over the compass (x and z, both ways): a body turns on the spot, so a ring / line planned on this never ends up inside a neighbour. + the approach margin.
    /// Without profiles (the first tick): 1.445.
    func ringTouch(_ o: BlobBrain) -> Float {
        var w: Float = 0, ok = false
        for u in [SIMD2<Float>(1, 0), SIMD2(-1, 0), SIMD2(0, 1), SIMD2(0, -1)] { if let t = touchRadius(o, along: u) { w = max(w, t); ok = true } }
        return ok ? w + ContactStance.approach : 1.445
    }
    /// The chord / follow distance for a crew: `extra` more than the widest touch of any two of them (0 = packed, touching).
    func ringChord(_ crew: [BlobBrain], extra: Float = 0) -> Float {
        var w: Float = 0
        for i in crew.indices { for j in (i + 1)..<crew.count where j < crew.count { w = max(w, crew[i].ringTouch(crew[j])) } }
        return (w > 0 ? w : 1.445) + extra
    }
}

extension BlobBrain {
    /// The sleep pile: two sleepers that lie side by side are kept touching (gap 0, the wings / tail counted), the one that fell asleep first stays. Called every tick by the one that has the lower id.
    func sleepPileTick() {
        guard ContactField.enabled, idleState.kind == .sleep, social == nil else { return }
        for o in socialOthers() where o !== self && !o.isNapping && !o.held && o.social == nil && o.idleState.kind != .sleep {          // (a neighbour who is up: the sleeper does not move, the neighbour is kept off)
            ContactSettle.step(self, o, target: ContactStance.near, anchoredA: true, onlySeparate: true, features: true, urgent: ContactSettleTuning.stanceUrgent, support: true)
        }
        for o in socialOthers() where o !== self && isNapping && o.isNapping && steerID < o.steerID {
            let older = o.idleState.t > idleState.t + 0.05 || (abs(o.idleState.t - idleState.t) <= 0.05 && o.steerID < steerID)
            guard let g = ContactField.gap(steerID, o.steerID, features: true), g < 0.7 else { continue }
            ContactSettle.step(self, o, target: ContactStance.hold, anchoredA: !older, anchoredB: older, features: true, urgent: ContactSettleTuning.stanceUrgent, support: true)
        }
    }
}
