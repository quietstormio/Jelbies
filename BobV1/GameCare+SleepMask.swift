//
//  GameCare+SleepMask.swift
//  Feeds the sleep eye masks (Room/SleepMask.swift): ticks them with every Jelly's brain and body, hands the meshes to the room renderer.
//

import Foundation

extension GameCare {
    /// Once per fixed step, after every Jelly has been ticked.
    func tickMasks(_ actors: [JellyActor], dt: Float) {
        for a in actors {
            guard let b = a.brain else { continue }
            sleepMasks.tick(id: a.id, brain: b, sim: a.sim, raceBusy: race.active, dt: dt)
        }
        sleepMasks.stepPuffs(dt: dt)
    }

    /// After the frame's last sim step: the masks (carried by the bodies' poses now) and puffs go to the room. Nothing is drawn on the track or in the bath.
    func refreshMasks(renderer: MelonRenderer?) {
        guard let room = renderer?.room else { return }
        let active = sleepMasks.isActive
        guard active || masksDrawn else { return }
        let f = sleepMasks.frame(theme: room.theme, hidden: room.raceVisible || room.bathVisible)
        room.setMasks(opaque: f.opaque, translucent: f.translucent)
        masksDrawn = active
    }
}
