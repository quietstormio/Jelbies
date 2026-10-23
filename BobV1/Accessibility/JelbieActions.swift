//
//  JelbieActions.swift
//  The custom actions of a Jelbie accessibility element (round-1023 a11y): each one calls the SAME care API the HUD button calls, with the same
//  guards, and says why when it cannot run. The close-up touches (pet, pat, boop, poke, squish, toss) are SCRIPTED fingers: `ScriptedTouch`
//  describes the timed path in the Jelbie's own screen space, and the stage feeds it through the normal pointer path (MelonController.runScripted),
//  so hearts, haptics, sounds and the stubby-arms / attached-feet invariants are exactly those of a real finger.
//

import Foundation
import CoreGraphics

enum JelbieAction: String, CaseIterable, Sendable {
    case highlight, callOver, feed, water, train, bed, wake
    case pet, patHead, boopCheek, pokeBelly, squishCheeks, toss, letGo

    func title(_ name: String) -> String {
        switch self {
        case .highlight: return "Highlight \(name)"
        case .callOver: return "Call \(name) over"
        case .feed: return "Feed \(name)"
        case .water: return "Give \(name) water"
        case .train: return "Train \(name)"
        case .bed: return "Put \(name) to bed"
        case .wake: return "Wake \(name) up"
        case .pet: return "Pet \(name)"
        case .patHead: return "Pat \(name)'s head"
        case .boopCheek: return "Boop \(name)'s cheek"
        case .pokeBelly: return "Poke \(name)'s belly"
        case .squishCheeks: return "Squish \(name)'s cheeks"
        case .toss: return "Toss \(name) up"
        case .letGo: return "Let \(name) go"
        }
    }

    /// The scripted touch behind a close-up action.
    var script: ScriptedTouch.Kind? {
        switch self {
        case .pet: return .pet
        case .patHead: return .patHead
        case .boopCheek: return .boopCheek
        case .pokeBelly: return .pokeBelly
        case .squishCheeks: return .squishCheeks
        case .toss: return .toss
        default: return nil
        }
    }
}

/// A finger drawn by the app: a timed path in body space (x right, y up from his centroid, in sim units like the stage's touch demo), per pointer.
nonisolated struct ScriptedTouch: Sendable {
    enum Kind: String, CaseIterable, Sendable { case pet, patHead, boopCheek, pokeBelly, squishCheeks, toss }
    let kind: Kind
    /// Seconds the script runs (every pointer is up after this).
    var duration: Double {
        switch kind {
        case .pet: return 1.4
        case .patHead, .boopCheek, .pokeBelly: return 0.22
        case .squishCheeks: return 2.2
        case .toss: return 1.1
        }
    }
    static let pointerCount = 2

    private static func sm(_ v: Double) -> Float { let k = Float(min(1, max(0, v))); return k * k * (3 - 2 * k) }

    /// Where each pointer is at time `t` (nil = lifted).
    func frame(at t: Double) -> [SIMD2<Float>?] {
        guard t >= 0, t < duration else { return [nil, nil] }
        switch kind {
        case .pet:                       // three strokes back and forth over his belly and cheek, the way a rub goes
            let k = Float(min(1, t / 0.25)), ph = Float(t)
            return [SIMD2(0.4 * sinf(2 * .pi * 1.1 * ph) * k, 0.25 * sinf(2 * .pi * 0.55 * ph) * k), nil]
        case .patHead:
            return t < 0.1 ? [SIMD2(0, 0.55), nil] : [nil, nil]
        case .boopCheek:
            return t < 0.1 ? [SIMD2(0.5, 0.16), nil] : [nil, nil]
        case .pokeBelly:
            return t < 0.1 ? [SIMD2(0, -0.2), nil] : [nil, nil]
        case .squishCheeks:              // two fingers 0.1 s apart on the cheeks, still, then together, held, and off
            let g = 0.5 - 0.3 * Self.sm((t - 0.6) / 0.9)
            let a: SIMD2<Float>? = t < 1.8 ? SIMD2(-g, 0.16) : nil
            let b: SIMD2<Float>? = (t >= 0.1 && t < 1.8) ? SIMD2(g, 0.16) : nil
            return [a, b]
        case .toss:                      // tap, tap-and-hold on the crown, lift gently, let go (slower than a throw: he is put down, not thrown)
            if t < 0.1 { return [SIMD2(0, 0.62), nil] }
            if t < 0.3 { return [nil, nil] }
            let lift = 0.3 * Self.sm((t - 0.55) / 0.45)
            return [SIMD2(0, 0.62 + lift), nil]
        }
    }
}

/// Runs a script: the pointer edges (down / move / up) between two frames.
nonisolated struct ScriptedTouchRun: Sendable {
    enum Edge: Equatable, Sendable { case down(Int, SIMD2<Float>), move(Int, SIMD2<Float>), up(Int) }
    let script: ScriptedTouch
    let jelly: Int
    var t0: Double
    private(set) var down: [Bool] = [false, false]
    private(set) var finished = false

    init(_ kind: ScriptedTouch.Kind, jelly: Int, start: Double) { script = ScriptedTouch(kind: kind); self.jelly = jelly; t0 = start }

    /// The edges to apply at time `now`. When `cancelled`, everything still down is lifted and the run ends.
    mutating func step(now: Double, cancelled: Bool = false) -> [Edge] {
        guard !finished else { return [] }
        var out: [Edge] = []
        let f = cancelled ? [nil, nil] : script.frame(at: now - t0)
        for k in 0..<ScriptedTouch.pointerCount {
            switch (down[k], f[k]) {
            case (false, .some(let p)): down[k] = true; out.append(.down(k, p))
            case (true, .some(let p)): out.append(.move(k, p))
            case (true, nil): down[k] = false; out.append(.up(k))
            default: break
            }
        }
        if cancelled || now - t0 >= script.duration { finished = true }
        return out
    }
}

@MainActor
enum JelbieActions {
    /// Why nothing can be done to Jelbies right now (nil = fine).
    static func busyReason(_ care: GameCare) -> String? {
        if care.tripActive { return "Not now. A race or show is on" }
        if care.bath.active { return "Not now. It is bath time" }
        if care.arranging { return "Finish arranging the room first" }
        return nil
    }

    /// The actions on offer for Jelbie `id`, in reading order, for the current state. Roaming: care actions; in his close-up: the touches.
    static func available(_ care: GameCare, id: Int, asleep: Bool) -> [JelbieAction] {
        if busyReason(care) != nil { return [] }
        if care.focus.isActive {
            guard care.focusGroup.ids.contains(id) else { return [] }
            if care.focus.isFocused { return [.pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss, .letGo] }
            return [.letGo]
        }
        var out: [JelbieAction] = [.highlight, .callOver, .feed, .water, .train]
        out.append(asleep ? .wake : .bed)
        return out
    }

    /// Runs `action` on Jelbie `id`. Returns true only if it started; otherwise says why (announcement) and returns false.
    /// `touch`: starts a scripted finger on the stage (false when one cannot run).
    @discardableResult
    static func perform(_ action: JelbieAction, id: Int, care: GameCare, asleep: Bool = false, touch: (ScriptedTouch.Kind, Int) -> Bool = { _, _ in false }) -> Bool {
        func no(_ why: String) -> Bool { A11yAnnounce.say(why, priority: .high); return false }
        guard let prof = care.jelly(id) else { return false }
        let name = prof.name
        if let why = busyReason(care) { return no(why) }
        if care.focus.isActive {
            switch action {
            case .letGo:
                guard care.focus.phase != .leaving else { return false }
                care.release(); return true
            case .pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss:
                guard care.focus.isFocused else { return no("\(name) is still coming over") }
                guard care.focusGroup.ids.contains(id) else { return no("\(name) is not in the close-up") }
                guard let k = action.script, touch(k, id) else { return no("One moment") }
                return true
            default: return no("Let \(name) go first")
            }
        }
        switch action {
        case .highlight:
            care.tapJelly(id)
            return true
        case .callOver:
            care.comeHere(jelly: id); return true
        case .feed:
            if care.trayOut { return no("Food is already out") }
            guard GameRouter.shared.perform(.feed(id), care: care) else { return no("\(name) cannot eat right now") }
            return true
        case .water:
            if care.trayOut { return no("A drink is already out") }
            guard GameRouter.shared.perform(.water(id), care: care) else { return no("\(name) cannot drink right now") }
            return true
        case .train:
            care.beginTraining(id); return true
        case .bed:
            if !care.canBedtime { return no("Bedtime is not possible right now") }
            care.bedtime(ids: [id]); return true
        case .wake:
            guard asleep else { return no("\(name) is awake") }
            care.wakeSleeper(id, groggy: false); return true
        case .pet, .patHead, .boopCheek, .pokeBelly, .squishCheeks, .toss:
            return no("Call \(name) over first")
        case .letGo:
            return no("\(name) is not in a close-up")
        }
    }
}
