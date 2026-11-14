//
//  WeatherTests.swift
//  The weather (Melon/Weather.swift) and the Jelbies' storm reactions (BlobBrain+Weather.swift): the storm schedule and its persistence, the plan's timing and the
//  gentleness limits, the huddle (everybody to a tight cluster, nobody through anybody), the busy ones that skip it, the touch that interrupts it, the relief and the
//  scatter, and that every bit of state is back to normal afterwards.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class WeatherTests: XCTestCase {
    override func setUp() { super.setUp(); RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }
    override func tearDown() { RoomLayout.dynamicBoxes = []; GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0); super.tearDown() }

    func suite() -> UserDefaults { UserDefaults(suiteName: "weather-\(UUID().uuidString)")! }

    // MARK: the schedule

    func testNextStormIsTwoToFiveHoursAwayAndPersisted() {
        let d = suite()
        let a = WeatherBook(defaults: d)
        XCTAssertGreaterThanOrEqual(a.nextStormAt - a.playSeconds, WeatherTuning.gap.lowerBound)
        XCTAssertLessThanOrEqual(a.nextStormAt - a.playSeconds, WeatherTuning.gap.upperBound)
        let b = WeatherBook(defaults: d)          // a relaunch: the same roll, no new one
        XCTAssertEqual(b.nextStormAt, a.nextStormAt)
        XCTAssertFalse(b.isStorming)
    }

    func testStormComesWhenPlayTimeReachesItAndRelaunchDoesNotRepeatIt() {
        let d = suite()
        d.set(100.0, forKey: WeatherBook.playKey); d.set(130.0, forKey: WeatherBook.nextKey)
        let a = WeatherBook(defaults: d)
        var started = false
        for _ in 0..<2000 { if a.tick(dt: 0.05).contains(where: { $0.kind == .began }) { started = true; break } }
        XCTAssertTrue(started, "the storm begins once the play time passes the roll")
        XCTAssertTrue(a.isStorming)
        let b = WeatherBook(defaults: d)          // killed mid-storm and relaunched: not storming, and the next one is hours away (rolled when this one began)
        XCTAssertFalse(b.isStorming)
        XCTAssertGreaterThanOrEqual(b.nextStormAt - b.playSeconds, WeatherTuning.gap.lowerBound - 60)
        var again = false
        for _ in 0..<2000 { if b.tick(dt: 0.05).contains(where: { $0.kind == .began }) { again = true } }
        XCTAssertFalse(again)
    }

    func testPlayTimeOnlyCountsWhileTheRoomIsShown() {
        let a = WeatherBook(defaults: suite())
        let p = a.playSeconds
        a.tick(dt: 1, active: false)
        XCTAssertEqual(a.playSeconds, p)
        a.tick(dt: 1, active: true)
        XCTAssertEqual(a.playSeconds, p + 1, accuracy: 1e-9)
    }

    func testForcedStormArgument() {
        let d = suite()
        d.set(1, forKey: "Storm"); d.set(1.0, forKey: "StormDelay")
        let a = WeatherBook(defaults: d)
        XCTAssertFalse(a.isStorming)
        var ev: [StormEvent] = []
        for _ in 0..<100 { ev += a.tick(dt: 0.05) }
        XCTAssertTrue(ev.contains { $0.kind == .began })
        XCTAssertTrue(a.isStorming)
        d.set(2, forKey: "Storm")
        let b = WeatherBook(defaults: d)
        for _ in 0..<100 { b.tick(dt: 0.05) }
        XCTAssertEqual(b.phase, .peak, "-Storm 2 starts at the peak")
    }

    func testNoStormEverStartsByItselfWhenDisabled() {
        let d = suite()
        d.set(0.0, forKey: WeatherBook.playKey); d.set(1.0, forKey: WeatherBook.nextKey)
        let a = WeatherBook(defaults: d); a.disabled = true
        for _ in 0..<400 { a.tick(dt: 0.05) }
        XCTAssertFalse(a.isStorming)
    }

    // MARK: the plan

    func testPlanTimingAndGentleness() {
        for seed in 1...200 as ClosedRange<UInt64> {
            let p = StormPlan.make(seed: seed)
            XCTAssertGreaterThanOrEqual(p.total, 120, "seed \(seed)"); XCTAssertLessThanOrEqual(p.total, 230, "seed \(seed): a storm lasts 2-4 minutes")
            XCTAssertTrue(p.events.map(\.t).isSorted)
            XCTAssertEqual(p.events.first?.kind, .began)
            XCTAssertEqual(p.events.last?.kind, .ended)
            let close = p.strikes.filter { $0.close }
            XCTAssertTrue(close.first.map { $0.t >= p.peakStart && $0.t <= p.peakStart + 3.5 } ?? false, "seed \(seed): the first close strike opens the peak")
            for s in p.strikes where s.close { XCTAssertGreaterThanOrEqual(s.t, p.peakStart) }
            // gentle: pulses at least 0.3 s apart (3 flashes a second at most), strikes at least 7 s apart at the peak, amplitudes below the cap
            for s in p.strikes { for (a, b) in zip(s.pulses, s.pulses.dropFirst()) { XCTAssertGreaterThanOrEqual(b.dt - a.dt, 0.299) }; for q in s.pulses { XCTAssertLessThanOrEqual(q.amp, 1.0) } }
            for (a, b) in zip(p.strikes.filter { $0.t >= p.peakStart }, p.strikes.filter { $0.t >= p.peakStart }.dropFirst()) { XCTAssertGreaterThanOrEqual(b.t - a.t, 7 - 1e-9) }
            // the flash never exceeds the cap and the flicker rate stays under three a second
            var prev: Float = 0, rises = 0, lastRise = -9.0
            var t = 0.0
            while t < p.total {
                let f = p.flash(at: t)
                XCTAssertLessThanOrEqual(f, 1.0)
                if f > 0.25, prev <= 0.25 { rises += 1; XCTAssertGreaterThanOrEqual(t - lastRise, 0.29, "seed \(seed): flashes closer than 0.3 s"); lastRise = t }
                prev = f; t += 1.0 / 120
            }
            XCTAssertEqual(p.gloom(at: 0), 0); XCTAssertEqual(p.gloom(at: p.total), 0); XCTAssertEqual(p.rain(at: p.total), 0, accuracy: 1e-6)
            XCTAssertGreaterThan(p.gloom(at: p.buildUp + 20), 0.99)
            XCTAssertEqual(p.flash(at: p.peakStart + 3.05, reduce: true) > 0, true)
        }
    }

    func testWholeStormRunsAndEndsClear() {
        let a = WeatherBook(defaults: suite())
        a.begin(seed: 7)
        var seen: [StormEvent] = []
        var phases: [StormPhase] = []
        var maxFlash: Float = 0
        for _ in 0..<(60 * 260) {
            seen += a.tick(dt: 1.0 / 60)
            if phases.last != a.phase { phases.append(a.phase) }
            maxFlash = max(maxFlash, a.look().flash)
            if !a.isStorming { break }
        }
        XCTAssertEqual(phases, [.buildUp, .peak, .clearing, .clear])
        XCTAssertGreaterThan(maxFlash, 0.5)
        XCTAssertTrue(seen.contains { $0.kind == .notice })
        XCTAssertGreaterThanOrEqual(seen.filter { if case .rumble = $0.kind { return true }; return false }.count, 2, "distant rumbles")
        XCTAssertEqual(seen.last?.kind, .ended)
        XCTAssertTrue(a.look().isClear)
    }

    func testReduceMotionIsOneSoftGlow() {
        let p = StormPlan.make(seed: 5)
        let s = p.strikes.first { $0.close }!
        let hard = (0..<200).map { p.flash(at: s.t + Double($0) / 100) }
        let soft = (0..<200).map { p.flash(at: s.t + Double($0) / 100, reduce: true) }
        XCTAssertLessThan(zip(soft, soft.dropFirst()).map { abs($1 - $0) }.max()!, zip(hard, hard.dropFirst()).map { abs($1 - $0) }.max()!, "reduce motion: no sudden flash")
    }

    // MARK: the Jelbies

    @MainActor final class Room {
        let lab: SocialTests.Lab
        let reactor = StormReactor()
        let book: WeatherBook
        var js: [StormReactor.Jelly]
        init(n: Int = 3, book: WeatherBook) {
            lab = SocialTests.Lab(n: n, quiet: true, seed: 11)
            self.book = book
            js = lab.rigs.enumerated().map { StormReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim, skinner: $0.element.skinner) }
            for r in lab.rigs { r.brain.anticsEnabled = true }
        }
        nonisolated deinit {}
        /// One 60 Hz step like the stage: the weather, the reactor, then the bodies.
        func step(events extra: [StormEvent] = []) {
            let ev = book.tick(dt: 1.0 / 60) + extra
            if !ev.isEmpty { reactor.handle(ev, plan: book.plan, jellies: js, care: nil) }
            reactor.tick(jellies: js, care: nil, dt: 1.0 / 60)
            lab.tick(watching: false)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            lab.sampleGaps()
        }
        func run(_ seconds: Float, until: (() -> Bool)? = nil) { for _ in 0..<Int(seconds * 60) { step(); if until?() == true { break } } }
        /// Skips the weather clock ahead without ticking the bodies (events still go to the reactor).
        func skip(to storm: Double) {
            while book.stormTime < storm - 0.01 && book.isStorming {
                let ev = book.tick(dt: min(4.9, storm - book.stormTime))
                if !ev.isEmpty { reactor.handle(ev, plan: book.plan, jellies: js, care: nil) }
            }
        }
        var gaps: [Float] { var g: [Float] = []; for i in 0..<lab.rigs.count { for j in (i + 1)..<lab.rigs.count { g.append(lab.centreGap(i, j)) } }; return g }
    }

    @MainActor struct Snapshot: Equatable {
        var autonomy: [Bool], peerGap: [Float], reserved: [Bool], blocked: [Bool], commanded: [Bool], hurry: [Bool]
        init(_ r: Room) {
            let b = r.lab.rigs.map(\.brain)
            autonomy = b.map(\.autonomy); peerGap = b.map(\.peerGap); reserved = b.map(\.reserved); blocked = b.map(\.idleBlocked); commanded = b.map(\.commanded); hurry = b.map(\.hurry)
        }
    }

    /// Starts a storm at the peak and runs until the huddle has formed (everyone in `.huddle`), returning the seconds it took.
    func huddled(_ room: Room, ids: [Int], seed: UInt64 = 4, limit: Float = 25) -> Float {
        let ev = room.book.begin(seed: seed, jumpTo: .peak)
        room.reactor.handle(ev, plan: room.book.plan, jellies: room.js, care: nil)
        var t: Float = 0
        while t < limit {
            room.step(); t += 1.0 / 60
            if ids.allSatisfy({ room.reactor.members[$0]?.mode == .huddle }) { return t }
        }
        return -1
    }

    func testHuddleGathersEveryFreeJelbieIntoATightClusterNobodyThroughAnybody() {
        let room = Room(book: WeatherBook(defaults: suite()))
        let before = Snapshot(room)
        let t = huddled(room, ids: [0, 1, 2])
        XCTAssertGreaterThan(t, 0, "all three reach the huddle: \(room.reactor.log)")
        XCTAssertLessThan(t, 14, "the scurry takes a few seconds")
        room.run(2)
        let gap = MelonController.jellyGap
        for g in room.gaps {
            XCTAssertGreaterThanOrEqual(g, gap * 0.93, "huddled Jelmiko keep the room's gap (\(room.gaps))")
            XCTAssertLessThanOrEqual(g, gap * 1.6, "...and are pressed close, not apart (\(room.gaps))")
        }
        XCTAssertGreaterThanOrEqual(room.lab.minPair, gap * MelonController.softFloor - 0.02, "nobody went through anybody on the way (min centre gap \(room.lab.minPair))")
        XCTAssertTrue(room.lab.rigs.allSatisfy { $0.brain.storm.isActive }, "the storm pose is on")
        XCTAssertTrue(room.lab.rigs.contains { $0.brain.expr.kind == .worried }, "worried eyes")
        // a tremble: the roll changes sign within a second
        var lo: Float = 0, hi: Float = 0
        for _ in 0..<60 { room.step(); let r = room.lab.rigs[0].brain.storm.roll; lo = min(lo, r); hi = max(hi, r) }
        XCTAssertGreaterThan(hi - lo, 0.02, "trembling")
        XCTAssertLessThan(max(hi, -lo), 0.06, "...gently")
        _ = before
    }

    func testFlashFlinchesTheHuddle() {
        let room = Room(book: WeatherBook(defaults: suite()))
        XCTAssertGreaterThan(huddled(room, ids: [0, 1, 2]), 0)
        room.run(1)
        let m0 = room.lab.rigs[0].brain.storm.squash
        var low = m0
        let plan = room.book.plan!
        let i = plan.strikes.firstIndex { $0.close }!
        let ev = [StormEvent(t: 0, kind: .flash(i))]
        room.reactor.handle(ev, plan: plan, jellies: room.js, care: nil)
        for _ in 0..<20 { room.step(); low = min(low, room.lab.rigs[0].brain.storm.squash) }
        XCTAssertLessThan(low, m0 - 0.05, "a flinch on the flash (squash \(m0) -> \(low))")
    }

    func testBusyJelbiesSkipTheHuddle() {
        let room = Room(book: WeatherBook(defaults: suite()))
        room.lab.rigs[1].brain.reserved = true          // his meal is coming
        XCTAssertGreaterThan(huddled(room, ids: [0, 2]), 0, "\(room.reactor.log)")
        XCTAssertNil(room.reactor.members[1], "the reserved one is not part of it")
        XCTAssertTrue(room.lab.rigs[1].brain.storm.isNeutral)
        XCTAssertTrue(room.lab.rigs[1].brain.reserved, "and his reservation is untouched")
    }

    func testALockThatStartsMidHuddleReleasesEverybody() {
        let room = Room(book: WeatherBook(defaults: suite()))
        let before = Snapshot(room)
        XCTAssertGreaterThan(huddled(room, ids: [0, 1, 2]), 0)
        room.reactor.locks.meal = true          // a meal is asked for
        room.run(0.5)
        XCTAssertTrue(room.reactor.members.isEmpty)
        for r in room.lab.rigs { room.lab.tick(watching: false); XCTAssertTrue(r.brain.storm.isNeutral) }
        room.run(1)
        XCTAssertEqual(Snapshot(room), before, "all state restored")
    }

    func testAMealInProgressNeverStartsAHuddle() {
        let room = Room(book: WeatherBook(defaults: suite()))
        room.reactor.locks.bath = true
        let ev = room.book.begin(seed: 4, jumpTo: .peak)
        room.reactor.handle(ev, plan: room.book.plan, jellies: room.js, care: nil)
        room.run(12)
        XCTAssertTrue(room.reactor.members.isEmpty)
        XCTAssertTrue(room.lab.rigs.allSatisfy { $0.brain.storm.isNeutral && !$0.brain.hurry })
    }

    func testAPettedJelbieStaysAndCalms() {
        let room = Room(book: WeatherBook(defaults: suite()))
        XCTAssertGreaterThan(huddled(room, ids: [0, 1, 2]), 0)
        let b = room.lab.rigs[2].brain
        b.activity = .touched          // a finger has him
        room.reactor.tick(jellies: room.js, care: nil, dt: 1.0 / 60)
        XCTAssertEqual(room.reactor.members[2]?.mode, .comforted)
        XCTAssertTrue(b.storm.wantRoll == 0 && b.storm.wantPitch == 0 && b.storm.wantSquash == 1, "no tremble while he is held")
        let pos = b.position
        for _ in 0..<120 { room.reactor.tick(jellies: room.js, care: nil, dt: 1.0 / 60); b.activity = .touched }
        XCTAssertEqual(b.position, pos, "he did not run off to the others")
        XCTAssertEqual(room.reactor.members[2]?.mode, .comforted)
        XCTAssertFalse(room.reactor.members.filter { $0.key != 2 }.isEmpty, "the others still huddle")
        // let go: he comes back to the huddle while the peak lasts
        b.activity = .idle
        room.run(16)
        XCTAssertEqual(room.reactor.members[2]?.mode, .huddle, "after the petting he rejoins: \(room.reactor.log) member \(String(describing: room.reactor.members[2])) act \(b.activity) pending \(String(describing: b.pending)) script \(b.script) pos \(b.position) slots \(room.reactor.slots)")
    }

    func testReliefShakesOffAndScattersAndRestoresEverything() {
        let room = Room(book: WeatherBook(defaults: suite()))
        let before = Snapshot(room)
        var ticks = 0
        room.reactor.onFirstShake = { ticks += 1 }
        XCTAssertGreaterThan(huddled(room, ids: [0, 1, 2]), 0)
        room.run(1)
        let cluster = room.gaps.reduce(0, +) / 3
        let plan = room.book.plan!
        room.skip(to: plan.clearStart - 0.2)
        room.run(0.5)
        XCTAssertEqual(room.book.phase, .clearing)
        var shook = Set<Int>()
        for _ in 0..<(60 * 14) {
            room.step()
            for (i, r) in room.lab.rigs.enumerated() where r.brain.idleState.kind == .shake { shook.insert(i) }
        }
        XCTAssertEqual(shook, [0, 1, 2], "the group shakes it off")
        XCTAssertEqual(ticks, 1, "one soft haptic tick for the relieved shake-off, not one per Jelmiko")
        XCTAssertTrue(room.reactor.members.isEmpty, "everyone is free: \(room.reactor.log)")
        XCTAssertTrue(room.lab.rigs.allSatisfy { $0.brain.storm.isNeutral && !$0.brain.hurry })
        XCTAssertGreaterThan(room.gaps.reduce(0, +) / 3, cluster + 0.2, "they scattered")
        room.skip(to: plan.total)
        room.run(1)
        XCTAssertFalse(room.reactor.stormOn)
        XCTAssertEqual(Snapshot(room), before, "all state restored")
    }

    func testOneJelbieNoticesAtTheWindowFirst() {
        let room = Room(book: WeatherBook(defaults: suite()))
        let ev = room.book.begin(seed: 3)
        room.reactor.handle(ev, plan: room.book.plan, jellies: room.js, care: nil)
        room.reactor.handle([StormEvent(t: 16, kind: .notice)], plan: room.book.plan, jellies: room.js, care: nil)
        let kinds = room.lab.rigs.map { $0.brain.commandedIdle }
        XCTAssertEqual(kinds.filter { $0 == .window }.count, 1, "exactly one Jelmiko goes to the window")
        room.run(2)
        XCTAssertTrue(room.lab.rigs.contains { $0.brain.idleState.kind == .window })
    }

    func testSleepersWakeGrumpyAtTheFirstCloseThunderOfThePeak() {
        let room = Room(book: WeatherBook(defaults: suite()))
        let s = room.lab.rigs[2]
        s.brain.idleForced = true
        XCTAssertTrue(s.brain.idleStart(.sleep, s.sim))
        XCTAssertTrue(s.brain.isSleeping)
        let ev = room.book.begin(seed: 4, jumpTo: .peak)
        room.reactor.handle(ev, plan: room.book.plan, jellies: room.js, care: nil)
        let plan = room.book.plan!
        let i = plan.strikes.firstIndex { $0.close }!
        room.reactor.handle([StormEvent(t: 0, kind: .flash(i))], plan: plan, jellies: room.js, care: nil)
        XCTAssertTrue(s.brain.isSleeping, "a flash only wobbles a sleeper")
        XCTAssertNil(room.reactor.members[2])
        room.reactor.handle([StormEvent(t: 0, kind: .thunder(i))], plan: plan, jellies: room.js, care: nil)
        XCTAssertTrue(room.reactor.log.contains { $0.contains("wakes grumpy") }, "\(room.reactor.log)")
    }

    func testStormPoseNeverTipsTheBodyPastTheLimit() {
        // the largest pose the channel can write: tremble roll + flinch pitch stay far below 0.5 rad
        var worst: Float = 0
        for k in 0..<2000 {
            let t = Float(k) / 60
            let p = StormPose.huddle(t: t, standing: 5, phase: 1.7, flinch: Float(k % 80) / 60, amplitude: 1)
            worst = max(worst, abs(p.pitch), abs(p.roll))
            XCTAssertGreaterThan(p.squash, 0.8)
        }
        XCTAssertLessThan(worst, 0.2)
    }

    // MARK: haptics

    func testHapticsFollowTheStormPhasesSoftlyAndRarely() {
        let book = WeatherBook(defaults: suite())
        book.begin(seed: 9)
        let h = StormHaptics()
        var flashOnly = 0
        var kinds: [(StormHaptic, Double)] = []
        var t = 0.0
        while book.isStorming {
            let ev = book.tick(dt: 1.0 / 60)
            t += 1.0 / 60
            for e in ev {
                if case .flash = e.kind { XCTAssertNil(StormHaptics.haptic(for: e, plan: book.plan)); flashOnly += 1 }
                if let k = StormHaptics.haptic(for: e, plan: book.plan), h.request(k, now: t, blocked: false, driver: nil) { kinds.append((k, t)) }
            }
        }
        let plan = StormPlan.make(seed: 9)
        XCTAssertGreaterThan(flashOnly, 3, "flashes happened and made no haptic")
        XCTAssertTrue(kinds.contains { $0.0 == .farRumble && $0.1 < plan.buildUp }, "a soft far rumble in the build-up")
        XCTAssertTrue(kinds.contains { $0.0 == .closeRumble && $0.1 >= plan.peakStart }, "a close rumble at the peak")
        XCTAssertFalse(kinds.contains { $0.0 == .closeRumble && $0.1 < plan.peakStart }, "none before the peak")
        XCTAssertFalse(kinds.contains { $0.0 == .softTick }, "the tick belongs to the shake-off, not the thunder")
        for (a, b) in zip(kinds, kinds.dropFirst()) { XCTAssertGreaterThanOrEqual(b.1 - a.1, StormHaptics.thunderGap - 0.02, "at most one thunder haptic per 10 s") }
        XCTAssertLessThanOrEqual(StormHaptics.farPeak, 0.2); XCTAssertLessThanOrEqual(StormHaptics.closePeak, 0.35)
        XCTAssertLessThanOrEqual(StormHaptics.farDuration, 0.8); XCTAssertGreaterThan(StormHaptics.closePeak, StormHaptics.farPeak)
        // skipped entirely while a race / volleyball / the bath has the haptics
        let b = StormHaptics()
        XCTAssertFalse(b.request(.closeRumble, now: 100, blocked: true, driver: nil))
        XCTAssertFalse(b.request(.softTick, now: 100, blocked: true, driver: nil))
        XCTAssertTrue(b.sent.isEmpty)
        XCTAssertTrue(b.request(.softTick, now: 100, blocked: false, driver: nil))
        XCTAssertTrue(b.request(.softTick, now: 100.1, blocked: false, driver: nil), "ticks are not thunder-gated")
        // with the driver silent (not warm / haptics off) the request is still counted and is a pure no-op
        let sink = RecordingHapticSink()
        let driver = HapticDriver(sinks: [sink])
        let c = StormHaptics()
        c.request(.closeRumble, now: 1, blocked: false, driver: driver)
        XCTAssertEqual(sink.events(.wobble).count, 1, "outside focus the storm plays through the room's engine (2026-11-02: it used to be silent)")
        driver.setWarm(true); sink.clear()
        c.request(.farRumble, now: 20, blocked: false, driver: driver)
        c.request(.softTick, now: 21, blocked: false, driver: driver)
        XCTAssertEqual(sink.events(.wobble).count, 1); XCTAssertEqual(sink.events(.transient).count, 1)
        XCTAssertEqual(sink.events(.wobble)[0].intensity, StormHaptics.farPeak, accuracy: 1e-6)
    }

    func testClusterSlotsAreAtLeastTheGapApart() {
        for n in 1...4 {
            let s = StormReactor.clusterSlots(centre: .zero, count: n, gap: 1.47)
            XCTAssertEqual(s.count, n)
            for i in 0..<n { for j in (i + 1)..<n { XCTAssertGreaterThanOrEqual(simd_distance(s[i], s[j]), 1.47 - 1e-4) } }
        }
    }
}

private extension Array where Element == Double {
    var isSorted: Bool { zip(self, dropFirst()).allSatisfy { $0 <= $1 } }
}
