//
//  PetLanes.swift
//  Two-finger petting (pet-two-r1): "use both thumbs to pet two at a time".
//
//  The FIRST finger on the close-up is the primary and runs exactly as always (the stage's mode / gesture / `model.touch`): it alone can pick up, throw, pinch the cheeks or tap.
//  While it is down on a Jelmiko (pending or stroking), a later finger that lands on a DIFFERENT Jelmiko of the close-up gets a PET LANE: one `TouchPlay` for that body only, fed
//  by that finger from down to up. A lane only pets (dent, eyes, lean, hearts, purr, the grumpy refusal, attention credit): no gesture classifier, so it never lifts, throws or taps.
//  A lane outlives its finger until the body has settled, then is removed; a lifted / cancelled finger ends its own stroke only.
//
//  Haptics: the phone has ONE motor. A lane's TouchPlay has its own capture driver (no engine); its continuous levels are held by `LaneTapSink` and folded into the primary
//  driver's single request (`HapticDriver.companion` / `mix`: the stronger plus a quarter of the weaker, a little fuller), its transients are forwarded without a second sound.
//  Sounds: a lane's paired touch sounds are 0.7x (`laneSoundGain`) so two together stay sensible; each brain's own chirps are untouched.
//

import Foundation
import QuartzCore
import UIKit
import simd

/// Where a finger that lands in the close-up goes. Pure, so the table is testable without a stage.
enum PetRoute: Equatable {
    case primary                 // the finger starts the one primary touch (as always)
    case cheeksCandidate         // a second finger on the primary's own Jelmiko: the stage's existing cheeks pinch (it decides)
    case lane                    // a pet-only lane on the Jelmiko under the finger
    case ignore                  // nothing happens (as before)

    enum Primary: Equatable { case none, pending, pet, grab, cheeks }

    /// `picked`: the focused Jelmiko under the finger (nil = empty floor). `touchID`: the primary's Jelmiko. `liveLanes`: Jelmiko with a finger on a lane now.
    static func route(primary: Primary, picked: Int?, touchID: Int, liveLanes: Set<Int>, maxLanes: Int = PetLanes.maxLanes, getUpOff: Bool = true) -> PetRoute {
        guard let picked else { return .ignore }
        switch primary {
        case .none:
            if liveLanes.contains(picked) { return .ignore }          // that Jelmiko is already being petted by another finger: one stroke per body
            return getUpOff ? .primary : .ignore
        case .grab, .cheeks:
            return .ignore                                           // a hold / a drag / a cheeks pinch is not disturbed by another finger: it is never dropped, thrown or moved
        case .pending, .pet:
            if picked == touchID { return primary == .pending ? .cheeksCandidate : .ignore }
            if liveLanes.contains(picked) || liveLanes.count >= maxLanes { return .ignore }
            return .lane
        }
    }
}

/// Holds a lane driver's continuous levels (nothing is played: the primary driver plays the mix) and hands its transients on, silently, to the primary driver.
@MainActor
final class LaneTapSink: HapticSink {
    private(set) var level: [HapticChannel: (i: Float, s: Float)] = [:]
    weak var target: HapticDriver?
    init() {}
    nonisolated deinit {}
    func start() {}
    func stop() { level.removeAll() }
    func setContinuous(_ ch: HapticChannel, intensity: Float, sharpness: Float) { level[ch] = (intensity, sharpness) }
    func transient(intensity: Float, sharpness: Float) { target?.softTap(now: 0, intensity: intensity, sharpness: sharpness) }
    func wobble(peak: Float, sharpness: Float, tau: Float, duration: Float) { target?.softWobble(peak: peak, sharpness: sharpness, tau: tau, duration: duration) }
}

@MainActor
final class PetLane {
    let jelly: Int
    let play: TouchPlay
    let driver: HapticDriver
    let tap = LaneTapSink()
    /// The finger on this lane (nil once it lifted or was cancelled: the lane then settles and is removed).
    var finger: ObjectIdentifier?
    var point: CGPoint
    var size: CGSize
    fileprivate var owed: Float = 0
    fileprivate var owedClock: Float = 0
    fileprivate var lastBorn: Double = -.infinity

    init(jelly: Int, finger: ObjectIdentifier, point: CGPoint, size: CGSize, target: HapticDriver?) {
        self.jelly = jelly; self.finger = finger; self.point = point; self.size = size
        let d = HapticDriver(sinks: [tap])
        d.soundGain = PetLanes.laneSoundGain
        d.enabled = true
        d.setWarm(true)
        driver = d
        play = TouchPlay(haptics: d)
        tap.target = target
    }
}

@MainActor
final class PetLanes {
    /// The primary plus this many lanes = up to three fingers (one per Jelmiko of the close-up).
    static let maxLanes = 2
    static let laneSoundGain: Float = 0.7

    private(set) var lanes: [Int: PetLane] = [:]          // by Jelmiko id: one lane (one TouchPlay) per body, never two

    var isEmpty: Bool { lanes.isEmpty }
    /// Jelmiko with a finger on a lane right now.
    var liveIDs: Set<Int> { Set(lanes.values.filter { $0.finger != nil }.map(\.jelly)) }
    func owns(_ finger: ObjectIdentifier) -> Bool { lanes.values.contains { $0.finger == finger } }

    /// A finger lands on Jelmiko `jelly`: its lane starts (or, if that body's lane is still settling from a lifted finger, takes the new finger over).
    @discardableResult
    func begin(jelly: Int, finger: ObjectIdentifier, point: CGPoint, size: CGSize, target: HapticDriver?) -> PetLane {
        if let l = lanes[jelly] { l.finger = finger; l.point = point; l.size = size; return l }
        let l = PetLane(jelly: jelly, finger: finger, point: point, size: size, target: target)
        lanes[jelly] = l
        return l
    }

    func move(finger: ObjectIdentifier, point: CGPoint, size: CGSize) -> Bool {
        guard let l = lanes.values.first(where: { $0.finger == finger }) else { return false }
        l.point = point; l.size = size
        return true
    }

    /// The finger lifted / was cancelled: its stroke ends, the body settles (the lane is removed by `tick` once it has).
    func end(finger: ObjectIdentifier) -> Bool {
        guard let l = lanes.values.first(where: { $0.finger == finger }) else { return false }
        l.finger = nil
        return true
    }

    /// The combined request of every lane for the primary driver (nil = none).
    func companionLevels() -> (pi: Float, ps: Float, si: Float, ss: Float)? {
        guard !lanes.isEmpty else { return nil }
        var pi: Float = 0, ps: Float = 0.1, si: Float = 0, ss: Float = 0.5
        for l in lanes.values {
            let p = l.tap.level[.pet], q = l.tap.level[.squish]
            if let p, p.i > 0 { ps = pi > 0 ? (p.i > pi ? p.s : ps) : p.s; pi = HapticDriver.mix(pi, p.i) }
            if let q, q.i > 0 { ss = si > 0 ? (q.i > si ? q.s : ss) : q.s; si = HapticDriver.mix(si, q.i) }
        }
        return pi > 0 || si > 0 ? (pi, ps, si, ss) : nil
    }

    /// What a lane's body offers the frame: nil drops the lane (the Jelmiko is gone, or his brain is not running).
    struct Body {
        var sim: SoftBody
        var brain: BlobBrain?
        var skinner: Skinner
        var mood: BlobMood
        var attentionWanted: Bool
        /// The world ray under the lane's finger (nil = no finger).
        var ray: (o: SIMD3<Float>, d: SIMD3<Float>)?
        var screen: SIMD2<Float>?
    }

    /// One frame, BEFORE the primary's pet frame (so its haptic request sees fresh lane levels). `credit(jelly, amount)`: attention earned by petting / purring (the same rates
    /// as the primary's, in the same 0.5 s lumps). `heart(jelly, born)`: a new heart over that Jelmiko's head.
    func tick(dt: Float, now: Double, surface: RestSurface?, body: (PetLane) -> Body?, credit: (Int, Float) -> Void, heart: (Int, Double) -> Void) {
        for (id, l) in lanes {
            guard let b = body(l) else { cancel(id, sim: nil, brain: nil, skinner: nil); continue }
            l.play.mood = b.mood; l.play.attentionWanted = b.attentionWanted
            l.play.petFrame(dt: dt, now: now, ray: l.finger == nil ? nil : b.ray, screen: l.finger == nil ? nil : b.screen, sim: b.sim, brain: b.brain, skinner: b.skinner, surface: surface)
            for h in l.play.hearts where h.born > l.lastBorn { l.lastBorn = h.born; heart(id, h.born) }
            let petting = l.play.contact && l.play.speed > TouchPlay.strokeSpeed * 0.5
            if petting || l.play.isPurring { l.owed += dt * (l.play.isPurring ? NeedsTuning.purrRate : NeedsTuning.petRate) }
            l.owedClock += dt
            if l.owedClock >= 0.5 { l.owedClock = 0; if l.owed > 0 { credit(id, l.owed); l.owed = 0 } }
            if l.finger == nil, !l.play.isActive, !b.sim.pressing {
                if l.owed > 0 { credit(id, l.owed) }
                cancel(id, sim: b.sim, brain: b.brain, skinner: b.skinner)
            }
        }
    }

    /// Drops a lane and everything it had on its body.
    func cancel(_ id: Int, sim: SoftBody?, brain: BlobBrain?, skinner: Skinner?) {
        guard let l = lanes.removeValue(forKey: id) else { return }
        l.finger = nil
        if let sim, let skinner { l.play.cancel(sim: sim, brain: brain, skinner: skinner) }
        l.tap.stop()
    }

    /// Focus ended / paused / a new close-up: every lane goes at once.
    func cancelAll(body: (Int) -> (SoftBody, BlobBrain?, Skinner)?) {
        for id in Array(lanes.keys) {
            if let b = body(id) { cancel(id, sim: b.0, brain: b.1, skinner: b.2) } else { cancel(id, sim: nil, brain: nil, skinner: nil) }
        }
    }
}
