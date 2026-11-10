//
//  GameCare+Play.swift
//  Play mode's glue: when Play may start, the actors handed to the controller, the room's world for the ball (walls, furniture), the ball's mesh in the room
//  renderer, and what the player feels (haptics, sounds) for each PlayEvent. The camera is GameCamera.playBlend (eased by the controller).
//

import Foundation
import UIKit
import simd

extension GameCare {
    /// Play may start: roaming in the room, nothing else going on, and somebody awake to play with.
    var canPlay: Bool {
        focus.phase == .roaming && !bath.active && (!tripActive || parkPlayOpen) && !raceBusy && !trayOut && !cafe.active && !arranging && (!park.inScene || parkPlayOpen) && !volley.inScene && !groom.inScene
            && !guestBook.present && !nightSkip.active && !play.active && !playJellies().isEmpty
    }
    /// The park is up and playing: the ball and the bubble wand work there too (never while it fades in or out; the other trips still block Play).
    var parkPlayOpen: Bool { park.phase == .playing }
    /// Why Play is not available (VoiceOver), nil = it is.
    var playBlocker: String? {
        if play.active { return "Already playing" }
        if focus.isActive { return "Not in the close-up" }
        if bath.active { return "Not while cleaning" }
        if trayOut { return "Food is already out" }
        if (tripActive && !parkPlayOpen) || raceBusy || cafe.active { return "Not while away" }
        if guestBook.present { return "Not while a friend is over" }
        if playJellies().isEmpty { return "Everybody is asleep" }
        return nil
    }

    /// The awake Jelbies in the room, as the controller sees them.
    func playJellies() -> [PlayJelly] {
        let own: [PlayJelly] = playActors.compactMap { a in
            guard let b = a.brain, !parkHides(a.id), !b.isSleeping, !b.isNapping else { return nil }
            return PlayJelly(id: a.id, brain: b, sim: a.sim, skinner: a.skinner)
        }
        guard park.inScene else { return own }
        // the park's visitors head and kick the ball back too, but keep roaming (they are not set on the play line)
        return own + parkBook.actors.compactMap { a in
            guard let b = a.brain, !b.isSleeping, !b.isNapping else { return nil }
            return PlayJelly(id: a.id, brain: b, sim: a.sim, skinner: a.skinner, free: true)
        }
    }

    /// The ball's back wall: the room's, or the park's roam rect (GameCamera.configurePark).
    private func applyPlayWorld() { TossTuning.zBack = park.inScene ? GameCamera.roamRect.min.y : -2.4; TossTuning.zFront = park.inScene ? 4.95 : 9 }

    /// A toy was picked: Play mode on with that ball.
    func beginPlay(ball kind: DecorKind) {
        guard canPlay else { AudioHub.shared.play(.notEnough); return }
        select.cancel()
        clearHighlight()
        applyPlayWorld()
        play.onEvent = { [weak self] e in self?.playFeedback(e) }
        play.begin(ball: kind, title: kind.title, jellies: playJellies())
        AudioHub.shared.play(.uiconfirm)
    }

    /// The bubble wand was picked (Toys/BubbleWand.swift): Play mode on with the wand's controls, the Jelbies free to watch and chase the bubbles.
    func beginPlay(wand: BubbleWand) {
        guard canPlay else { AudioHub.shared.play(.notEnough); return }
        select.cancel()
        clearHighlight()
        play.onEvent = nil
        applyPlayWorld()
        play.beginToy(title: wand.title)
        wand.begin(care: self)
        AudioHub.shared.play(.uiconfirm)
    }

    func endPlay() {
        play.end()
        play.onEvent = nil
        TossTuning.zBack = -2.4; TossTuning.zFront = 9
        BubbleWand.shared.deactivate()          // (no-op unless the wand was out)
    }

    /// Once per fixed step (after the Jellies and the decor): the ball's physics, the Jelbies' parts in the game.
    func tickPlay(_ actors: [JellyActor], dt: Float) {
        playActors = actors
        guard play.active || play.camBlend > 0 || GameCamera.playBlend != 0 else { return }
        if play.active, focus.isActive || bath.active || (tripActive && !parkPlayOpen) || (park.active && !parkPlayOpen) || guestBook.present { endPlay() }          // (Go home / the bedtime call ends the park's play first)
        play.tick(dt: dt, world: tossWorld(), jellies: play.active ? playJellies() : [])
        if play.active, UserDefaults.standard.integer(forKey: "PlayDemo") > 0, Int(play.clock * 60) % 15 == 0 {
            let b = play.ball
            NSLog("[playtoss] t=%.2f %@ ball (%.2f %.2f %.2f) v (%.1f %.1f %.1f) jellies %@", play.clock, String(describing: play.phase), b.pos.x, b.pos.y, b.pos.z, b.vel.x, b.vel.y, b.vel.z,
                  play.jellies.map { String(format: "%d:(%.1f,%.1f)%@", $0.id, $0.pos.x, $0.pos.y, $0.brain.tossBusy ? "*" : "") }.joined(separator: " "))
        }
    }

    /// The room as the ball sees it: the visible floor's sides, the furniture and the sofa under their tops.
    func tossWorld() -> TossWorld {
        var w = TossWorld()
        w.xHalf = { DecorPlacement.visibleHalf(z: $0) + 0.3 }
        let solids = DecorField.shared.feet.filter { $0.spec.solid && $0.kind != .minigoal }
        let cyl = RoomLayout.cylinders
        w.solid = { p in
            var d = RoomLayout.sofaDistanceXZ(p)
            for f in solids { d = min(d, f.distance(p)) }
            for c in cyl { d = min(d, simd_distance(p, c.centre) - c.radius) }
            return d
        }
        return w
    }

    // MARK: feel

    func playFeedback(_ e: PlayEvent) {
        if UserDefaults.standard.integer(forKey: "PlayDemo") > 0 { NSLog("[playtoss] %@", String(describing: e)) }
        let hub = AudioHub.shared
        func buzz(_ style: UIImpactFeedbackGenerator.FeedbackStyle, _ i: CGFloat) { Haptic.impact(style, intensity: i) }
        switch e {
        case .release(let s):
            buzz(.soft, min(0.9, 0.35 + CGFloat(s) * 0.04)); hub.play(.tick, volume: 0.6, rate: 1.1)
        case .floorBounce(let s):
            if s > 1.4 { hub.play(.boop, volume: min(0.45, 0.12 + s * 0.04), rate: 1.5) }
        case .header(let id, _):
            buzz(.soft, 0.75); hub.play(.highFiveBoop, jelly: id, volume: 0.8)
        case .bodyBoop(let id):
            buzz(.light, 0.4); hub.play(.boop, jelly: id, volume: 0.4, rate: 1.2)
        case .kick(let id):
            buzz(.light, 0.5); hub.play(.boop, jelly: id, volume: 0.5, rate: 1.3)
        case .pass:
            hub.play(.sparkle, volume: 0.35)
        case .whiff, .rescue: break
        case .caught(let rally):
            buzz(.soft, 1.0); hub.play(.squish, volume: 0.6, rate: 0.8)
            if rally >= 1 { hub.play(.cheerSmall, volume: 0.35) }
        }
    }

    // MARK: drawing

    /// The ball and its shadow (never in the bubble wand's toy phase: no ball there, whatever ball was thrown last), drawn with the room's animating decor. True = this frame's active decor mesh was set here.
    func refreshTossBall(_ room: RoomRenderer, active: Set<Int>, time: Float) -> Bool {
        let p = play
        guard p.ballGame, p.camBlend > 0.02 || p.phase != .inHand else {
            if playShown { playShown = false; room.setDecorActive(RoomMesh()); decorDrawn.activeShown = false }
            return false
        }
        let f = DecorField.shared
        let b = RoomMeshBuilder(); b.material = .plain
        func add(_ m: RoomMesh) { let off = UInt32(b.mesh.vertices.count); b.mesh.vertices.append(contentsOf: m.vertices); b.mesh.indices.append(contentsOf: m.indices.map { $0 + off }) }
        if !active.isEmpty { add(DecorModels.build(feet: f.feet.filter { active.contains($0.uid) }, field: f, time: time)) }
        let ball = p.ball
        let h = max(ball.pos.y - ball.radius, 0)
        // a soft dark disc under it: smaller and fainter the higher it is
        let k = min(1, h / 3)
        let col = SIMD3<Float>(repeating: 0.55 + 0.25 * k) * SIMD3(0.9, 0.8, 0.7)
        if p.phase == .flying || p.phase == .loose { ParkScenery.disc(b, cx: ball.pos.x, cz: ball.pos.z, radius: ball.radius * (1.25 - 0.35 * k), y: 0.021, color: col) }
        // the landing marker: a soft ring + dot at the predicted touch-down, closing in and brightening as the ball comes down (gone once it is down)
        if p.phase == .flying || (p.phase == .loose && h > 0.15), h > 0.12, let l = ball.landing(xHalf: { DecorPlacement.visibleHalf(z: $0) }), l.t < 3 {
            let prog = 1 - min(1, l.t / 1.6)                               // 0 = far, 1 = about to land
            let r = ball.radius * (2.1 - 0.9 * prog)
            let glow = SIMD3<Float>(0.70 + 0.30 * prog, 0.76 + 0.24 * prog, 0.86 + 0.14 * prog)
            let haloC = SIMD3<Float>(repeating: 0.50 + 0.14 * prog) * SIMD3(0.9, 0.85, 0.8)
            ParkScenery.disc(b, cx: l.xz.x, cz: l.xz.y, radius: r * 1.15, y: 0.024, color: haloC)
            VolleyBallMesh.annulus(b, cx: l.xz.x, cz: l.xz.y, r0: r * 0.80, r1: r * 1.0, y: 0.03, color: glow)
        }
        var a = DecorAnim(); a.rot = ball.rot; a.pos = SIMD2(ball.pos.x, ball.pos.z)
        let m = RoomMeshBuilder(); m.material = .plain
        DecorModels.add(p.ballKind, at: SIMD2(ball.pos.x, ball.pos.z), lift: h, anim: a, time: time, uid: 0, into: m)
        add(m.mesh)
        room.setDecorActive(b.mesh)
        decorDrawn.activeShown = true
        playShown = true
        return true
    }
}
