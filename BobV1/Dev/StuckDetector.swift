//
//  StuckDetector.swift
//  no-stuck-r1 (the owner, 2026-11-24: "Make sure nothing ... can ever get stuck"). DEV BUILDS ONLY (Debug, the simulator, the phone's JELBIES_DEV_ARGS builds; compiled out of the App Store archive).
//  `-StuckProbe 1` (or env STUCK_PROBE=1): once a second of GAME time (the stage's fixed steps: a starved simulator or a backgrounded app does not count) every Jelmiko and the game's holds are checked.
//  Anything that has been wrong for longer than its limit is logged once as
//      [stuck] kind=<kind> who=<id or -> for=<s> <detail>
//  and, when it clears, `[stuck] cleared kind=... who=... after=...`. A summary line every 60 s: `[stuck] summary sim=<s> n=<events> kinds=...`.
//  It only READS the game (the release guard is GameCare+StuckRelease.swift). Kinds:
//    autonomy-off      a Jelmiko with his life switched off while nothing holds him (no close-up, call, trip, meal, bath, welcome, outing, show)
//    motionless        a body that has not moved nor changed what it is doing for `motionlessAfter` s, outside the allow-list (sleep, sit / rest, eating, close-up, trips, bath)
//    commanded-orphan  `commanded` set with no job, nothing pending and no script
//    reserved-orphan   `reserved` set while nothing that reserves bodies is on
//    call-lost         `callRunning` (a Come walk in flight) with no come job anywhere (the night-meal bug)
//    tap-no-effect     a Feed / Water tap that was not refused and put no tray out; a Come here tap that started no call and said nothing
//    meal-lock         the tray / a wanted meal / a group serving on longer than any real meal (`mealLockAge`)
//    focus-approach    the Come walk (`.approaching`) on too long;  focus-leaving: the camera's way out on too long
//    cancel-pill       the Cancel pill (a group action) up too long
//    bath / trip / welcome / outing / social   a hold past its longest legal length
//    audio-silent      music that should be heard is not playing
//

#if DEBUG || JELBIES_DEV_ARGS || targetEnvironment(simulator)
import Foundation
import simd

@MainActor
final class StuckDetector {
    static let shared = StuckDetector()
    nonisolated(unsafe) static var on: Bool = DevArgs.enabled && (UserDefaults.standard.integer(forKey: "StuckProbe") != 0 || ProcessInfo.processInfo.environment["STUCK_PROBE"] != nil)

    struct Finding: Equatable { let kind: String; let who: Int; let limit: Float; let detail: String; var key: String { "\(kind)#\(who)" } }

    // limits (game seconds)
    static let autonomyOffAfter: Float = 8, motionlessAfter: Float = 45, commandedAfter: Float = 15, reservedAfter: Float = 30, callLostAfter: Float = 6
    static let feedTapAfter: Float = 75, comeTapAfter: Float = 6, mealLockAfter: Float = 240, approachAfter: Float = 40, leavingAfter: Float = 12, cancelPillAfter: Float = 150
    static let bathAfter: Float = 420, tripAfter: Float = 1500, welcomeAfter: Float = 180, outingAfter: Float = 120, socialAfter: Float = 240, audioAfter: Float = 25

    private var acc: Float = 0
    private(set) var simTime: Float = 0
    private var age: [String: Float] = [:]
    private var flagged: [String: Finding] = [:]
    private(set) var events: [String: Int] = [:]
    private(set) var log: [String] = []          // (tests read it)
    private var still: [Int: (p: SIMD2<Float>, sig: String, t: Float)] = [:]
    private var lastSummary: Float = 0
    // taps (GameCare calls `noteTap`)
    struct Tap { let what: String; let at: Float; let notice: Int; let msgs: Int }
    private var taps: [Tap] = []
    private var phaseAge: (FocusPhase, Float) = (.roaming, 0)

    func reset() { events = [:]; log = []; simTime = 0; lastSummary = 0; acc = 0; age = [:]; flagged = [:]; still = [:]; taps = []; phaseAge = (.roaming, 0) }

    /// GameCare calls this when the player taps Feed / Water ("feed" / "water") or Come here ("come").
    func noteTap(_ what: String, care: GameCare) {
        guard Self.on else { return }
        taps.append(Tap(what: what, at: simTime, notice: care.noticeSerial, msgs: GameMessageCenter.shared.stuckSerial))
    }

    /// The release guard (GameCare+StuckRelease.swift) let a body go: counted as a bug of its own kind.
    func noteReleased(_ what: String, who: Int) {
        guard Self.on else { return }
        events["released-" + what, default: 0] += 1
        emit(String(format: "[stuck] kind=released-%@ who=%d sim=%.0f", what, who, simTime))
    }

    /// Once per fixed step (GameCare.tick, Jelly 0's stage tick).
    func tick(care: GameCare, dt: Float) {
        guard Self.on else { return }
        simTime += dt; acc += dt
        let p = care.focus.phase
        if p == phaseAge.0 { phaseAge.1 += dt } else { phaseAge = (p, 0) }
        guard acc >= 1 else { return }
        let step = acc; acc = 0
        judge(findings(care: care, step: step), step: step)
        if simTime - lastSummary >= 60 { lastSummary = simTime; emit(String(format: "[stuck] summary sim=%.0f n=%d kinds=%@", simTime, events.values.reduce(0, +), events.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))) }
    }

    private func emit(_ s: String) { NSLog("%@", s); log.append(s); if log.count > 400 { log.removeFirst(100) } }

    private func judge(_ now: [Finding], step: Float) {
        var seen = Set<String>()
        for f in now {
            seen.insert(f.key)
            let a = (age[f.key] ?? 0) + step; age[f.key] = a
            if a >= f.limit, flagged[f.key] == nil {
                flagged[f.key] = f; events[f.kind, default: 0] += 1
                emit(String(format: "[stuck] kind=%@ who=%@ for=%.0f sim=%.0f %@", f.kind, f.who < 0 ? "-" : String(f.who), a, simTime, f.detail))
            }
        }
        for k in Array(age.keys) where !seen.contains(k) {
            if let f = flagged[k] { emit(String(format: "[stuck] cleared kind=%@ who=%@ after=%.0f sim=%.0f", f.kind, f.who < 0 ? "-" : String(f.who), age[k] ?? 0, simTime)) }
            age[k] = nil; flagged[k] = nil
        }
    }

    /// What is wrong right now (the ages are kept by `judge`). `step` = the game seconds since the last call.
    func findings(care c: GameCare, step: Float) -> [Finding] {
        var out: [Finding] = []
        let bodies: [(id: Int, brain: BlobBrain)] = c.raceBook.actors.isEmpty
            ? (0..<max(c.jellies.count, 1)).compactMap { id in c.brainFor(id).map { (id, $0) } }
            : c.raceBook.actors.compactMap { a in a.brain.map { (a.id, $0) } }
        let trip = c.tripActive || c.raceBusy
        let outing = c.outing.running
        let welcome = c.newcomerWelcome != nil
        let homeQuiet = !trip && !outing && !welcome && !c.bath.active && !c.trayOut && !c.groupActive && !c.isPreview && !c.show.onStage && c.focus.phase == .roaming && !c.bedtimeWalking
        func line(_ b: BlobBrain) -> String {
            "scr=\(b.scriptKindName) job=\(b.job == nil ? "-" : "Y") pend=\(b.pending == nil ? 0 : 1) cmd=\(b.commanded ? 1 : 0) res=\(b.reserved ? 1 : 0) auto=\(b.autonomy ? 1 : 0) idle=\(b.idleState.kind?.rawValue ?? "-") act=\(b.activity) sleep=\(b.isSleeping ? 1 : 0) soc=\(b.social == nil ? 0 : 1) pos=\(String(format: "%.2f,%.2f", b.position.x, b.position.y))"
        }
        let game = "ph=\(c.focus.phase) ids=\(c.focusGroup.ids) trip=\(trip ? 1 : 0) tray=\(c.trayOut ? 1 : 0) group=\(c.groupActive ? 1 : 0) bath=\(c.bath.active ? 1 : 0) play=\(c.play.active ? 1 : 0) call=\(c.callRunning ? 1 : 0) queued=\(c.queued.count)"

        for (id, b) in bodies {
            guard b.enabled else { continue }
            let parked = trip || c.tripFrozen(id) || c.parkHides(id)
            // a body whose life is off while nothing holds it
            let guest = id >= c.jellies.count          // (a visiting friend: his walk in / out runs with autonomy off; only `motionless` applies)
            if homeQuiet, !guest, !b.autonomy, !b.isSleeping, b.social == nil, !b.reserved, b.commandedIdle == nil, !b.race.active, !b.volley.active {
                out.append(Finding(kind: "autonomy-off", who: id, limit: Self.autonomyOffAfter, detail: "\(line(b)) | \(game)"))
            }
            if b.commanded, b.job == nil, b.pending == nil, b.scriptIsNone, b.commandedIdle == nil, !trip {
                out.append(Finding(kind: "commanded-orphan", who: id, limit: Self.commandedAfter, detail: "\(line(b)) | \(game)"))
            }
            if b.reserved, homeQuiet, !guest, b.social == nil, !c.play.active {
                out.append(Finding(kind: "reserved-orphan", who: id, limit: Self.reservedAfter, detail: "\(line(b)) | \(game)"))
            }
            if let s = b.social, s.t > Self.socialAfter {
                out.append(Finding(kind: "social", who: id, limit: 0, detail: "age=\(Int(s.t)) \(line(b))"))
            }
            // motionless: the same spot AND the same doing, outside the allow-list
            let sig = "\(b.scriptKindName)|\(b.idleState.kind?.rawValue ?? "-")|\(b.activity)|\(b.job == nil ? 0 : 1)"
            let allowed = parked || b.isSleeping || b.activity == .eating || b.activity == .drinking || c.bath.active || (c.focus.phase == .focused && c.focusGroup.includes(id))
                || [IdleKind.sit, .slump, .sleep, .sway, .decorSit, .window].contains(where: { $0 == b.idleState.kind }) || b.isPerched || c.isPreview
            if let s = still[id], simd_distance(s.p, b.position) < 0.05, s.sig == sig {
                still[id] = (s.p, sig, s.t + step)
                if !allowed { out.append(Finding(kind: "motionless", who: id, limit: Self.motionlessAfter, detail: "\(line(b)) | \(game)")) }
            } else { still[id] = (b.position, sig, 0) }
        }
        // the Come walk's flag with nobody walking it
        if c.callRunning, let b0 = c.brainFor(0), b0.job == nil, b0.pending == nil, !c.queued.contains(where: { if case .come = $0 { return true }; return false }), !b0.isSleeping, !b0.mealWaking {
            out.append(Finding(kind: "call-lost", who: 0, limit: Self.callLostAfter, detail: game))
        }
        // taps that did nothing
        taps.removeAll { t in
            let el = simTime - t.at
            let said = c.noticeSerial != t.notice || GameMessageCenter.shared.stuckSerial != t.msgs
            switch t.what {
            case "come":
                if c.focus.phase != .roaming || said { return true }
                if el >= Self.comeTapAfter { out.append(Finding(kind: "tap-no-effect", who: -1, limit: 0, detail: "come tap \(Int(el)) s ago: nothing | \(game)")); return true }
            default:
                if c.dining.isPresent || said && !c.trayOut { return true }
                if el >= Self.feedTapAfter { out.append(Finding(kind: "tap-no-effect", who: -1, limit: 0, detail: "\(t.what) tap \(Int(el)) s ago: no tray | wanted=\(c.wanted != nil ? 1 : 0) meal=\(c.meal != nil ? 1 : 0) \(game)")); return true }
            }
            return false
        }
        if c.mealLockAge > Self.mealLockAfter { out.append(Finding(kind: "meal-lock", who: -1, limit: 0, detail: "lockAge=\(Int(c.mealLockAge)) tray=\(c.dining.phase) \(game)")) }
        if c.focus.phase == .approaching { out.append(Finding(kind: "focus-approach", who: -1, limit: Self.approachAfter, detail: game)) }
        if c.focus.phase == .leaving { out.append(Finding(kind: "focus-leaving", who: -1, limit: Self.leavingAfter, detail: game)) }
        if c.cancelPill { out.append(Finding(kind: "cancel-pill", who: -1, limit: Self.cancelPillAfter, detail: game)) }
        if c.bath.active { out.append(Finding(kind: "bath", who: -1, limit: Self.bathAfter, detail: game)) }
        if c.tripActive { out.append(Finding(kind: "trip", who: -1, limit: Self.tripAfter, detail: "race=\(c.race.active ? 1 : 0) show=\(c.show.active ? 1 : 0) cafe=\(c.cafe.active ? 1 : 0) park=\(c.park.active ? 1 : 0) groom=\(c.groom.active ? 1 : 0) volley=\(c.volley.active ? 1 : 0)")) }
        if welcome { out.append(Finding(kind: "welcome", who: -1, limit: Self.welcomeAfter, detail: game)) }
        if outing { out.append(Finding(kind: "outing", who: -1, limit: Self.outingAfter, detail: game)) }
        let m = AudioHub.shared.stuckMusicProbe
        if m.wanted, !m.playing { out.append(Finding(kind: "audio-silent", who: -1, limit: Self.audioAfter, detail: m.why)) }
        return out
    }
}
#endif
