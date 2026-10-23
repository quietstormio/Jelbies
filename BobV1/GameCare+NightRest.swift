//
//  GameCare+NightRest.swift
//  Bedtime is the player's call (round 1022): the Jelbies go to bed when told ("goodnight", the group Bedtime button, Siri) or at night after a few
//  minutes with no interaction. The brain never chooses bed itself at night (`BlobBrain.sleepWanted`). This file is the room's bedtime book:
//    - who has been asked to sleep (`wanted`) and is retried until they lie down (so the LAST of three always goes to bed too);
//    - the idle clocks (the whole room, and each Jelbie) that fire the night-idle bedtime and put a Jelbie woken at night back to bed;
//    - waking: one by name / poke wakes only him, "wake up everyone" wakes all, selecting never wakes;
//    - coming back at night after a long time away: already asleep, before the first frame.
//

import Foundation
import simd

enum NightRestTuning {
    /// Seconds at night with no player interaction -> everybody to bed (DEBUG `-NightIdle <s>` overrides).
    nonisolated(unsafe) static var idleBedtime: Float = 180
    /// Seconds without interaction with HIM -> a Jelbie woken at night goes back to bed.
    static let backToBed: Float = 120
    /// Seconds between re-issued bedtimes to a Jelbie who is still up.
    static let retry: Float = 3
    /// Back at night after at least this long away -> already asleep.
    static let awayAsleepAfter: TimeInterval = 300
    /// DayBlend night above this (about 20:35 to 07:10) counts as bedtime hours, as does deep night.
    static let nightEdge: Float = SleepTuning.nightEdge
    /// Sleep hold for a bedtime sleep (the stage-3 morning rule ends it).
    static let untilMorning: Float = 36_000
    nonisolated(unsafe) static var debugLoaded = false
}

struct NightRestBook {
    var roomIdle: Float = 0                    // s since any interaction
    var personal: [Int: Float] = [:]           // s since interaction with that Jelbie
    var wanted: Set<Int> = []                  // ids that should be asleep; retried until napping
    var dayOnce: Set<Int> = []                 // subset of wanted asked by day: dropped once napping (no retry after a later wake)
    var retryT: [Int: Float] = [:]
    var nightWoken: Set<Int> = []              // woken by the player at night: back to bed after `backToBed` idle
    var arrivalAsleep = false                  // set by the away check; applied on the first tick that has actors
    var arrivalIDs: Set<Int> = []              // the ones put down instantly (the curtain waits for them to settle)
    var lastSelected: Int?
    var autoFired = false                      // the idle rule fired for this stretch (re-arms on interaction)
    var debugRead = false
}

extension GameCare {
    // MARK: state read by the buttons

    /// Night enough that nobody chooses bed alone and the idle rule is armed.
    var isBedtimeHours: Bool { DayClock.shared.nightFactor > NightRestTuning.nightEdge || DayClock.shared.deepNightFactor > 0.5 }
    /// A group Bedtime is allowed now (no race / show / meal / clean-up going on).
    var canBedtime: Bool { !raceBusy && !show.active && !trayOut && !bath.active && meal == nil }
    /// Somebody is still on their feet.
    var anyAwake: Bool { raceBook.actors.contains { $0.brain.map { !$0.isSleeping } ?? false } }
    private var presentActorIDs: [Int] { raceBook.actors.filter { $0.brain != nil }.map(\.id) }

    // MARK: going to bed

    /// Everybody to bed (the group Bedtime button, Siri, a plain "goodnight").
    func bedtimeAll() { bedtime(ids: presentActorIDs.isEmpty ? jellies.map(\.id) : presentActorIDs) }

    /// Bedtime for these Jelbies, issued now and retried until they lie down.
    func bedtime(ids: [Int]) {
        guard canBedtime else { return }
        registerBedtime(ids)
        if let f = voice.onGoodnight { f(ids) } else { for id in ids { selectBrain(id)?.commandedGoodnight = true } }
    }

    /// The book-keeping half of a bedtime (the voice path issues the order itself and logs it).
    func registerBedtime(_ ids: [Int]) {
        nightRest.wanted.formUnion(ids)
        if !isBedtimeHours { nightRest.dayOnce.formUnion(ids) }
        for id in ids { nightRest.nightWoken.remove(id); nightRest.retryT[id] = NightRestTuning.retry }
        noteInteraction()
    }

    // MARK: waking

    /// Wake ONLY this Jelbie (a name, a poke). A no-op on an awake one besides the bookkeeping.
    func wakeSleeper(_ id: Int, groggy: Bool = true) {
        if let b = selectBrain(id), b.isSleeping, !b.sleep.wakeAsked {
            b.commandedGoodnight = false
            b.sleepWake(groggy: groggy)
            nightRest.wanted.remove(id); nightRest.dayOnce.remove(id)
            if isBedtimeHours { nightRest.nightWoken.insert(id) }
        }
        noteInteraction(jelly: id)
    }
    /// A deliberate poke on a sleeper (W3 wires the gesture).
    func pokeSleeper(_ id: Int) { wakeSleeper(id, groggy: true) }

    /// "Wake up everyone".
    func wakeAll() {
        nightRest.wanted.removeAll(); nightRest.dayOnce.removeAll()
        for a in raceBook.actors { wakeSleeper(a.id) }
        if isBedtimeHours { nightRest.nightWoken.formUnion(presentActorIDs) }
        noteInteraction()
    }

    /// The player did something: the idle clocks restart (a wanted bedtime stays).
    func noteInteraction(jelly: Int? = nil) {
        nightRest.roomIdle = 0; nightRest.autoFired = false
        if let id = jelly { nightRest.personal[id] = 0 }
    }

    // MARK: away

    /// Back at night after a long time: they are already asleep (applied on the first tick that has bodies). True = handled, no greeting.
    @discardableResult
    func awayBedtime(_ away: TimeInterval) -> Bool {
        #if DEBUG
        let demo = UserDefaults.standard.integer(forKey: "BedtimeAwayDemo") == 1 && !nightRest.debugRead
        if demo { nightRest.debugRead = true }
        #else
        let demo = false
        #endif
        guard demo || (away >= NightRestTuning.awayAsleepAfter && isBedtimeHours), canBedtime else { return false }
        nightRest.arrivalAsleep = true
        LaunchGate.shared.hold(.resume)
        return true
    }

    private func applyArrivalAsleep() {
        let ids = raceBook.actors.sorted { $0.id < $1.id }
        nightRest.arrivalIDs = []
        for a in ids {
            guard let b = a.brain, b.sleepEnabled else { continue }
            b.abortAll(a.sim, a.skinner)
            b.pending = nil
            b.sleepInstant(a.sim, a.skinner)
            nightRest.arrivalIDs.insert(a.id)
            nightRest.wanted.insert(a.id)
        }
        queued = []; greeting = false; greetPending = []
    }

    // MARK: the tick

    func tickNightRest(dt: Float) {
        #if DEBUG
        if !NightRestTuning.debugLoaded {
            NightRestTuning.debugLoaded = true
            if let v = UserDefaults.standard.object(forKey: "NightIdle") as? Double, v > 0 { NightRestTuning.idleBedtime = Float(v) }
        }
        #endif
        let actors = raceBook.actors.filter { $0.brain != nil }
        let ids = actors.map(\.id)
        var book = nightRest
        defer { nightRest = book }
        book.roomIdle += dt
        for id in ids { book.personal[id, default: 0] += dt }
        // busy states restart the clocks: the player is playing with them
        if focus.isActive || focus.phase != .roaming || trayOut || meal != nil || wanted != nil || groupActive || bath.active || tripActive
            || arranging || voice.mode.phase != .idle || select.sheetOpen { book.roomIdle = 0; book.autoFired = false }
        if focus.isActive { for id in focusGroup.ids { book.personal[id] = 0 } }
        if bath.active { book.personal[bath.targetID] = 0 }
        if select.selectedID != book.lastSelected {          // a new highlight is a touch; a highlight that stays keeps nobody awake
            book.lastSelected = select.selectedID
            book.roomIdle = 0; book.autoFired = false
            if let s = select.selectedID { book.personal[s] = 0 }
        }
        // a Jelbie the player woke (a touch, a very loud bang) is not asked back to bed by the retry
        for id in book.wanted {
            if let b = selectBrain(id), b.isSleeping, b.sleep.wakeAsked, b.sleep.groggy {
                book.wanted.remove(id); book.dayOnce.remove(id)
                if isBedtimeHours { book.nightWoken.insert(id) }
                book.personal[id] = 0; book.roomIdle = 0; book.autoFired = false
            }
        }
        if raceBusy || show.active { book.wanted.removeAll(); book.dayOnce.removeAll(); return }
        if book.arrivalAsleep, !actors.isEmpty {
            nightRest = book; applyArrivalAsleep(); book = nightRest
            book.arrivalAsleep = false
        }
        if !book.arrivalIDs.isEmpty {          // the curtain waits for the instant sleepers to settle
            let done = book.arrivalIDs.allSatisfy { id in actors.first { $0.id == id }.map { ($0.brain?.isNapping ?? true) && $0.sim.isSettled } ?? true }
            if done { book.arrivalIDs = []; LaunchGate.shared.settled(true) }
        }
        let night = isBedtimeHours
        if !night {
            book.wanted = book.wanted.intersection(book.dayOnce)
            book.nightWoken = []; book.autoFired = false
            for id in book.dayOnce where selectBrain(id)?.isNapping ?? false { book.dayOnce.remove(id); book.wanted.remove(id) }
        } else {
            if book.roomIdle >= NightRestTuning.idleBedtime, !book.autoFired {
                book.autoFired = true
                let go = ids.filter { !book.nightWoken.contains($0) }
                book.wanted.formUnion(go)
                for id in go { book.retryT[id] = 0 }
            }
            for id in book.nightWoken where (book.personal[id] ?? 0) >= NightRestTuning.backToBed {
                book.nightWoken.remove(id); book.wanted.insert(id); book.retryT[id] = 0
            }
        }
        let held = focus.isActive || focus.phase != .roaming || trayOut || meal != nil || bath.active || groupActive
        for id in book.wanted.sorted() {
            guard let b = selectBrain(id) else { continue }
            if b.isSleeping { if !b.sleep.wakeAsked { book.retryT[id] = 0 }; continue }          // down, on his way, or rolling up: wait
            if b.race.active || b.sleepLocked || b.activity == .touched || b.activity == .recovering || b.reserved || held { continue }
            book.retryT[id, default: 0] -= dt
            if book.retryT[id]! <= 0 { b.commandedGoodnight = true; book.retryT[id] = NightRestTuning.retry }
        }
    }
}
