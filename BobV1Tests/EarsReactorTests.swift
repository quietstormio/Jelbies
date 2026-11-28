//
//  EarsReactorTests.swift
//  The sound reactions on headless rigs: the locks (meal, bath, voice, training, race block everything; the close-up allows only the small ones),
//  the GameCare -> Locks mapping, clap -> the nearest comes (hurry), double clap -> everyone, laugh -> giggle, bark -> startle, meow -> curious,
//  sleepers only stir (a very loud bang wakes them), the dance bounce lands ON the beat (squash minima at the beat times), the stream -> host
//  clock, and the DSP-only pipeline's beat on a click track, converted to host time, lines up with the clicks.
//

import XCTest
import AVFoundation
import simd
@testable import BobV1

@MainActor
final class EarsReactorTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    @MainActor final class Room {
        let rigs: [MotionRig]
        let reactor = EarsReactor()
        var came: [Int] = []
        var everyone = 0
        var dances: [Bool] = []
        var jellies: [EarsReactor.Jelly] { rigs.enumerated().map { EarsReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) } }
        var now: Double = 0
        init(count: Int = 2) {
            rigs = (0..<count).map { _ in MotionRig(game: true) }
            for (i, r) in rigs.enumerated() {
                r.brain.seed = 11 + UInt64(i); r.brain.amplitude = 1
                if i > 0 { r.sim.shift(byXZ: SIMD2(Float(i) * 1.2, Float(i) * 0.8)); r.brain.currentPose(r.sim) }
            }
            reactor.comeHere = { [unowned self] id in came.append(id); rigs[id].brain.requestNow(.come(to: SIMD2(0, 1.4))) }
            reactor.comeEveryone = { [unowned self] in everyone += 1 }
            reactor.onDance = { [unowned self] on in dances.append(on) }
        }
        func handle(_ e: EarEvent) { reactor.handle(e, jellies: jellies, now: now) }
        /// `brains: false` leaves the brains alone (a faked nap would end on the first brain tick): only time and the reactor move.
        func run(_ seconds: Double, brains: Bool = true, each: (() -> Void)? = nil) {
            let js = jellies
            for _ in 0..<Int(seconds * 60) {
                if brains { for r in rigs { r.tick() } }
                now += 1.0 / 60
                reactor.tick(jellies: js, dt: 1.0 / 60, now: now)
                each?()
            }
        }
        func nap(_ i: Int) { let b = rigs[i].brain; b.idleState.kind = .sleep; b.sleep.stage = 3; b.sleep.wakeAsked = false }
    }

    // MARK: locks

    func testEveryBlockingLockStopsAClapAndTheCloseUpAllowsOnlySmallReactions() {
        let room = Room(count: 1); Self.keep.append(room)
        for set in [{ (l: inout EarsReactor.Locks) in l.meal = true }, { $0.bath = true }, { $0.voice = true }, { $0.training = true }, { $0.focusApproach = true }] {
            var l = EarsReactor.Locks(); set(&l)
            XCTAssertTrue(l.blocksAll)
            room.reactor.locks = l
            room.handle(.heard(.clap)); room.handle(.musicStarted(nil)); room.handle(.heard(.laugh))
            XCTAssertNil(room.reactor.anim(of: 0), "\(l): nothing")
            XCTAssertFalse(room.reactor.isDancing)
        }
        XCTAssertEqual(room.came, [])
        // the close-up: a clap gives a giggle, never a come; no dance; a laugh still giggles
        var l = EarsReactor.Locks(); l.focus = true
        XCTAssertFalse(l.blocksAll); XCTAssertTrue(l.blocksBig)
        room.reactor.locks = l
        room.handle(.heard(.clap))
        XCTAssertEqual(room.reactor.anim(of: 0), .giggle)
        XCTAssertEqual(room.came, [])
        room.handle(.musicStarted(nil))
        XCTAssertFalse(room.reactor.isDancing)
        // the race lock is read live
        room.run(1.5)                                   // the giggle is over
        XCTAssertNil(room.reactor.anim(of: 0))
        room.reactor.locks = EarsReactor.Locks()
        var racing = true
        room.reactor.extraLock = { racing }
        room.handle(.heard(.laugh)); room.handle(.heard(.clap)); room.handle(.musicStarted(nil))
        XCTAssertTrue(room.reactor.locks.race); XCTAssertTrue(room.reactor.locks.blocksAll)
        XCTAssertNil(room.reactor.anim(of: 0)); XCTAssertFalse(room.reactor.isDancing); XCTAssertEqual(room.came, [])
        racing = false
        room.handle(.heard(.laugh))
        XCTAssertEqual(room.reactor.anim(of: 0), .giggle)
    }

    func testGameCareMapsToLocks() {
        let care = GameCare(jellyCount: 3, persistent: false)
        let reactor = EarsReactor()
        Self.keep += [care, reactor]
        reactor.update(care: care)
        XCTAssertEqual(reactor.locks, EarsReactor.Locks(), "a quiet room: no locks")
        // a meal (the tray is reserved as soon as food is picked)
        care.feed("berries")
        reactor.update(care: care)
        XCTAssertTrue(reactor.locks.meal); XCTAssertTrue(reactor.locks.blocksAll)
        care.release()
        // the close-up: approaching blocks everything, the settled close-up only the big ones
        let care2 = GameCare(jellyCount: 1, persistent: false)
        Self.keep.append(care2)
        care2.call()
        reactor.update(care: care2)
        XCTAssertTrue(reactor.locks.focus)
        XCTAssertEqual(reactor.locks.focusApproach, care2.focus.phase == .approaching)
        // the voice: the mic open
        let care3 = GameCare(jellyCount: 1, persistent: false)
        Self.keep.append(care3)
        _ = care3.voice.mode.begin()
        reactor.update(care: care3)
        XCTAssertTrue(reactor.locks.voice)
        // the race, from outside (and from GameCare's race wait)
        reactor.extraLock = { true }
        reactor.update(care: care)
        XCTAssertTrue(reactor.locks.race)
        reactor.extraLock = { false }
        care.raceWait = RaceWait(id: 0)
        reactor.update(care: care)
        XCTAssertTrue(reactor.locks.race)
        care.raceWait = nil
        reactor.update(care: care)
        XCTAssertFalse(reactor.locks.race)
    }

    // MARK: reactions

    func testAReservedJellyWaitsForHisMealAndNeverReacts() {
        let room = Room(count: 2); Self.keep.append(room)
        room.rigs[0].brain.reserved = true
        room.handle(.heard(.clap))
        XCTAssertNil(room.reactor.anim(of: 0)); XCTAssertEqual(room.reactor.anim(of: 1), .perk)
        XCTAssertEqual(room.came, [1], "the free one comes")
        room.handle(.musicStarted(EarBeat(bpm: 120, anchor: room.now, strength: 3)))
        XCTAssertFalse(room.rigs[0].brain.ears.dancing); XCTAssertTrue(room.rigs[1].brain.ears.dancing)
        // idleBlocked alone (the close-up sets it on everybody) is not a reservation: in the close-up a clap still gives the giggle
        room.run(2.0)
        room.rigs[1].brain.idleBlocked = true
        room.reactor.locks = { var l = EarsReactor.Locks(); l.focus = true; return l }()
        room.handle(.heard(.clap))
        XCTAssertNil(room.reactor.anim(of: 1), "a dancer keeps dancing: no giggle (ears-dance-r2)")
        room.handle(.musicStopped); room.run(EarsDance.tail + 0.5); room.handle(.heard(.clap))
        XCTAssertEqual(room.reactor.anim(of: 1), .giggle, "idleBlocked in the close-up still giggles once the dance is over")
        XCTAssertNil(room.reactor.anim(of: 0), "reserved never reacts")
    }

    func testClapBringsTheNearestOneHurryingAndADoubleClapEveryone() {
        let room = Room(count: 2); Self.keep.append(room)
        room.handle(.heard(.clap))
        XCTAssertEqual(room.came.count, 1)
        let near = room.came[0]
        XCTAssertTrue(room.rigs[near].brain.hurry, "he hurries (run blend)")
        XCTAssertEqual(room.reactor.anim(of: 0), .perk); XCTAssertEqual(room.reactor.anim(of: 1), .perk)
        room.run(1.5)
        XCTAssertNil(room.reactor.anim(of: 0), "the perk is over")
        room.handle(.doubleClap)
        XCTAssertEqual(room.everyone, 1)
        XCTAssertTrue(room.rigs.allSatisfy { $0.brain.hurry })
    }

    func testADoubleClapWithASleeperPresentBringsOnlyTheNearestAwakeOne() {
        let room = Room(count: 2); Self.keep.append(room)
        room.nap(1)
        XCTAssertTrue(room.rigs[1].brain.isNapping)
        room.handle(.doubleClap)
        XCTAssertEqual(room.everyone, 0, "not comeEveryone: that would wake the sleeper")
        XCTAssertEqual(room.came, [0], "exactly one came: the awake one")
        XCTAssertEqual(room.reactor.anim(of: 1), .stir, "the sleeper only stirs")
        XCTAssertFalse(room.rigs[1].brain.sleep.wakeAsked)
    }

    func testLaughGigglesBarkStartlesMeowIsCuriousWhistleTiltsThenComes() {
        let room = Room(count: 1); Self.keep.append(room)
        room.handle(.heard(.laugh))
        XCTAssertEqual(room.reactor.anim(of: 0), .giggle)
        XCTAssertEqual(room.rigs[0].brain.expr.kind, .joyArc, "the giggle shows on the face (liveliness expression layer)")
        var sq: Float = 1
        room.run(0.4) { sq = min(sq, room.rigs[0].brain.ears.squash) }
        XCTAssertLessThan(sq, 0.97, "the giggle bounces")
        room.run(1.0)
        XCTAssertNil(room.reactor.anim(of: 0))
        room.handle(.heard(.dogBark))
        XCTAssertEqual(room.reactor.anim(of: 0), .startle(level: 0.5))
        XCTAssertEqual(room.rigs[0].brain.expr.kind, .surprised, "a bark: wide eyes")
        var flinch: Float = 1, hopped = false
        room.run(0.5) { flinch = min(flinch, room.rigs[0].brain.ears.squash); if case .hopPlay = room.rigs[0].brain.script { hopped = true } }
        XCTAssertLessThan(flinch, 0.9, "the flinch squashes him")
        XCTAssertTrue(hopped, "a startled hop")
        room.run(2.5)
        room.handle(.heard(.catMeow))
        XCTAssertEqual(room.reactor.anim(of: 0), .curious)
        var roll: Float = 0
        room.run(0.8) { roll = max(roll, abs(room.rigs[0].brain.ears.roll)) }
        XCTAssertGreaterThan(roll, 0.03, "the curious head tilt")
        room.run(1.5)
        room.handle(.heard(.whistle))
        XCTAssertEqual(room.reactor.anim(of: 0), .tilt)
        XCTAssertEqual(room.came.count, 0)
        room.run(3.0)
        XCTAssertEqual(room.came.count, 1, "after the tilt he comes")
    }

    func testSleepersOnlyStirUnlessItIsVeryLoud() {
        let room = Room(count: 2); Self.keep.append(room)
        room.nap(1)
        XCTAssertTrue(room.rigs[1].brain.isNapping)
        room.handle(.heard(.clap))
        XCTAssertEqual(room.reactor.anim(of: 1), .stir)
        XCTAssertEqual(room.came, [0], "the awake one comes, not the sleeper")
        room.run(1.2, brains: false)
        room.handle(.heard(.laugh))
        XCTAssertEqual(room.reactor.anim(of: 1), .stir)
        XCTAssertEqual(room.reactor.anim(of: 0), .giggle)
        room.handle(.musicStarted(EarBeat(bpm: 120, anchor: room.now, strength: 3)))
        XCTAssertTrue(room.reactor.isDancing)
        XCTAssertFalse(room.rigs[1].brain.ears.dancing || room.reactor.anim(of: 1) != .stir, "the sleeper is not pulled into the dance")
        room.run(1.2, brains: false)
        room.handle(.bang(level: 0.4))
        XCTAssertEqual(room.reactor.anim(of: 1), .stir, "a modest bang: a stir")
        room.run(1.0, brains: false)
        room.handle(.bang(level: 0.9))
        XCTAssertEqual(room.reactor.anim(of: 1), .stir, "a loud bang (0.9) is still only a stir: only a VERY loud one wakes a sleeper")
        XCTAssertFalse(room.rigs[1].brain.sleep.wakeAsked)
        room.run(1.0, brains: false)
        room.handle(.bang(level: 0.95))
        XCTAssertEqual(room.reactor.anim(of: 1), .startle(level: 0.95), "a very loud bang wakes him")
        XCTAssertTrue(room.rigs[1].brain.sleep.wakeAsked)
        XCTAssertFalse(room.rigs[1].brain.isNapping)
    }

    // MARK: the dance

    /// The Music Ears dance (ears-sway-r1): they walk to a row facing the camera, spaced well apart, and sway on the beat with one smooth move.
    func testDanceWalksToTheRowFacesFrontSwaysOnTheBeatAndEndsAfterTheMusic() {
        let room = Room(count: 2); Self.keep.append(room)
        room.reactor.rowWaitRange = 1...1; room.reactor.routinesOn = false          // (ears-dance-r2: the walk to the row follows the sway in place; the routines have their own tests)
        let bpm: Float = 120, anchor = room.now + 0.3
        room.handle(.musicStarted(EarBeat(bpm: bpm, anchor: anchor, strength: 3)))
        XCTAssertTrue(room.reactor.isDancing)
        XCTAssertEqual(room.dances, [true])
        var rollStep: Float = 0, sqStep: Float = 0
        var prev: [(r: Float, s: Float)] = room.rigs.map { _ in (0, 1) }
        var trace: [(t: Double, sq: Float)] = []
        room.run(16) {
            for (i, r) in room.rigs.enumerated() {
                let e = r.brain.ears
                rollStep = max(rollStep, abs(e.roll - prev[i].r)); sqStep = max(sqStep, abs(e.squash - prev[i].s))
                prev[i] = (e.roll, e.squash)
            }
            trace.append((room.now, room.rigs[0].brain.ears.squash))
        }
        // the row: both stand on their spots, well apart, facing the camera
        let spots = room.reactor.rows.values.compactMap(\.spot)
        XCTAssertEqual(spots.count, 2, "a row of two: \(room.reactor.log)")
        for (i, r) in room.rigs.enumerated() {
            let st = room.reactor.rows[i]
            XCTAssertEqual(st?.phase, .swaying, "dancer \(i) in his place: \(room.reactor.log)")
            if let sp = st?.spot { XCTAssertLessThan(simd_distance(GameCare.floorPos(r.brain, r.sim), sp), 0.45, "dancer \(i) stands on his spot") }
            XCTAssertLessThan(abs(wrapAngle(r.brain.yaw - r.brain.faceCameraYaw())), 0.5, "dancer \(i) faces the camera")
        }
        let apart = simd_distance(GameCare.floorPos(room.rigs[0].brain, room.rigs[0].sim), GameCare.floorPos(room.rigs[1].brain, room.rigs[1].sim))
        XCTAssertGreaterThanOrEqual(apart, EarsRow.minGap - 0.05, "spaced well apart")
        // one smooth move: no pop (the old dance flipped the sway side in one frame: 0.2 rad)
        XCTAssertLessThan(rollStep, 0.016, "roll step per frame")
        XCTAssertLessThan(sqStep, 0.01, "squash step per frame")
        // the bob is lowest at the sway's extremes, which sit on the beat grid (every 2nd beat at 120 BPM: a side change per second)
        var minima: [Double] = []
        for i in 1..<(trace.count - 1) where trace[i].t > room.now - 6 && trace[i].sq < trace[i - 1].sq && trace[i].sq <= trace[i + 1].sq && trace[i].sq < 0.97 { minima.append(trace[i].t) }
        XCTAssertGreaterThanOrEqual(minima.count, 4, "a bob per side change: \(minima)")
        let period = 60.0 / Double(bpm)
        for m in minima {
            let off = ((m - anchor) / period).rounded() * period + anchor
            XCTAssertEqual(m, off, accuracy: 0.05, "bob at \(m) is off the beat at \(off)")
        }
        XCTAssertFalse(room.reactor.log.contains { $0.hasPrefix("hop") || $0.hasPrefix("spin") }, "no hops or twirls: \(room.reactor.log)")
        // the music stops: the dance tails off and clears the pose
        room.handle(.musicStopped)
        room.run(0.5)
        XCTAssertTrue(room.reactor.isDancing, "still dancing through the tail")
        room.run(EarsDance.tail + 0.6)
        XCTAssertFalse(room.reactor.isDancing)
        XCTAssertEqual(room.dances, [true, false])
        for r in room.rigs { XCTAssertTrue(r.brain.ears.isNeutral, "pose back to neutral: \(r.brain.ears)"); XCTAssertFalse(r.brain.earsActive) }
        XCTAssertTrue(room.reactor.rows.isEmpty)
    }

    /// A wrong estimate (a half-beat flip), a new anchor, a new tempo and a lost beat never pop the sway.
    func testSwayNeverPopsAtReanchorsTempoChangesOrALostBeat() {
        let room = Room(count: 1); Self.keep.append(room)
        room.handle(.musicStarted(EarBeat(bpm: 100, anchor: room.now, strength: 3)))
        var rollStep: Float = 0, sqStep: Float = 0, rollMax: Float = 0
        var prev: (r: Float, s: Float) = (0, 1)
        func watch() {
            let e = room.rigs[0].brain.ears
            rollStep = max(rollStep, abs(e.roll - prev.r)); sqStep = max(sqStep, abs(e.squash - prev.s)); prev = (e.roll, e.squash); rollMax = max(rollMax, abs(e.roll))
        }
        room.run(8, each: watch)
        let p = 0.6
        room.handle(.musicBeat(EarBeat(bpm: 100, anchor: room.now + p / 2, strength: 3))); room.run(1, each: watch)          // one half-beat flip
        room.handle(.musicBeat(EarBeat(bpm: 100, anchor: room.now, strength: 3))); room.run(1, each: watch)
        room.handle(.musicBeat(EarBeat(bpm: 200, anchor: room.now, strength: 3))); room.run(1, each: watch)          // the octave
        room.handle(.musicBeat(EarBeat(bpm: 130, anchor: room.now + 0.1, strength: 3))); room.run(1, each: watch)
        room.handle(.musicBeatLost); room.run(4, each: watch)                                                           // lost: the sway goes on
        let before = rollMax; rollMax = 0
        room.run(3, each: watch)
        XCTAssertGreaterThan(rollMax, 0.08, "still swaying with no beat (it coasts): was \(before)")
        XCTAssertLessThan(rollStep, 0.016, "roll step per frame")
        XCTAssertLessThan(sqStep, 0.01, "squash step per frame")
        XCTAssertTrue(room.reactor.isDancing)
    }

    /// The row: spaced apart, on free floor, never overlapping the furniture.
    func testTheRowIsSpacedWellApartAndOnFreeFloor() {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956); GameCamera.aspect = 440.0 / 956.0
        defer { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
        for n in 1...3 {
            let ps = EarsRow.gameSpots(count: n, resolver: nil)
            XCTAssertEqual(ps.count, n, "a row for \(n)")
            for p in ps { XCTAssertTrue(FreeFloor.isFree(p, radius: EarsRow.bodyRadius), "\(p) is clear of the furniture") }
            for i in 0..<ps.count { for j in (i + 1)..<max(ps.count, i + 1) { XCTAssertGreaterThanOrEqual(simd_distance(ps[i], ps[j]), EarsRow.minGap) } }
            XCTAssertTrue(ps.allSatisfy { $0.y == ps[0].y }, "abreast")
        }
        // something in the way: the row slides or goes back, still apart
        let blocked = EarsRow.spots(count: 3, free: { abs($0.x) > 0.9 || $0.y > 1.7 ? true : simd_length($0 - SIMD2(0, 1.6)) > 0.8 && abs($0.x) > 0.9 }, halfWidth: { _ in 3 })
        XCTAssertEqual(blocked.count, 3)
        for i in 0..<3 { for j in (i + 1)..<3 { XCTAssertGreaterThanOrEqual(simd_distance(blocked[i], blocked[j]), EarsRow.minGap) } }
        XCTAssertTrue(EarsRow.spots(count: 3, free: { _ in false }, halfWidth: { _ in 3 }).isEmpty, "nothing fits: they stay where they stand")
    }

    func testAMealEndsTheDanceAtOnce() {
        let room = Room(count: 1); Self.keep.append(room)
        room.handle(.musicStarted(EarBeat(bpm: 120, anchor: room.now, strength: 3)))
        room.run(1.0)
        XCTAssertTrue(room.reactor.isDancing)
        room.reactor.locks.meal = true
        room.run(1.0 / 30)
        XCTAssertFalse(room.reactor.isDancing)
        XCTAssertFalse(room.rigs[0].brain.ears.dancing)
    }

    // MARK: the clock

    func testStreamToHostClockFollowsTheBuffersAndMovesTheBeatAnchor() {
        var c = EarsClock()
        XCTAssertFalse(c.isSet)
        XCTAssertEqual(c.media(1.0), 1.0, "no offset yet: identity")
        c.note(bufferHost: 1000.0, streamStart: 0)
        XCTAssertEqual(c.offset!, 1000.0, accuracy: 1e-9)
        c.note(bufferHost: 1000.5 + 0.004, streamStart: 0.5)         // 4 ms of jitter: smoothed, not followed
        XCTAssertEqual(c.offset!, 1000.001, accuracy: 1e-6)
        c.note(bufferHost: 1002.0, streamStart: 0.6)                 // a dropped buffer (a 1.4 s jump): snapped
        XCTAssertEqual(c.offset!, 1001.4, accuracy: 1e-9)
        XCTAssertEqual(c.stream(c.media(3.3)), 3.3, accuracy: 1e-9)
        let b = EarBeat(bpm: 120, anchor: 2.0, strength: 3)
        XCTAssertEqual(c.media(b).anchor, 1003.4, accuracy: 1e-9)
        XCTAssertEqual(c.media(b).bpm, 120)
        if case .musicStarted(let mb) = c.media(EarEvent.musicStarted(b)) { XCTAssertEqual(mb!.anchor, 1003.4, accuracy: 1e-9) } else { XCTFail() }
        XCTAssertEqual(c.media(EarEvent.heard(.clap)), .heard(.clap))
    }

    /// The main path: the built-in classifier accepts the 0.5 s / 50 % window the pipeline asks for (else every phone would silently fall back to DSP only).
    func testPipelineBuildsTheClassifierPath() throws {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else { throw XCTSkip("no format") }
        let p = EarsPipeline(format: fmt, classify: true)
        XCTAssertTrue(p.usesClassifier, "SoundAnalysis v1 request rejected: the window / overlap must fit windowDurationConstraint")
        XCTAssertNotNil(p.analyzer)
        let d = EarsPipeline(format: fmt, classify: false)
        XCTAssertFalse(d.usesClassifier)
    }

    func testDspPipelineBeatOnAClickTrackLinesUpWithTheClicksInHostTime() throws {
        let sr = 16000.0
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { throw XCTSkip("no format") }
        let p = EarsPipeline(format: fmt, classify: false)
        XCTAssertFalse(p.usesClassifier)
        // 120 BPM clicks, the first at 0.25 s, 10 s long, host clock starting at 5000 s
        let t = EarsDSPTests()
        var seed: UInt64 = 3
        var x = [Float](repeating: 0, count: Int(sr * 10))
        t.noiseFloor(&x, seed: &seed)
        var k = 0.25
        while k < 10 { t.burst(&x, at: k, length: 0.02, amp: 0.7, seed: &seed); k += 0.5 }
        let host0 = 5000.0
        var i = 0
        while i < x.count {
            let n = min(1024, x.count - i)
            p.feed(Array(x[i..<(i + n)]), hostStart: host0 + Double(i) / sr)
            i += n
        }
        let d = p.drain()
        let starts = d.events.compactMap { e -> EarBeat? in if case .musicStarted(let b) = e { return b }; return nil }
        let beats = d.events.compactMap { e -> EarBeat? in if case .musicBeat(let b) = e { return b }; return nil }
        XCTAssertEqual(starts.count, 1, "music started once: \(d.events)")
        guard let last = beats.last ?? starts.first ?? nil else { return XCTFail("no beat") }
        XCTAssertEqual(last.bpm, 120, accuracy: 5)
        // the anchor is in HOST time now: a click time, as the host saw it, is on the grid
        let clickHost = host0 + 8.25
        let (ph, _) = last.phase(at: clickHost)
        let dist = min(ph, 1 - ph) * last.period
        XCTAssertLessThan(dist, 0.03, "beat grid off the clicks by \(dist * 1000) ms (anchor \(last.anchor), bpm \(last.bpm))")
        XCTAssertEqual(d.hearing, .music)
    }
}
