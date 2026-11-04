//
//  BlobBrain+Relay.swift
//  The relay's three body states, all made of existing moves (no new gait):
//    waiting / finished   `relayStand`: still on the track (race.active, so the room's rules stay off him) with NO script, so his body settles and sleeps
//                         (JellyActor.brainIsStill) and costs nothing until he is called.
//    running              `relayGo`: the race script again; the race model's committed steps move him exactly as in a solo race.
//    bounce / cheer       `relayHop`: the roaming hop (script .hopPlay, the same squash, tuck and landing) in place, minus the room-floor clamp of startHop.
//

import Foundation
import simd

extension BlobBrain {
    /// He stands on the track doing nothing (waiting at a handoff box, or done): the race script off, the race still his.
    func relayStand() {
        guard race.active else { return }
        if race.jumping { race.jumping = false; gait.hopApex = 0.10; gait.hopDuration = 0.26 }
        race.pendingFoot = nil; race.stumbleT = 0
        script = .none; activity = .idle
        restTimer = 1000
    }

    /// He is called: the race script takes him (from where he stands) and the next committed step moves him.
    func relayGo(sim: SoftBody) {
        guard race.active else { return }
        if case .hopPlay = script { return }          // (a bounce in the air finishes first: the keep-alive picks the race script up after it)
        script = .race; activity = .walking
        restTimer = 1.0
    }

    /// He is standing (no script, idle) and can bounce.
    var relayCanHop: Bool { race.active && scriptIsNone && idleState.kind == nil && !commanded }

    /// A small hop in place (the bounce while he waits, the cheer when he is done).
    func relayHop(_ sim: SoftBody) {
        guard relayCanHop else { return }
        AudioHub.shared.play(.jump, jelly: steerID, x: px, volume: 0.6)
        sim.targets = []; beanHold = 0; feetInit = false; feet.reset(); stepLive = false
        gait.wander = false
        gait.facingYaw = yaw
        gait.home = SIMD2(px, pz)
        gait.hopApex = 0.10; gait.hopDuration = 0.26
        poseW = 0
        gait.hop(sim, to: SIMD2(px, pz) + SIMD2(sinf(yaw), cosf(yaw)) * 0.0001, reduceMotion: amplitude < 0.7)
        script = .hopPlay; activity = .playing
    }
}
