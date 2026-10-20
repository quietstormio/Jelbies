//
//  DrillFlow.swift
//  The practice drill "Rhythm Steps" on the race flow's track trip (RaceFlow `kind == .drill`): the same fade, track and body as the race, no rivals.
//
//      fade -> track -> 3-2-1-GO (waits for the music) -> three laps of L / R prompts on the beat grid -> results (+Waddle) -> back home
//
//  Time is the SONG clock: the training music's own position (AVAudioPlayerNode render time), so the prompts never drift from what is heard. When the
//  music is not playing (muted, the tests) the clock counts the sim's fixed steps instead. A hit makes the body take one step of the locked gait (the
//  race's step event); a miss trips him (the race's stumble). Drops are not earned here.
//

import Foundation

/// What the drill view shows (republished only when it changes).
struct DrillUI: Equatable {
    var lap = 1
    var laps = TrainingTuning.laps
    var streak = 0, perfects = 0, goods = 0, misses = 0
    var flash: DrillGrade?
    var flashSerial = 0
    var running = false
}

/// What a finished drill gave.
struct DrillResult: Equatable {
    var accuracy: Float
    var perfects: Int, goods: Int, misses: Int, bestStreak: Int
    var waddleBefore: Float, waddleAfter: Float
    var focusBefore: Float, focusAfter: Float
    var pepLeft: Int
    /// This session was not at full value (the day's Pep was used up).
    var pepSpent: Bool
    var waddleGain: Float { waddleAfter - waddleBefore }
    var focusGain: Float { focusAfter - focusBefore }
}

/// Sound cues of the drill (AudioHub maps them to files; tests count them).
enum DrillCue: Equatable {
    case perfect, good, streak, lap, go, statUp, tired, jingle(win: Bool)
}

/// Run-time state of one drill kept beside the flow.
struct DrillRun {
    var song = TrainingTuning.loopStart
    var audioWait: Float = 0
    var pending: [RaceEvent] = []
    var dipStage = 0                // 0 none, 1 waiting, 2 out, 3 in
    var dipT: Float = 0
    var goAge: Float = 0
    var flashAge: Float = 0
    var autoDone = 0                // prompts the auto-player has handled
    var settledResult = false
    static let dipDelay: Float = 0.7, dipOut: Float = 0.25, dipIn: Float = 0.4
}

extension RaceFlow {
    /// The song time now: the audio clock when it runs, else counted frames.
    private func songNow(dt: Float = 0) -> Double {
        if let a = songClock() { drillState.song = a } else { drillState.song += Double(dt) }
        return drillState.song
    }

    func tickDrill(dt: Float) -> [RaceEvent] {
        guard sim != nil else { return [] }
        let song = songNow(dt: dt)
        var out: [RaceEvent] = drillState.pending
        drillState.pending.removeAll()
        if sim!.phase == .countdown {
            if introT < Self.introPause { introT += dt; return out }
            if !audioReady(), drillState.audioWait < 3 { drillState.audioWait += dt; return out }
            sim!.tick(dt: dt)
            for e in sim!.takeEvents() {
                switch e {
                case .countdown: cueSerial += 1; cue(.countdownBeep)
                case .go: cueSerial += 1; drillCue(.go)
                default: break
                }
            }
            if sim!.phase != .countdown { drill = DrillSim(seed: sim!.seed, songTime: song); publishDrill() }
            refreshUI()
            return out
        }
        guard drill != nil else { return out }
        drillState.goAge += dt
        drillState.flashAge += dt
        if drillState.flashAge > 0.7, drillUI.flash != nil { drillUI.flash = nil }
        tickDip(dt: dt)
        if drillResult == nil {
            if drillAuto { autoPlay(song: song) }
            drill!.tick(songTime: song)
            out += handleDrill(drill!.takeEvents())
            publishDrill()
        } else {
            cardAge += dt
            if let a = autoReturnAfter, cardAge >= a { goHome() }
        }
        refreshUI()
        return out
    }

    /// A tap of the foot button during the drill.
    func drillTap(foot: Int) {
        guard kind == .drill, drill != nil, drillResult == nil, wipe == 0 else { return }
        let song = songClock() ?? drillState.song
        drillState.song = max(drillState.song, song)
        drill!.tap(foot: foot, at: drillState.song)
        drillState.pending += handleDrill(drill!.takeEvents())
        publishDrill()
    }

    /// Plays the drill for him: every prompt tapped on the beat, except a few (a late good one, a missed one) so the screen shows all the grades.
    private func autoPlay(song: Double) {
        guard drill != nil else { return }
        while drillState.autoDone < drill!.total {
            let p = drill!.prompts[drillState.autoDone]
            let late: Double = drillState.autoDone % 5 == 3 ? 0.09 : (drillState.autoDone % 7 == 4 ? 0.01 : 0.0)
            let at = p.time + TrainingTuning.latencyOffset + late
            if at > song { break }
            drillState.autoDone += 1
            if drillState.autoDone % 11 == 6 { continue }           // not tapped: a miss
            drill!.tap(foot: p.foot, at: at)
        }
    }

    private func handleDrill(_ events: [DrillEvent]) -> [RaceEvent] {
        var out: [RaceEvent] = []
        let w = sim?.racers[0].stats.waddle ?? 0.5
        for e in events {
            switch e {
            case .hit(_, let foot, let grade):
                out.append(.step(racer: 0, foot: foot, stride: RaceTuning.stride(waddle: w), rate: RaceTuning.maxRate(waddle: w), final: false))
                drillUI.flash = grade; drillUI.flashSerial += 1; drillState.flashAge = 0
                drillCue(grade == .perfect ? .perfect : .good)
            case .miss:
                out.append(.stumble(racer: 0))
                drillUI.flash = .miss; drillUI.flashSerial += 1; drillState.flashAge = 0
            case .streak: drillCue(.streak)
            case .lapEnd(let lap):
                if lap < TrainingTuning.laps, drillState.dipStage == 0 { drillState.dipStage = 1; drillState.dipT = 0 }
            case .lapStart: drillCue(.lap)
            case .finished: finishDrill()
            case .stray: break
            }
        }
        return out
    }

    private func publishDrill() {
        guard let d = drill else { return }
        var u = drillUI
        u.lap = d.lap; u.streak = d.streak; u.perfects = d.perfects; u.goods = d.goods; u.misses = d.misses; u.running = drillResult == nil
        if u != drillUI { drillUI = u }
    }

    private func tickDip(dt: Float) {
        switch drillState.dipStage {
        case 1:
            drillState.dipT += dt
            if drillState.dipT >= DrillRun.dipDelay { drillState.dipStage = 2; drillState.dipT = 0 }
        case 2:
            drillState.dipT += dt
            dip = min(1, drillState.dipT / DrillRun.dipOut)
            if dip >= 1 { onLapReset(); drillState.dipStage = 3; drillState.dipT = 0 }
        case 3:
            drillState.dipT += dt
            dip = max(0, 1 - drillState.dipT / DrillRun.dipIn)
            if dip <= 0 { drillState.dipStage = 0 }
        default: break
        }
    }

    /// The last prompt is judged: the gain goes onto the stats once.
    private func finishDrill() {
        guard !drillState.settledResult, let d = drill, let st = stats else { return }
        drillState.settledResult = true
        let before = (st.waddle, st.focus)
        let spent = st.pepFactor < 1
        let gain = st.finishPractice(accuracy: d.accuracy, steadiness: d.steadiness)
        drillResult = DrillResult(accuracy: d.accuracy, perfects: d.perfects, goods: d.goods, misses: d.misses, bestStreak: d.bestStreak,
                                  waddleBefore: before.0, waddleAfter: before.0 + gain.waddle, focusBefore: before.1, focusAfter: before.1 + gain.focus,
                                  pepLeft: st.pepLeft, pepSpent: spent)
        waddleGain = gain.waddle
        cardAge = 0
        cueSerial += 1
        drillCue(d.accuracy >= 0.5 ? .statUp : .tired)
        drillCue(.jingle(win: d.accuracy >= 0.5))
        publishDrill()
    }
}
