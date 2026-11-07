//
//  BlobBrain+Weather.swift
//  What the Jelbies do in a storm (Melon/Weather.swift is the storm). StormReactor turns the storm's events into reactions, on moves that already exist:
//    notice     in the build-up one Jelbie walks to a window and peers out worried (the window antic, `commandedIdle = .window`)
//    startle    the first close thunder: a surprised face and a flinch (and a hop, the startle's own)
//    huddle     during the peak every free Jelbie scurries (the walk at the hurry speed, `hurry`) to a tight cluster and stands pressed close: slots a little more than
//               the room's keep-apart gap apart (`Lineup` picks who takes which, walks never cross and never run through a standing Jelbie), a hunched stance,
//               a fine tremble, worried eyes, and a flinch at every flash. Everything is the storm POSE CHANNEL (`BlobBrain.storm`, an EarsPose added in `drivePose`):
//               the body, the feet and the walk are untouched, so the feet stay attached by construction (StormFeetTests).
//    comfort    a Jelbie the player is holding or petting (a finger on him, a close-up) stays with the player and calms: no gather, no tremble, a calm face
//    sleepers   flinch (a jelly wobble), and at the first close thunder of the peak wake grumpy and join the others
//    relief     when the storm clears the cluster breaks with a relieved group shake-off (the `shake` move), a sigh, and they scatter
//  Busy Jelbies (a meal, the bath, a race or any trip, a voice lesson) skip all of it; a lock that starts mid-huddle lets everybody go at once.
//

import Foundation
import simd

nonisolated enum StormTuning {
    /// Centre distance of two huddled Jelbies relative to the room's keep-apart gap (MelonController.jellyGap): a hair more, so nobody is pushed.
    static let gapFactor: Float = 1.05
    /// The tremble.
    static let trembleHz: Float = 9, trembleRoll: Float = 0.030, trembleSquash: Float = 0.012
    /// The hunched stance (squash below 1) and the lean forward (rad).
    static let hunch: Float = 0.05, lean: Float = 0.02
    /// The flash flinch: squash dip, forward pitch (rad), rise and fall times (s).
    static let flinchSquash: Float = 0.10, flinchPitch: Float = 0.07, flinchRise: Float = 0.08, flinchFall: Float = 0.22
    /// Seconds the startle lasts before the scurry begins.
    static let startleTime: Float = 0.8
    /// A scurrying Jelbie that has not arrived after this long is taken as arrived where he stands.
    static let gatherLimit: Float = 12
    /// The shake-offs are staggered this much; the scatter walks start after the shake.
    static let shakeStagger: Float = 0.28, shakeTime: Float = 3.2, scatterTime: Float = 5
}

extension BlobBrain {
    /// The storm pose channel is doing something (a huddle, a flinch, a pose not yet back to neutral): the sim must not sleep.
    var stormActive: Bool { storm.isActive }
}

/// The flinch curve: 0...1, up fast, away slowly. `t` seconds after the flash.
nonisolated func stormFlinch(_ t: Float) -> Float {
    guard t >= 0 else { return 0 }
    if t < StormTuning.flinchRise { return t / StormTuning.flinchRise }
    return expf(-(t - StormTuning.flinchRise) / StormTuning.flinchFall)
}

/// The storm pose channel's values (also what the feet suites drive).
nonisolated enum StormPose {
    /// The huddle stance `t` seconds into the storm clock, `standing` seconds after he arrived, `flinch` seconds since the last flash (-1 = none).
    static func huddle(t: Float, standing: Float, phase: Float, flinch: Float, amplitude amp: Float) -> (pitch: Float, roll: Float, squash: Float) {
        let w = 2 * Float.pi * StormTuning.trembleHz
        let build = min(1, standing / 0.5)          // the tremble builds over the first half second of standing there, and swells a little now and then
        let swell = 0.75 + 0.25 * sinf(2 * .pi * 0.37 * t + phase)
        let roll = StormTuning.trembleRoll * amp * build * swell * sinf(w * t + phase)
        let k = stormFlinch(flinch)
        let sq = 1 - StormTuning.hunch * amp * build + StormTuning.trembleSquash * amp * build * sinf(1.27 * w * t + phase * 1.7) - StormTuning.flinchSquash * amp * k
        return ((StormTuning.lean * build + StormTuning.flinchPitch * k) * amp, roll, sq)
    }
}

@MainActor
final class StormReactor {
    static let shared = StormReactor()

    struct Jelly {
        let id: Int
        let brain: BlobBrain
        let sim: SoftBody
        let skinner: Skinner
    }
    struct Locks: Equatable {
        var meal = false, focus = false, focusApproach = false, bath = false, voice = false, training = false, race = false, trip = false
        var blocksAll: Bool { meal || focusApproach || bath || voice || training || race || trip }
    }
    enum Mode: Equatable { case startled, gather, huddle, comforted, shaking, scatter }
    struct Member {
        var mode: Mode
        var t: Float = 0
        var slot = -1
        /// Seconds since the walk to the slot was asked (-1 = not yet), and how many times it was asked.
        var asked: Float = -1
        var tries = 0
        var flinch: Float = -1
        var faceClock: Float = 0
        var phase: Float = 0
        var inPlace = false
        var shakeAt: Float = 0
        var shook = false
        var spot = SIMD2<Float>.zero
    }

    var locks = Locks()
    /// The first shake-off of the relief (one soft haptic tick goes with it).
    var onFirstShake: (() -> Void)?
    private var shakeTicked = false
    private(set) var members: [Int: Member] = [:]
    private(set) var slots: [SIMD2<Float>] = []
    private(set) var stormOn = false
    private(set) var peakOn = false
    private(set) var huddleOn = false
    private(set) var firstCloseDone = false
    private var gatherAt: Float?
    private var clock: Float = 0
    private var noticer: Int?
    private var noticeFace: Float = 0, noticeClock: Float = 0
    private var joinClock: Float = 0
    private var replanClock: Float = 0
    private var committed: Set<Int> = []
    private var slotOf: [Int: Int] = [:]
    private var seenSleep: Set<Int> = []
    private var rng = WeatherRNG(seed: 99)
    /// Tests / the log.
    private(set) var log: [String] = []
    private(set) var replans = 0
    private var jellies: [Jelly] = []
    private var plan: StormPlan?

    init() {}
    nonisolated deinit {}

    /// The reactor's view of the room, rebuilt only when an actor or a brain changes (no array per step).
    func refresh(actors: [JellyActor]) -> [Jelly] {
        if jellies.count == actors.count, zip(jellies, actors).allSatisfy({ $0.brain === $1.brain && $0.sim === $1.sim }) { return jellies }
        jellies = actors.compactMap { a in a.brain.map { Jelly(id: a.id, brain: $0, sim: a.sim, skinner: a.skinner) } }
        return jellies
    }

    // MARK: locks

    func update(care: GameCare) {
        var l = Locks()
        l.meal = care.trayOut || care.wanted != nil || care.meal != nil || care.groupActive
        l.focus = care.focus.isActive
        l.focusApproach = care.focus.isActive && care.focus.phase == .approaching
        l.bath = care.bath.active
        l.voice = care.voice.mode.phase != .idle
        l.training = care.voice.teachPrompt != nil
        l.race = care.race.active || care.raceWait != nil
        l.trip = care.tripActive || care.raceBusy
        locks = l
    }

    /// Is the player holding or petting him (a finger on him, or he is in the close-up)?
    func comforted(_ j: Jelly, care: GameCare?) -> Bool {
        if j.brain.activity == .touched || j.brain.activity == .recovering { return true }
        if let c = care, c.focus.isActive, c.focusGroup.ids.contains(j.id) { return true }
        return false
    }

    /// Can he join the storm reactions at all (not busy with something of his own)?
    func available(_ j: Jelly, care: GameCare?) -> Bool {
        let b = j.brain
        if b.reserved || b.race.active || b.volley.active || b.commanded || !b.enabled { return false }
        if let c = care, c.parkHides(j.id) { return false }
        return true
    }

    // MARK: events

    /// The storm's events of this step (WeatherBook.tick) and the plan they belong to.
    func handle(_ events: [StormEvent], plan p: StormPlan?, jellies js: [Jelly], care: GameCare?) {
        jellies = js
        if let p { plan = p }
        for e in events {
            switch e.kind {
            case .began:
                stormOn = true; peakOn = false; firstCloseDone = false; huddleOn = false; gatherAt = nil; seenSleep = []; noticer = nil
                note("storm begins")
            case .phase(let ph):
                if ph == .peak { peakOn = true }
                if ph == .clearing { peakOn = false; reliefBegin(care: care) }
            case .notice:
                notice(care: care)
            case .rumble:
                for j in js where available(j, care: care) && !j.brain.isSleeping && members[j.id] == nil && j.id != noticer && rng.next() < 0.5 { j.brain.face(.worried, hold: 1.4) }
            case .flash(let i):
                guard let s = plan?.strikes[safe: i], s.strength > 0.4 else { continue }
                flinchAll(care: care, big: s.close)
            case .thunder(let i):
                guard let s = plan?.strikes[safe: i] else { continue }
                if s.close { closeThunder(care: care) }
            case .ended:
                releaseAll(note: "storm ends")
                stormOn = false; peakOn = false; huddleOn = false
            }
        }
    }

    private func notice(care: GameCare?) {
        let cands = jellies.filter { available($0, care: care) && !$0.brain.isSleeping && !comforted($0, care: care) && $0.brain.idleState.kind == nil && !locks.blocksAll && !locks.focus }
        guard !cands.isEmpty else { return }
        let j = cands[Int(rng.next() * Double(cands.count)) % cands.count]
        noticer = j.id
        noticeFace = 9
        j.brain.commandedIdle = .window
        j.brain.face(.worried, hold: 3)
        note("\(j.id) notices at the window")
    }

    /// A flash: the huddled flinch; the others (awake, free) flinch where they stand; sleepers wobble.
    private func flinchAll(care: GameCare?, big: Bool) {
        for j in jellies {
            if j.brain.isSleeping { j.brain.jellyKick = max(j.brain.jellyKick, big ? 0.6 : 0.3); continue }
            if var m = members[j.id], m.mode == .huddle || m.mode == .gather { m.flinch = 0; members[j.id] = m; if m.mode == .huddle { j.brain.face(.surprised, hold: 0.45) } }
            else if members[j.id] == nil, available(j, care: care), !comforted(j, care: care), j.brain.activity == .idle {
                var m = Member(mode: .startled); m.flinch = 0; m.inPlace = true
                members[j.id] = m
                j.brain.face(.surprised, hold: 0.6)
            }
        }
    }

    /// The thunder of a close strike: the first one at the peak startles everybody and starts the gather; sleepers wake grumpy.
    private func closeThunder(care: GameCare?) {
        guard peakOn, !firstCloseDone else { return }
        firstCloseDone = true
        for j in jellies {
            if j.brain.isSleeping, available(j, care: care), !seenSleep.contains(j.id) {
                seenSleep.insert(j.id)
                j.brain.sleepWake(groggy: true, fast: true)
                j.brain.face(.grumpy, hold: 2.2)
                note("\(j.id) wakes grumpy")
            }
        }
        for j in jellies where !j.brain.isSleeping && available(j, care: care) && !locks.blocksAll {
            if comforted(j, care: care) { setComforted(j); continue }
            var m = members[j.id] ?? Member(mode: .startled)
            m.mode = .startled; m.t = 0; m.flinch = 0; m.phase = Float(j.id) * 1.7
            m.inPlace = locks.focus
            members[j.id] = m
            j.brain.face(.surprised, hold: 1.0)
            if !locks.focus, case .none = j.brain.script, j.brain.pending == nil, j.brain.idleState.kind == nil { j.brain.startHopPlay(sim: j.sim, distance: 0.0001) }
        }
        gatherAt = clock + StormTuning.startleTime
        note("first close thunder: startle")
    }

    // MARK: tick

    func tick(jellies js: [Jelly], care: GameCare?, dt: Float) {
        jellies = js
        clock += dt
        if locks.blocksAll, !members.isEmpty { releaseAll(note: "locked: \(locks)"); huddleOn = false; gatherAt = nil }
        if let t = gatherAt, clock >= t {
            gatherAt = nil
            if !locks.blocksAll { beginGather(care: care) }
        }
        if huddleOn, peakOn, !locks.blocksAll {
            joinClock += dt
            if joinClock >= 0.5 { joinClock = 0; lateJoiners(care: care) }
            replanClock += dt
            if replanClock >= Lineup.period { replanClock = 0; replan(care: care) }
        }
        if noticeFace > 0, let n = noticer, let j = jellies.first(where: { $0.id == n }) {
            noticeFace -= dt
            noticeClock += dt
            if noticeClock >= 1.3 { noticeClock = 0; if members[n] == nil, !j.brain.isSleeping { j.brain.face(.worried, hold: 1.6) } }
        }
        for j in jellies {
            guard var m = members[j.id] else { continue }
            let alive = step(&m, j, care: care, dt: dt)
            if alive { members[j.id] = m } else { members[j.id] = nil }
        }
        if !huddleOn, members.isEmpty { slots = [] }
    }

    /// One member for one step; false when he is released.
    private func step(_ m: inout Member, _ j: Jelly, care: GameCare?, dt: Float) -> Bool {
        let b = j.brain
        m.t += dt
        if m.flinch >= 0 { m.flinch += dt; if m.flinch > 0.9 { m.flinch = -1 } }
        // the stage must not let him wander off: hold the autonomous pick back like the dance does
        if m.mode != .shaking, m.mode != .scatter {
            b.restTimer = max(b.restTimer, 1.5)
            b.idleState.cooldown = max(b.idleState.cooldown, 1.5)
        }
        if b.hurry { b.hurryUpdate(dt: dt) }
        // the player has him: he stays with the player and calms
        if m.mode != .shaking, m.mode != .scatter, comforted(j, care: care) {
            if m.mode != .comforted { setComforted(j); m.mode = .comforted; m.t = 0; m.slot = -1; slotOf[j.id] = nil; committed.remove(j.id); note("\(j.id) comforted") }
            b.storm.clear()
            m.faceClock += dt
            if m.faceClock >= 1.5 { m.faceClock = 0; b.face(.neutral, hold: 1.6) }
            return true
        }
        if m.mode == .comforted {
            // let go again: back to the huddle while the peak lasts, else free
            if peakOn, huddleOn, !locks.blocksAll { m.mode = .gather; m.asked = -1; m.tries = 0; m.t = 0; m.inPlace = false; members[j.id] = m; _ = assignLate(j.id, care: care); m = members[j.id] ?? m }
            else { return release(j, care: care) }
            return true
        }
        if b.isSleeping { b.storm.clear(); return release(j, care: care) }
        let amp = b.amplitude
        switch m.mode {
        case .startled:
            let k = stormFlinch(m.flinch)
            b.storm.write(pitch: StormTuning.flinchPitch * amp * k, roll: 0, squash: 1 - StormTuning.flinchSquash * amp * k)
            // a flinch where he stands (a flash before the thunder) lets go after a second; the thunder's startle waits for the gather (or the lock that cancels it)
            if m.inPlace, m.t >= 1.0, !huddleOn { return release(j, care: care) }
            if !m.inPlace, gatherAt == nil, !huddleOn, m.t >= 3 { return release(j, care: care) }
            return true
        case .gather:
            if m.inPlace || locks.focus { trembleInPlace(&m, j, dt: dt); return true }
            if m.asked < 0 {
                guard m.slot >= 0, slots.indices.contains(m.slot) else { return true }
                if b.isSocial { b.stop() }
                b.hurry = true
                b.requestNow(.come(to: slots[m.slot]))
                m.asked = 0; m.tries += 1
                b.storm.clear()
            }
            m.asked += dt
            m.faceClock += dt
            if m.faceClock >= 1.3 { m.faceClock = 0; b.face(.worried, hold: 1.6) }
            let flinchK = stormFlinch(m.flinch)
            if flinchK > 0 { b.storm.write(pitch: StormTuning.flinchPitch * 0.6 * amp * flinchK, roll: 0, squash: 1 - StormTuning.flinchSquash * 0.6 * amp * flinchK) } else { b.storm.clear() }
            let here = GameCare.floorPos(b, j.sim)
            let near = m.slot >= 0 && slots.indices.contains(m.slot) ? simd_distance(here, slots[m.slot]) : 99
            if near < Lineup.commitDistance { committed.insert(j.id) }
            let idle = b.pending == nil && b.activity == .idle && { if case .none = b.script { return true }; return false }()
            if m.asked > 0.4, idle {
                if near < 0.5 || m.tries >= 3 || m.asked > StormTuning.gatherLimit { m.mode = .huddle; m.t = 0; m.asked = -1; committed.insert(j.id); b.hurry = false }
                else { m.asked = -1 }          // stopped short (steering held him): ask again
            } else if m.asked > StormTuning.gatherLimit { m.mode = .huddle; m.t = 0; committed.insert(j.id); b.hurry = false }
            return true
        case .huddle:
            if m.inPlace || locks.focus { trembleInPlace(&m, j, dt: dt); return true }
            // a member pushed away (a mate's step-aside) walks back
            if m.slot >= 0, slots.indices.contains(m.slot), b.pending == nil, b.activity == .idle, simd_distance(GameCare.floorPos(b, j.sim), slots[m.slot]) > 0.7, m.t > 1.0 {
                m.mode = .gather; m.asked = -1; m.tries = 0; return true
            }
            trembleInPlace(&m, j, dt: dt)
            return true
        case .shaking:
            b.storm.clear()
            if !m.shook, m.t >= m.shakeAt {
                m.shook = true
                if !shakeTicked { shakeTicked = true; onFirstShake?() }
                b.commandedIdle = .shake
                b.face(.happy, hold: 2.6)
            }
            if m.t >= m.shakeAt + StormTuning.shakeTime { m.mode = .scatter; m.t = 0; m.asked = -1 }
            return true
        case .scatter:
            if m.asked < 0 {
                m.asked = 0
                b.hurry = false
                b.requestNow(.goTo(m.spot))
            }
            m.asked += dt
            let idle = b.pending == nil && b.activity == .idle && { if case .none = b.script { return true }; return false }()
            if (m.asked > 0.4 && idle) || m.asked > StormTuning.scatterTime { return release(j, care: care) }
            return true
        default:
            return true
        }
    }

    /// The huddle stance: hunched, a fine tremble, worried eyes, the flinch on top.
    private func trembleInPlace(_ m: inout Member, _ j: Jelly, dt: Float) {
        let b = j.brain
        m.faceClock += dt
        if m.faceClock >= 1.3 { m.faceClock = 0; b.face(.worried, hold: 1.6) }
        let p = StormPose.huddle(t: clock, standing: m.t, phase: m.phase, flinch: m.flinch, amplitude: b.amplitude)
        b.storm.write(pitch: p.pitch, roll: p.roll, squash: p.squash)
        b.storm.dancing = false
    }

    private func setComforted(_ j: Jelly) {
        j.brain.hurry = false
        j.brain.storm.clear()
        j.brain.face(.neutral, hold: 1.6)
    }

    // MARK: the huddle

    private func beginGather(care: GameCare?) {
        let ids = jellies.filter { j in
            guard available(j, care: care), !j.brain.isSleeping, !comforted(j, care: care) else { return false }
            return true
        }.map(\.id)
        huddleOn = true
        committed = []; slotOf = [:]; replans = 0
        guard !ids.isEmpty else { note("huddle: nobody free"); return }
        for id in ids {
            var m = members[id] ?? Member(mode: .gather)
            m.mode = .gather; m.t = 0; m.asked = -1; m.tries = 0; m.inPlace = locks.focus; m.phase = Float(id) * 1.7
            members[id] = m
        }
        if locks.focus {
            for id in ids { members[id]?.mode = .huddle; members[id]?.inPlace = true }
            note("huddle in place (close-up on)"); return
        }
        planCluster(ids: ids, care: care)
        note("huddle begins: \(ids.count) at \(slots.map { String(format: "(%.1f,%.1f)", $0.x, $0.y) })")
    }

    /// The cluster slots for `ids` and who takes which.
    private func planCluster(ids: [Int], care: GameCare?) {
        let js = ids.compactMap { id in jellies.first { $0.id == id } }
        guard !js.isEmpty else { return }
        let floors = js.map { GameCare.floorPos($0.brain, $0.sim) }
        let others = jellies.filter { !ids.contains($0.id) }.map { GameCare.floorPos($0.brain, $0.sim) }
        let gap = MelonController.jellyGap * StormTuning.gapFactor
        let centroid = floors.reduce(SIMD2<Float>.zero, +) / Float(floors.count)
        let probe = js[0].brain
        // the cluster centre: the nearest to where they are such that every slot is a floor the resolver leaves alone (walls, decor) and clear of the others
        var offsets: [SIMD2<Float>] = [.zero]
        for r in stride(from: Float(0.5), through: 3.5, by: 0.5) { for k in 0..<12 { let a = Float(k) * (.pi / 6); offsets.append(SIMD2(cosf(a), sinf(a)) * r) } }
        var chosen: [SIMD2<Float>]?
        for off in offsets {
            let c = centroid + off
            let s = Self.clusterSlots(centre: c, count: js.count, gap: gap)
            let ok = s.allSatisfy { p in
                let q = probe.resolve(SIMD3(p.x, 0, p.y), probe.footprint)
                return simd_distance(SIMD2(q.x, q.z), p) < 0.05 && others.allSatisfy { simd_distance($0, p) >= gap }
            }
            if ok { chosen = s; break }
        }
        let s = chosen ?? Self.clusterSlots(centre: centroid, count: js.count, gap: gap).map { p in let q = probe.resolve(SIMD3(p.x, 0, p.y), probe.footprint); return SIMD2(q.x, q.z) }
        slots = s
        let plan = Lineup.best(from: floors, slots: s, locked: [Int?](repeating: nil, count: js.count), centre: nil, bystanders: others)
        for (i, j) in js.enumerated() { slotOf[j.id] = plan[i]; members[j.id]?.slot = plan[i] }
    }

    /// Slots in a tight cluster: `count` points `gap` apart round `centre` (one: the centre; two: side by side; more: a regular polygon, the first at the back).
    nonisolated static func clusterSlots(centre c: SIMD2<Float>, count n: Int, gap: Float) -> [SIMD2<Float>] {
        switch n {
        case 0: return []
        case 1: return [c]
        case 2: return [c + SIMD2(-gap / 2, 0), c + SIMD2(gap / 2, 0)]
        default:
            let r = gap / (2 * sinf(.pi / Float(n)))
            return (0..<n).map { k in let a = -Float.pi / 2 + 2 * .pi * Float(k) / Float(n); return c + SIMD2(cosf(a), sinf(a)) * r }
        }
    }

    /// Re-read a few times a second until each commits (within `Lineup.commitDistance`), like the close-up row.
    private func replan(care: GameCare?) {
        let ids = members.filter { $0.value.mode == .gather && !$0.value.inPlace && $0.value.slot >= 0 }.map(\.key).sorted()
        guard ids.count > 1, slots.count >= ids.count else { return }
        let all = members.filter { ($0.value.mode == .gather || $0.value.mode == .huddle) && !$0.value.inPlace && $0.value.slot >= 0 }.map(\.key).sorted()
        let js = all.compactMap { id in jellies.first { $0.id == id } }
        guard js.count == all.count else { return }
        let floors = js.map { GameCare.floorPos($0.brain, $0.sim) }
        for (i, id) in all.enumerated() where !committed.contains(id) {
            if let s = slotOf[id], slots.indices.contains(s), simd_distance(floors[i], slots[s]) < Lineup.commitDistance { committed.insert(id) }
        }
        guard committed.count < all.count else { return }
        let bystanders = jellies.filter { !all.contains($0.id) }.map { GameCare.floorPos($0.brain, $0.sim) }
        let plan = Lineup.best(from: floors, slots: slots, locked: all.map { committed.contains($0) ? slotOf[$0] : nil }, centre: nil, bystanders: bystanders, current: all.map { slotOf[$0] ?? -1 })
        for (i, id) in all.enumerated() where slotOf[id] != plan[i] && !committed.contains(id) {
            slotOf[id] = plan[i]; members[id]?.slot = plan[i]; replans += 1
            if members[id]?.mode == .gather, members[id]?.asked ?? -1 >= 0, let b = jellies.first(where: { $0.id == id })?.brain {
                b.requestNow(.come(to: slots[plan[i]])); members[id]?.asked = 0
            }
        }
    }

    /// A Jelbie who becomes free during the peak (woke up, was let go by the player, finished a move) joins the cluster beside it.
    private func lateJoiners(care: GameCare?) {
        guard !locks.focus else { return }
        for j in jellies where members[j.id] == nil && available(j, care: care) && !j.brain.isSleeping && !comforted(j, care: care) && j.brain.idleState.kind != .sleep {
            var m = Member(mode: .gather); m.phase = Float(j.id) * 1.7
            members[j.id] = m
            if !assignLate(j.id, care: care) { members[j.id] = nil }
        }
    }

    /// A spot beside the cluster for a latecomer (a gap from everybody, a floor the resolver accepts); appended to `slots`.
    private func assignLate(_ id: Int, care: GameCare?) -> Bool {
        guard let j = jellies.first(where: { $0.id == id }) else { return false }
        let gap = MelonController.jellyGap * StormTuning.gapFactor
        let anchors = jellies.filter { members[$0.id] != nil && $0.id != id && members[$0.id]?.slot ?? -1 >= 0 }.map { GameCare.floorPos($0.brain, $0.sim) }
        let everyone = jellies.filter { $0.id != id }.map { GameCare.floorPos($0.brain, $0.sim) }
        let here = GameCare.floorPos(j.brain, j.sim)
        guard !anchors.isEmpty else {
            // nobody huddles yet: he trembles where he stands
            members[id]?.inPlace = true; members[id]?.mode = .huddle; members[id]?.slot = -1
            return true
        }
        var best: (d: Float, p: SIMD2<Float>)?
        for a in anchors { for k in 0..<16 {
            let ang = Float(k) * (.pi / 8)
            let p = a + SIMD2(cosf(ang), sinf(ang)) * gap
            let q = j.brain.resolve(SIMD3(p.x, 0, p.y), j.brain.footprint)
            guard simd_distance(SIMD2(q.x, q.z), p) < 0.05, everyone.allSatisfy({ simd_distance($0, p) >= gap * 0.99 }) else { continue }
            let d = simd_distance(here, p)
            if best == nil || d < best!.d { best = (d, p) }
        } }
        guard let b = best else {
            members[id]?.inPlace = true; members[id]?.mode = .huddle; members[id]?.slot = -1
            return true
        }
        slots.append(b.p)
        members[id]?.slot = slots.count - 1; slotOf[id] = slots.count - 1
        members[id]?.mode = .gather; members[id]?.asked = -1; members[id]?.inPlace = false
        return true
    }

    // MARK: relief

    private func reliefBegin(care: GameCare?) {
        gatherAt = nil
        shakeTicked = false
        let ids = members.keys.sorted()
        guard !ids.isEmpty else { huddleOn = false; return }
        var centre = SIMD2<Float>.zero, n: Float = 0
        for id in ids { if let j = jellies.first(where: { $0.id == id }) { centre += GameCare.floorPos(j.brain, j.sim); n += 1 } }
        centre /= max(n, 1)
        for (k, id) in ids.enumerated() {
            guard var m = members[id], let j = jellies.first(where: { $0.id == id }) else { continue }
            if m.mode == .comforted { j.brain.face(.happy, hold: 2.0); continue }
            j.brain.hurry = false
            m.mode = .shaking; m.t = 0; m.shook = false; m.shakeAt = Float(k) * StormTuning.shakeStagger; m.inPlace = false
            // the scatter: away from the cluster, each in his own direction, onto floor the resolver accepts
            let here = GameCare.floorPos(j.brain, j.sim)
            var dir = here - centre
            if simd_length(dir) < 0.05 { let a = Float(k) * 2.1; dir = SIMD2(cosf(a), sinf(a)) }
            dir = simd_normalize(dir)
            var spot = here
            for r: Float in [2.4, 1.9, 1.4, 1.0] {
                let p = here + dir * r
                let q = j.brain.resolve(SIMD3(p.x, 0, p.y), j.brain.footprint)
                if simd_distance(SIMD2(q.x, q.z), p) < 0.15 { spot = p; break }
            }
            m.spot = spot
            members[id] = m
        }
        huddleOn = false
        note("relief: shake off and scatter")
    }

    // MARK: release

    /// He is a free Jelbie again.
    @discardableResult
    private func release(_ j: Jelly, care: GameCare?) -> Bool {
        j.brain.storm.clear()
        j.brain.hurry = false
        committed.remove(j.id); slotOf[j.id] = nil
        return false
    }

    /// Everything back (a lock started, the storm ended).
    func releaseAll(note why: String = "") {
        for (id, _) in members { if let j = jellies.first(where: { $0.id == id }) { j.brain.storm.clear(); j.brain.hurry = false } }
        members = [:]; slots = []; committed = []; slotOf = [:]; gatherAt = nil; replans = 0
        if !why.isEmpty { note(why) }
    }

    /// Back to nothing (the app left the room, a scene change, tests).
    func reset() {
        releaseAll(); stormOn = false; peakOn = false; huddleOn = false; firstCloseDone = false; noticer = nil; noticeFace = 0; plan = nil; jellies = []; log = []
        clock = 0; joinClock = 0; replanClock = 0; seenSleep = []
    }

    private func note(_ s: String) { log.append(s); if log.count > 80 { log.removeFirst() } }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
