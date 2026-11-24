//
//  CafeTalkProbe.swift
//  Dev log for the café table after the meal (`-CafeTalkLog 1`, dev builds only): once per game second per body, "[cafetalk]" with the distance from its stand,
//  the yaw error against the facing it should keep (+ the body twist), what it is doing; and a count of the chirp requests by source. Capture / test aid only.
//

import Foundation
import simd

@MainActor
final class CafeTalkProbe {
    static let shared = CafeTalkProbe()
    static var on: Bool { DevArgs.enabled && UserDefaults.standard.integer(forKey: "CafeTalkLog") != 0 }
    var clock: Float = 0
    var next: Float = 0
    var started = false
    var chirps: [String: Int] = [:]

    func reset() { clock = 0; next = 0; started = false; chirps = [:] }

    func tick(_ care: GameCare, _ actors: [JellyActor], dt: Float) {
        guard Self.on else { return }
        let ph = care.cafe.phase
        guard ph == .cheer || ph == .lounge || ph == .done else { if ph != .eating { reset() }; return }
        if !started {
            started = true
            AudioHub.requestSrcTap = { what, jelly in
                guard what.hasPrefix("chirp:") else { return }
                let src = String(what.split(separator: "@").last ?? "?")
                Task { @MainActor in CafeTalkProbe.shared.chirps[src, default: 0] += 1 }
            }
        }
        clock += dt
        guard clock >= next else { return }
        next += 1
        for a in actors {
            guard let b = a.brain, let st = care.cafeBook.stands[a.id] else { continue }
            let want = care.cafeSeats(actors).first { $0.id == a.id }?.yaw ?? b.faceCameraYaw()
            let d = simd_distance(GameCare.floorPos(b, a.sim), st)
            let e = abs(GameCare.wrapAngle(b.yaw + b.twist + b.chat.twist - want))
            NSLog("[cafetalk] t=%.1f phase=%@ id=%d dist=%.3f yawErr=%.3f act=%@ idle=%@ feet=%d chirps=%@", clock, "\(ph)", a.id, d, e, "\(b.activity)", b.idleState.kind?.rawValue ?? "-", b.feet.active ? 1 : 0, "\(chirps.sorted { $0.key < $1.key })")
        }
    }
}

/// cafe-busy-r1: counts what a player's Jelmiko does after its treat is done (`-CafeCalmLog 1`, dev builds only): every step it counts the RISING edges of a turn (facing more than 0.3 rad off its seat),
/// a move (more than 0.2 u off its stand) and an action (a walk / emote / hop / idle that is not the talk's own giggle), by what the action was. The summary prints at the visit's end and every 15 s.
@MainActor
final class CafeCalmProbe {
    static let shared = CafeCalmProbe()
    static var on: Bool { DevArgs.enabled && UserDefaults.standard.integer(forKey: "CafeCalmLog") != 0 }
    struct Count { var turns = 0, moves = 0, acts = 0, steps = 0; var kinds: [String: Int] = [:]; var turning = false, moving = false, acting = false }
    var by: [Int: Count] = [:]
    var next: Float = 15, clock: Float = 0
    func reset() { by = [:]; next = 15; clock = 0 }

    func tick(_ care: GameCare, _ actors: [JellyActor], dt: Float) {
        guard Self.on else { return }
        guard care.cafe.phase == .eating || care.cafe.phase == .cheer || care.cafe.phase == .lounge || care.cafe.phase == .done else { return }
        clock += dt
        for s in care.cafeSeats(actors) where care.cafeFinished(s.id) {
            let b = s.brain
            var c = by[s.id] ?? Count()
            c.steps += 1
            let yawErr = abs(GameCare.wrapAngle(b.yaw + b.twist + b.chat.twist - s.yaw))
            let off = simd_distance(GameCare.floorPos(b, s.sim), s.stand)
            let calmAct = b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace
            var what = ""
            if case .none = b.script {} else { what = "script:\(b.script)".prefix(24).description }
            if what.isEmpty, !calmAct { what = "act:\(b.activity)" }
            if what.isEmpty, let k = b.idleState.kind, k != .giggle { what = "idle:\(k.rawValue)" }
            if what.isEmpty, let k = b.commandedIdle, k != .giggle { what = "cmd:\(k.rawValue)" }
            if b.idleState.kind == .giggle || b.commandedIdle == .giggle { if !what.hasPrefix("script:walk") && !what.hasPrefix("script:dine") { what = "" } }          // (the talk's own giggle is allowed)
            let busy = !what.isEmpty
            if yawErr > 0.3 { if !c.turning { c.turns += 1; c.kinds["turn@" + (what.isEmpty ? "-" : what), default: 0] += 1 }; c.turning = true } else if yawErr < 0.15 { c.turning = false }
            if off > 0.2 { if !c.moving { c.moves += 1; c.kinds["move@" + (what.isEmpty ? "-" : what), default: 0] += 1 }; c.moving = true } else if off < 0.1 { c.moving = false }
            if busy { if !c.acting { c.acts += 1; c.kinds[what, default: 0] += 1 }; c.acting = true } else { c.acting = false }
            by[s.id] = c
        }
        if clock >= next { next += 15; summary("t=\(Int(clock))") }
    }
    func summary(_ tag: String) {
        guard Self.on, !by.isEmpty else { return }
        NSLog("[cafecalm] %@ %@", tag, by.sorted { $0.key < $1.key }.map { "id\($0.key) turns=\($0.value.turns) moves=\($0.value.moves) acts=\($0.value.acts) steps=\($0.value.steps) \($0.value.kinds.sorted { $0.key < $1.key })" }.joined(separator: " | "))
    }
}
