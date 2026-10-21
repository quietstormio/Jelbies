//
//  AIHub.swift
//  The glue of the on-device AI features, owned by VoiceCoordinator and ticked from it once per fixed step:
//    - the IntentRouter (natural commands, Tier A / Tier B) and the command executor (`execute`), which maps a JellyCommand onto GameCare / brains
//    - the EventLog recorder: edge-detects what happened from state the game already exposes (needs gains, naps, trips, socials, the bath) so no
//      other file has to call `record`
//    - the DiaryBook's daily schedule and the ThoughtLines scheduler (both read-only on the frame loop; model work runs in background Tasks)
//  Brains of Jellies other than Bob are registered by the stage (`register`); Bob's comes with every tick.
//

import Foundation
import Observation
import QuartzCore

@MainActor
@Observable
final class AIHub {
    let log: EventLog
    let diary: DiaryBook
    let thoughts: ThoughtLines
    let router: IntentRouter
    /// Commands waiting to run once the hold is over (one per step, like the reaction queue).
    @ObservationIgnored var commandQueue: [JellyCommand] = []
    /// Jellies asked to sleep: once their sit starts it becomes a nap (`napDue` = seconds left to start sitting).
    @ObservationIgnored private var napWanted: [Int: Float] = [:]
    /// How many naps were forced by a sleep command (tests).
    @ObservationIgnored private(set) var napsStarted = 0
    @ObservationIgnored private var brains: [Int: Weak] = [:]
    private struct Weak { weak var b: BlobBrain? }
    /// Per-Jelly last-seen state for the edge detection.
    private struct Seen {
        var napping = false, stumbling = false, faceplants = 0, socials = 0, bath = false
        var levels: [Float] = [1, 1, 1]
        var gain: [Float] = [0, 0, 0]
        var gainIdle: [Float] = [0, 0, 0]
        var inited = false, brainSeen = false
    }
    @ObservationIgnored private var seen: [Int: Seen] = [:]
    @ObservationIgnored private var bathWas = false
    @ObservationIgnored private var bathTarget = 0
    @ObservationIgnored private var hourT: Double = 0
    @ObservationIgnored private var hour: Double = 12
    /// The clock the diary reads (tests inject).
    @ObservationIgnored var hourNow: () -> Double = { DayClock.shared.hour }
    @ObservationIgnored var nightFactor: () -> Float = { DayClock.shared.nightFactor }
    @ObservationIgnored var morningFactor: () -> Float = { DayClock.shared.morningFactor }
    /// Recording on (off in the motion tests that build a GameCare without wanting a log).
    @ObservationIgnored var recording = true

    nonisolated deinit {}

    /// `persists: false` keeps the log and diary in memory (tests); `model` / `writer` nil = Tier B only.
    init(persists: Bool = true, defaults: UserDefaults = .standard, model: AICommandModel? = nil, writer: AITextWriter? = nil,
         availability: AIAvailability = .shared, now: @escaping () -> Date = Date.init) {
        log = EventLog(defaults: defaults, persists: persists, now: now)
        diary = DiaryBook(defaults: defaults, persists: persists, writer: writer, now: now)
        thoughts = ThoughtLines(writer: writer)
        router = IntentRouter(model: model, availability: availability)
    }

    /// The stage hands over the other Jellies' brains (Bob's arrives with `tick`).
    func register(_ b: BlobBrain, id: Int) { brains[id] = Weak(b: b) }
    func brain(_ id: Int) -> BlobBrain? { brains[id]?.b }

    func catalog(care: GameCare) -> AICatalog {
        AICatalogRegistry.catalog(jellies: care.jellies.map { ($0.id, $0.name) })
    }

    // MARK: tick

    func tick(care: GameCare, bob: BlobBrain, dt: Float, listening: Bool, voiceBusy: Bool) {
        brains[0] = Weak(b: bob)
        let d = Double(dt)
        hourT += d
        if hourT >= 1 { hourT = 0; hour = hourNow() }
        if recording { observe(care: care, dt: dt) }
        driveNaps(dt: dt)
        log.tick(dt: d)
        let roster = care.jellies.map { ($0.id, $0.name) }
        diary.tick(dt: d, hour: hour, log: log, jellies: roster)
        let blocked = listening || voiceBusy || care.bubbleIcon != nil || care.focus.isActive || care.bath.active || care.select.isSelecting || care.greeting
        thoughts.tick(dt: d, moments: moments(care: care), blocked: blocked, roster: roster.map(\.1))
    }

    // MARK: recorder

    private func observe(care: GameCare, dt: Float) {
        // the bath: who was in it when it ended
        let bathOn = care.bath.active
        if bathOn { bathTarget = care.bath.targetID }
        if bathWas, !bathOn { log.record(.bathed, jelly: bathTarget) }
        bathWas = bathOn
        for p in care.jellies {
            var s = seen[p.id] ?? Seen()
            defer { seen[p.id] = s }
            let needs = p.needs
            let lv = NeedKind.allCases.map { needs.level($0) }
            if !s.inited { s.levels = lv; s.inited = true }
            // a need going UP is a meal / a drink / cuddles: one event per sitting (gains are summed until they stop for a few seconds)
            for k in NeedKind.allCases {
                let i = k.rawValue
                let delta = lv[i] - s.levels[i]
                if delta > 0.002 { s.gain[i] += delta; s.gainIdle[i] = 0 } else { s.gainIdle[i] += dt }
                if s.gain[i] > 0.03, s.gainIdle[i] > 6 {
                    switch k {
                    case .hunger: log.record(.ate, jelly: p.id, detail: Consumables.with(id: care.selectedFoodID)?.name ?? "a snack")
                    case .thirst: log.record(.drank, jelly: p.id, detail: Consumables.with(id: care.selectedDrinkID)?.name ?? "water")
                    case .attention: log.record(.cuddled, jelly: p.id)
                    }
                    s.gain[i] = 0
                } else if s.gain[i] <= 0.03, s.gainIdle[i] > 6 { s.gain[i] = 0 }
            }
            s.levels = lv
            guard let b = brain(p.id) else { continue }
            let napping = b.isNapping
            if napping, !s.napping { log.record(.napped, jelly: p.id) }
            s.napping = napping
            let stumbling = b.idleState.kind == .stumble
            if stumbling, !s.stumbling { log.record(.tripped, jelly: p.id) }
            s.stumbling = stumbling
            if !s.brainSeen { s.brainSeen = true; s.faceplants = b.flipFaceplants; s.socials = b.socialStarts.values.reduce(0, +) }
            if b.flipFaceplants > s.faceplants { log.record(.tripped, jelly: p.id, detail: "flip") }
            s.faceplants = b.flipFaceplants
            let socials = b.socialStarts.values.reduce(0, +)
            if socials > s.socials, let kind = b.socialKind {
                let partner = b.socialPartnerID
                if kind == .squabble { log.record(.squabbled, jelly: p.id, partner: partner) }
                else if kind != .look { log.record(.social, jelly: p.id, detail: Self.socialWord(kind), partner: partner) }
                if let q = partner, care.jellies.indices.contains(q), kind != .look {           // the partner's day has it too
                    log.record(kind == .squabble ? .squabbled : .social, jelly: q, detail: kind == .squabble ? nil : Self.socialWord(kind), partner: p.id)
                }
            }
            s.socials = socials
        }
    }
    static func socialWord(_ k: SocialKind) -> String {
        switch k { case .zoomies: return "zoomies"; case .boop: return "booped noses"; case .follow: return "followed"; case .greet: return "said hello"; case .squabble: return "squabbled"; case .look: return "looked" }
    }

    // MARK: moments (thought lines)

    private func moments(care: GameCare) -> [(jelly: Int, moment: ThoughtMoment, name: String)] {
        care.jellies.map { p in
            let b = brain(p.id)
            let per = JellyPersonality.of(name: p.name)
            var scene: ThoughtMoment.Scene = .idle
            if let b, b.isNapping { scene = .napping }
            else if let b, b.idleState.kind == .zoomies || b.zoomW > 0.1 { scene = .zooming }
            else if let b, b.isSocial, b.socialKind != .squabble, b.socialKind != .look { scene = .playing }
            else if p.needs.mood == .grumpy { scene = .grumpy }
            else if let w = p.needs.wantedNeed { scene = w == .hunger ? .hungry : w == .thirst ? .thirsty : .lonely }
            else if let t = log.since(.ate, jelly: p.id), t < 90 { scene = .justAte }
            else if let t = log.since(.bathed, jelly: p.id), t < 120 { scene = .justBathed }
            else if nightFactor() > 0.5 { scene = .night }
            else if morningFactor() > 0.5 { scene = .morning }
            return (p.id, ThoughtMoment(scene: scene, personality: per), p.name)
        }
    }

    // MARK: sleep

    /// Asks Jelly `id` to sleep: his sit is turned into a nap once it starts (the nap is the night sit with eyes closed; nothing new in the body).
    func requestNap(_ id: Int) {
        guard let b = brain(id) else { return }
        if b.idleState.kind == .sit, !b.idleState.yielding { b.napping = true; b.idleState.hold = max(b.idleState.hold, 55); napsStarted += 1; return }
        b.commandedIdle = .sit
        napWanted[id] = 4
    }
    private func driveNaps(dt: Float) {
        for (id, left) in napWanted {
            guard let b = brain(id) else { napWanted[id] = nil; continue }
            if b.idleState.kind == .sit, !b.idleState.yielding {
                b.napping = true
                b.idleState.hold = max(b.idleState.hold, 55)          // 55 s of eyes-closed sitting, like the night nap
                napsStarted += 1
                napWanted[id] = nil
            } else if left - dt <= 0 { napWanted[id] = nil } else { napWanted[id] = left - dt }
        }
    }
}
