//
//  BlobBrain+HopSound.swift
//  The generic hop sound + haptic (2026-11-06, "why no noises when they jump"): every Jelbie, wherever he is (home, park, groomer exit, race), gets a take-off .jump and a soft
//  landing thump from how high his SOLES are above the floor - not from the ~10 call sites that happened to ask for one. Hub-side dedupe: a take-off whose Jelbie asked for
//  an explicit .jump in the last 0.35 s stays silent (AudioHub.hopTakeoff). The per-sound minGap, mute and duck are the hub's own.
//

import Foundation
import simd

struct HopAirState {
    var airborne = false
    var airT: Float = 0
    var prevH: Float = 0
    var peakFall: Float = 0           // fastest descent (m/s) since the apex
    var peakH: Float = 0
}

nonisolated enum HopSoundTuning {
    static var enabled = true
    static let takeoffHeight: Float = 0.025         // both feet at least 2.5 cm off the floor = a real hop (not a walk bob or a squash)
    static let landHeight: Float = 0.008            // hysteresis: back under 8 mm = landed
    static let minAir: Float = 0.12                 // a landing only sounds after this long in the air
}

extension BlobBrain {
    /// Called at the end of every tick (any path). `tap` seams for the soak: events as (jelly, kind, height / speed).
    nonisolated(unsafe) static var hopEventTap: ((Int, String, Float) -> Void)?

    func hopSoundTick(_ sim: SoftBody, _ skinner: Skinner, _ dt: Float) {
        guard HopSoundTuning.enabled, dt > 0 else { return }
        // no sound or haptic while asleep / napping, carried, thrown, tumbling or touched; volleyball has its own hop sounds
        if isSleeping || activity == .touched || activity == .recovering || volley.active {
            hopAir = HopAirState(); return
        }
        // the soles' height above the floor: the higher of the two feet's lowest points (both feet off the floor)
        var h: Float = .infinity
        for s in 0..<2 {
            guard !skinner.beanPos[s].isEmpty else { h = 0; break }
            var lo = Float.infinity; for p in skinner.beanPos[s] { lo = min(lo, p.y) }
            h = min(h, lo - sim.floorY)
        }
        if !h.isFinite { h = 0 }
        h = max(0, h)
        let vy = (h - hopAir.prevH) / dt
        defer { hopAir.prevH = h }
        if !hopAir.airborne {
            if h > HopSoundTuning.takeoffHeight {
                hopAir.airborne = true; hopAir.airT = 0; hopAir.peakFall = 0; hopAir.peakH = h
                let hub = AudioHub.shared
                // volume 0.45 ... 0.9 by the push-off speed (a 1 m/s hop is small, 2.5 m/s+ a big one); rate +-6 %
                let v = min(1, max(0, (vy - 0.8) / 1.7))
                let vol = 0.45 + 0.45 * v
                Self.hopEventTap?(steerID, "takeoff", h)
                hub.hopTakeoff(jelly: steerID, x: px, volume: vol, rate: 1 + Float.random(in: -0.06...0.06))
            }
            return
        }
        hopAir.airT += dt; hopAir.peakH = max(hopAir.peakH, h)
        if vy < 0 { hopAir.peakFall = max(hopAir.peakFall, -vy) }
        if h < HopSoundTuning.landHeight {
            let long = hopAir.airT >= HopSoundTuning.minAir
            let fall = hopAir.peakFall
            hopAir = HopAirState(); hopAir.prevH = h
            guard long else { return }
            Self.hopEventTap?(steerID, "land", fall)
            let f = min(1, fall / 2.5)
            AudioHub.shared.hopLanding(jelly: steerID, x: px, volume: 0.25 + 0.3 * f, rate: 0.88 + Float.random(in: -0.04...0.04))
            if !race.active { HapticDriver.room?.hopLandTap(energy: 0.3 + f) }
        }
    }
}
