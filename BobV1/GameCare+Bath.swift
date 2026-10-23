//
//  GameCare+Bath.swift
//  "Clean" for whichever Jelly the care menu targets. Bob's run is the original one (GameCare.tick drives BathFlow with his brain); another
//  Jelly's run borrows the same BathFlow: the flow takes his grime and look for the run, `tickOthers` ticks it with HIS brain and body, and
//  the stage routes the touches to his body and draws the bathroom around him (renderer.bathBody).
//

import Foundation
import simd

/// What GameCare keeps for the other Jellies' clean-ups: the actors seen by `tickOthers` (to find a brain and a body) and the wetness a
/// washed Jelly leaves the tub with (it dries off over a few seconds, like Bob's).
@MainActor
final class BathPlug {
    struct Ref { weak var actor: JellyActor? }
    var actors: [Int: Ref] = [:]
    var wet: [Int: Float] = [:]
    nonisolated deinit {}
    /// Test hook / stage hook: tell GameCare which actor is Jelly `a.id` (tickOthers does it every step).
    func register(_ a: JellyActor) { actors[a.id] = Ref(actor: a) }
}

extension GameCare {
    /// Menu row "Clean" is available for this Jelly: no tray, no clean-up running, not in the come-here close-up, and a body to wash.
    func canClean(jelly id: Int) -> Bool {
        guard !trayOut, !bath.active, !tripActive, !focus.isActive else { return false }
        if id == 0 { return true }
        return bathPlug.actors[id]?.actor?.brain != nil
    }

    /// "Clean" on Jelly `id` (> 0; Bob's is `clean(jelly: 0)`): he runs out toward the camera, then soap, rinse, shine, sparkle, and back to where he was.
    func startCleanOther(jelly id: Int) {
        guard id != 0, canClean(jelly: id) else { return }
        guard let a = bathPlug.actors[id]?.actor, let brain = a.brain, let profile = jelly(id) else { return }
        select.cancel()
        profile.refreshLook(force: true)
        bathPlug.wet[id] = nil
        bath.onTargetEnd = { [weak self] who, wet in
            guard let self else { return }
            self.jelly(who)?.refreshLook(force: true)
            if wet > 0.001 { self.bathPlug.wet[who] = wet }
        }
        bath.returnSpot = Self.washReturnSpot(brain: brain, id: id, from: GameCare.floorPos(brain, a.sim))
        bath.start(brain: brain, jelly: id, grime: profile.grime, look: profile.look)
    }

    /// The Next button: the player moves to the next clean-up stage once the current one is complete (soap, rinse, shine).
    func nextCleanStep() { bath.advance() }

    /// The ✕ button (the Jelly being washed; `jelly` is accepted for symmetry with `clean(jelly:)`).
    func cancelClean(jelly id: Int? = nil) {
        guard let (brain, sim) = washer(id) else { return }
        bath.cancel(brain: brain, sim: sim)
    }
    func finishClean(jelly id: Int? = nil) {
        guard let (brain, sim) = washer(id) else { return }
        let shined = bath.phase == .finish
        bath.done(brain: brain, sim: sim)
        if shined { brain.postEvent(.shined); brain.blushBump(hold: 2.8, peak: 0.6); brain.wantJoy() }          // the others admire the shine
    }
    /// The brain and body of the clean-up that is running (must be `id` when one is given).
    private func washer(_ id: Int?) -> (BlobBrain, SoftBody?)? {
        let t = bath.targetID
        if let id, id != t { return nil }
        if t == 0 { return lastBrain.map { ($0, lastSim) } }
        guard let a = bathPlug.actors[t]?.actor, let b = a.brain else { return nil }
        return (b, a.sim)
    }

    /// Fixed step of the Jelly being washed (called from `tickOthers`); returns true while his profile must not run (the flow owns his dirt).
    func tickBathOther(_ a: JellyActor, brain: BlobBrain, profile: JellyProfile, dt: Float) -> Bool {
        bathPlug.register(a)
        if let w = bathPlug.wet[a.id] {
            let n = max(0, w - dt / BathTuning.wetFade)
            bathPlug.wet[a.id] = n > 0 ? n : nil
        }
        guard bath.targetID == a.id else { return false }
        if bath.active {
            bath.returnSpot = Self.washReturnSpot(brain: brain, id: a.id, from: bath.returnSpot ?? GameCamera.callSpot)
            bath.tick(brain: brain, sim: a.sim, play: touchPlay, dt: dt)
        }
        return true
    }

    /// Where a washed Jelly goes back to: his old spot, or (when somebody stands there now) the usual greeting spot, else a free place in front.
    static func washReturnSpot(brain: BlobBrain, id: Int, from saved: SIMD2<Float>) -> SIMD2<Float> {
        let others = brain.peers().map(\.pos)
        func free(_ p: SIMD2<Float>) -> Bool { !others.contains { simd_distance($0, p) < 1.2 } }
        if free(saved) { return saved }
        for c in [greetSpot(id), SIMD2(-1.6, 1.4), SIMD2(1.6, 1.4), SIMD2(0, 0.6)] where free(c) { return c }
        return greetSpot(id)
    }

    /// The look the renderer draws on Jelly `id` this frame: the washed Jelly's working look, Bob's own while another Jelly is washed,
    /// else the profile's room look. `sootStyle` = id puts each Jelly's streaks in his own places (Bob's spots stay exactly the original).
    func renderLook(for id: Int) -> BathLook {
        var l: BathLook
        if id == bath.targetID { l = bath.look }
        else if id == 0 { l = bath.savedBobLook ?? bath.look }
        else { l = jelly(id)?.look ?? .dry; if let w = bathPlug.wet[id] { l.wet = w } }
        l.sootStyle = Float(id)
        return l
    }
}
