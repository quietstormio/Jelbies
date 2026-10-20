//
//  MusicDirector.swift
//  What music plays when: a pure state machine (no players, no clock). The audio engine feeds it dt + the situation each frame and carries out
//  the events it returns. Rules:
//    - day / morning: the day playlist, shuffled, no repeat until all five have played;
//    - evening (17-21): evening_1 first, then day tracks at a lower volume; night (21-6): the lo-fi playlist;
//    - every Jelly napping: lo-fi at any hour (quiet), back to the time-of-day music once one wakes;
//    - after every 1 or 2 tracks a 30...90 s gap where only the room ambience plays; tracks crossfade over `fade` seconds;
//    - play layer (lofi_play): fades in ~1 s when the Jellies play / zoom, fades out 8...10 s after it calms; 2 min cooldown;
//      never at night (night only lifts the music volume a little while they play).
//    - screens: a `scene` (race, the final stretch, training, shop, town; Audio/SceneMusic.swift) fades the room music and the play layer out and plays
//      the scene's own track (crossfading between scenes); `results` is silence (a jingle plays); back to `none` the room music crossfades in again.
//

import Foundation

nonisolated enum MusicTrack: String, CaseIterable, Sendable {
    case day1 = "day_1", day2 = "day_2", day3 = "day_3", day4 = "day_4", day5 = "day_5"
    case evening1 = "evening_1"
    case night1 = "night_1", night2 = "night_2", night3 = "night_3"
    case lofiPlay = "lofi_play"

    static let dayPool: [MusicTrack] = [.day1, .day2, .day3, .day4, .day5]
    static let lofiPool: [MusicTrack] = [.night1, .night2, .night3]
}

nonisolated enum MusicMode: Equatable, Sendable {
    case day, evening, night, nap
    var usesLofi: Bool { self == .night || self == .nap }
}

nonisolated struct MusicInput: Equatable, Sendable {
    var phase: DayPhase = .day
    var allNapping = false
    var playing = false
    /// What the screen in front wants (race / training / shop / town); `.none` = the room.
    var scene: MusicScene = .none
}

nonisolated enum MusicEvent: Equatable, Sendable {
    case playTrack(MusicTrack, fade: Double)
    case fadeOutMain(fade: Double)
    case layerOn(fade: Double)
    case layerOff(fade: Double)
    /// A screen's own track starts (fading in; the others fade out) / stops.
    case sceneOn(SceneTrack, fade: Double)
    case sceneOff(fade: Double)
}

nonisolated struct MusicDirector {
    var fade = 3.0
    var length: (MusicTrack) -> Double
    var rand: () -> Double
    /// Mode switches wait at least this long after the last one (a time-lapse or a Jelly waking and napping again must not flap the music).
    var minDwell = 5.0
    static let gapRange: ClosedRange<Double> = 30...90
    static let layerRelease: ClosedRange<Double> = 8...10
    static let layerCooldown = 120.0
    static let layerFadeIn = 1.0, layerFadeOut = 3.0

    private(set) var mode: MusicMode = .day
    private(set) var current: MusicTrack?
    private(set) var elapsed = 0.0
    private(set) var gapLeft: Double?
    private(set) var gapLength = 0.0
    private(set) var tracksSincePause = 0
    private(set) var tracksBeforeGap = 1
    private(set) var layerOn = false
    /// The screen scene that is playing (`.none` = the room's own music).
    private(set) var scene: MusicScene = .none
    static let sceneFade = 1.2
    private(set) var cooldownLeft = 0.0
    private var calm = 0.0
    private var release = 9.0
    private var dwell = 100.0
    private var started = false
    private var eveningIntro = true
    private var bag: [MusicTrack] = []
    private(set) var lastPlayed: MusicTrack?
    private(set) var played: [MusicTrack] = []

    init(length: @escaping (MusicTrack) -> Double = { _ in 90 }, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.length = length; self.rand = rand
    }

    static func mode(for input: MusicInput) -> MusicMode {
        if input.allNapping { return .nap }
        switch input.phase { case .morning, .day: return .day; case .evening: return .evening; case .night: return .night }
    }

    /// Volume of the main music for the situation (evening is quieter, the nap lo-fi is quiet, play at night lifts a little).
    func mainGain(playing: Bool = false) -> Double {
        var g: Double
        switch mode { case .day: g = 1; case .evening: g = 0.7; case .night: g = 0.75; case .nap: g = 0.5 }
        if mode == .night, playing { g *= 1.18 }
        if layerOn { g *= 0.12 }          // the play layer takes over; the playlist waits underneath
        return g
    }
    var layerGain: Double { layerOn ? 1 : 0 }

    private mutating func nextTrack() -> MusicTrack {
        if mode == .evening, eveningIntro { eveningIntro = false; lastPlayed = .evening1; return .evening1 }
        let pool = mode.usesLofi ? MusicTrack.lofiPool : MusicTrack.dayPool
        bag.removeAll { !pool.contains($0) }
        if bag.isEmpty {
            var b = pool
            for i in stride(from: b.count - 1, to: 0, by: -1) { b.swapAt(i, Int(rand() * Double(i + 1)) % (i + 1)) }
            if b.count > 1, b[0] == lastPlayed { b.swapAt(0, b.count - 1) }
            bag = b
        }
        let t = bag.removeFirst()
        lastPlayed = t
        return t
    }

    private mutating func startNext(_ ev: inout [MusicEvent], fade f: Double? = nil) {
        let t = nextTrack()
        current = t; elapsed = 0; gapLeft = nil
        played.append(t)
        ev.append(.playTrack(t, fade: f ?? fade))
    }

    /// Back from the background / an interruption. The gap clock froze while away, so a return mid-gap would give up to 90 s of silence: start the
    /// next track now (fading in over `fade`). Also when the room's music should be playing but no deck actually is (`deckPlaying` false).
    /// Does nothing while a screen's scene music is up (the hub re-checks the scene engine itself).
    mutating func resumed(deckPlaying: Bool, fade f: Double = 1.5) -> [MusicEvent] {
        guard started, scene == .none else { return [] }
        guard gapLeft != nil || !deckPlaying else { return [] }
        var ev: [MusicEvent] = []
        pickGapPlan()
        tracksSincePause = 0
        startNext(&ev, fade: f)
        return ev
    }

    /// Test seam: be in an ambience-only gap of `length` seconds.
    mutating func forceGap(_ length: Double) {
        guard started, scene == .none else { return }
        current = nil; gapLength = length; gapLeft = length
    }

    private mutating func pickGapPlan() {
        tracksBeforeGap = rand() < 0.5 ? 1 : 2
    }

    mutating func update(dt: Double, input: MusicInput) -> [MusicEvent] {
        var ev: [MusicEvent] = []
        dwell += dt
        cooldownLeft = max(0, cooldownLeft - dt)

        // screens
        if input.scene != scene {
            let old = scene
            scene = input.scene
            if old == .none {                       // leaving the room: its music and the play layer fade out
                ev.append(.fadeOutMain(fade: Self.sceneFade))
                if layerOn { layerOn = false; cooldownLeft = Self.layerCooldown; ev.append(.layerOff(fade: Self.sceneFade)) }
                current = nil; gapLeft = nil; tracksSincePause = 0
            }
            if let t = scene.track { ev.append(.sceneOn(t, fade: old == .none ? Self.sceneFade : 0.8)) }
            else if scene == .results { ev.append(.sceneOff(fade: 0.5)) }
            else {                                  // back in the room
                ev.append(.sceneOff(fade: Self.sceneFade))
                started = true; dwell = 0
                mode = Self.mode(for: input)
                if mode == .evening { eveningIntro = true }
                pickGapPlan()
                startNext(&ev)
            }
        }
        if scene != .none { return ev }          // a screen's music plays: no playlist, no play layer

        // mode
        let want = Self.mode(for: input)
        if !started {
            started = true
            mode = want
            if want == .evening { eveningIntro = true }
            pickGapPlan()
            startNext(&ev)
        } else if want != mode, dwell >= minDwell {
            if want == .evening { eveningIntro = true }
            mode = want; dwell = 0
            tracksSincePause = 0
            startNext(&ev)               // crossfade straight into the new mood's music (also ends a gap)
        }

        // playlist
        elapsed += dt
        if var g = gapLeft {
            g -= dt
            if g <= 0 { gapLeft = nil; pickGapPlan(); startNext(&ev) } else { gapLeft = g }
        } else if let cur = current, elapsed >= max(length(cur) - fade, 0.1) {
            tracksSincePause += 1
            if tracksSincePause >= tracksBeforeGap {
                tracksSincePause = 0
                ev.append(.fadeOutMain(fade: fade))
                current = nil
                gapLength = Self.gapRange.lowerBound + rand() * (Self.gapRange.upperBound - Self.gapRange.lowerBound)
                gapLeft = gapLength
            } else {
                startNext(&ev)
            }
        }

        // play layer
        let night = mode.usesLofi
        if layerOn {
            calm = input.playing ? 0 : calm + dt
            if night || calm >= release {
                layerOn = false; cooldownLeft = Self.layerCooldown
                ev.append(.layerOff(fade: Self.layerFadeOut))
            }
        } else if input.playing && !night && cooldownLeft <= 0 {
            layerOn = true; calm = 0
            release = Self.layerRelease.lowerBound + rand() * (Self.layerRelease.upperBound - Self.layerRelease.lowerBound)
            ev.append(.layerOn(fade: Self.layerFadeIn))
        }
        return ev
    }
}
