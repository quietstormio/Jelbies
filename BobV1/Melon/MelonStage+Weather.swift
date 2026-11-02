//
//  MelonStage+Weather.swift
//  The stage's side of the weather (Melon/Weather.swift, BlobBrain+Weather.swift): the storm clock ticks with the room's fixed step while the living room is on screen,
//  its events go to the Jelbies' reactions and the sound, and each frame the window shader gets the storm's look and the whole frame its exposure.
//

import Foundation
import QuartzCore

extension MelonController {
    /// The living room (with its windows) is what the player sees: not the track, the stage, the park, the bath, the species picker or a menu pause.
    var weatherRoomShown: Bool {
        guard game, !model.paused, !model.cutout else { return false }
        let c = model.care
        return !c.race.trackVisible && !c.show.onStage && !c.park.inScene && !c.volley.inScene && !c.groom.inScene && !c.bath.look.visible && c.bath.cameraBlend <= 0.001
    }

    /// Once per fixed sim step (after Ears): the weather clock, the storm's events to the sound and the Jelbies, the Jelbies' storm reactions.
    func stormTick(reduce: Bool) {
        guard game else { return }
        let book = WeatherBook.shared, reactor = StormReactor.shared
        let shown = weatherRoomShown
        guard book.isStorming || shown else { return }
        let dt = Double(actors[0].sim.stepDt)
        let events = book.tick(dt: dt, active: shown, reduce: reduce)
        guard book.isStorming || !events.isEmpty || reactor.stormOn else { return }
        reactor.update(care: model.care)
        reactor.onFirstShake = { [weak self] in
            guard let self else { return }
            let c = self.model.care
            StormHaptics.shared.request(.softTick, now: CACurrentMediaTime(), blocked: c.race.active || c.volley.active || c.volley.inScene || c.bath.active || c.tripActive, driver: c.touchPlay?.haptics)
        }
        let js = reactor.refresh(actors: actors)
        if !events.isEmpty {
            let c = model.care
            let blocked = c.race.active || c.volley.active || c.volley.inScene || c.bath.active || c.tripActive
            let now = CACurrentMediaTime(), driver = c.touchPlay?.haptics
            for e in events { if let h = StormHaptics.haptic(for: e, plan: book.plan) { StormHaptics.shared.request(h, now: now, blocked: blocked, driver: driver) } }
            AudioHub.shared.storm(events, plan: book.plan)
            reactor.handle(events, plan: book.plan, jellies: js, care: model.care)
        }
        reactor.tick(jellies: js, care: model.care, dt: Float(dt))
        AudioHub.shared.stormBed(rain: shown ? book.look(reduce: reduce).rain : 0)
    }

    /// The storm the window shader and the post exposure use this frame (clear everywhere but the living room).
    func weatherFrame(reduce: Bool) -> (look: WeatherLook, exposure: Float) {
        guard weatherRoomShown else { return (WeatherLook(), 1) }
        let look = WeatherBook.shared.look(reduce: reduce)
        return (look, look.isClear ? 1 : look.exposure(night: DayClock.shared.nightFactor))
    }
}
