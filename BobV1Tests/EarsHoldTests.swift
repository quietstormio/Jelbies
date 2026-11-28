//
//  EarsHoldTests.swift
//  Music Ears is hold-to-listen: the mic button held + music heard = every Jelbie dances (and shows the music-note bubble, `Ears.dancingIDs`);
//  not owned = no dance; a command during the hold wins; releasing ends the dance after `EarsDance.tail`. Plus the choreography: ONE sway, with no beat
//  (yet) a gentle one on its own clock that the beat then steers.
//

import XCTest
@testable import BobV1

@MainActor
final class EarsHoldTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private var suites: [String] = []

    private func suite() -> UserDefaults {
        let n = "EarsHoldTests.\(UUID().uuidString)"
        suites.append(n)
        return UserDefaults(suiteName: n)!
    }
    override func tearDown() {
        for n in suites { UserDefaults.standard.removePersistentDomain(forName: n) }
        suites = []
    }

    /// An inert Ears with two Jelbies on headless rigs and a clock the test moves.
    @MainActor private final class Rig {
        let ears: Ears
        let care = GameCare(jellyCount: 1, persistent: false)
        let rigs = (0..<2).map { _ in MotionRig(game: true) }
        var t: Double = 1000
        init(_ d: UserDefaults, owned: Bool) {
            ears = Ears(defaults: d, inert: true)
            ears.owned = { owned }
            ears.danceHook = { _ in }
            ears.clock = { [unowned self] in t }
            for (i, r) in rigs.enumerated() {
                r.brain.seed = 5 + UInt64(i); r.brain.amplitude = 1
                if i > 0 { r.sim.shift(byXZ: SIMD2(1.2, 0.8)); r.brain.currentPose(r.sim) }
            }
            ears.debugSetJellies(rigs.enumerated().map { EarsReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) })
            EarsHoldTests.keep += [care, ears]
        }
        func step(_ seconds: Double) {
            for _ in 0..<Int(seconds * 60) {
                for r in rigs { r.tick() }
                t += 1.0 / 60
                ears.step(care: care, dt: 1.0 / 60)
            }
        }
        func music(bpm: Float = 120, strength: Float = 3) { ears.inject(.musicStarted(EarBeat(bpm: bpm, anchor: t, strength: strength))) }
    }

    func testHoldPlusMusicMakesEveryOwnerDanceAndShowTheNoteBubble() {
        let r = Rig(suite(), owned: true)
        _ = r.care.voice.mode.begin()                        // the mic is open (the voice lock) ...
        r.ears.holdBegan()
        XCTAssertTrue(r.ears.holding)
        r.music(); r.step(0.5)
        XCTAssertTrue(r.ears.reactor.isDancing, "the voice lock does not stop a dance the hold started: \(r.ears.reactor.log)")
        XCTAssertEqual(r.ears.dancingIDs, [0, 1], "a music-note bubble for each dancer")
        XCTAssertTrue(r.rigs.allSatisfy { $0.brain.ears.dancing })
        r.step(3)
        XCTAssertEqual(r.ears.dancingIDs, [0, 1], "the bubble stays while they dance")
    }

    func testNotOwnedMeansNoHoldAndNoDance() {
        let r = Rig(suite(), owned: false)
        r.ears.holdBegan()
        XCTAssertFalse(r.ears.holding, "voice commands only")
        r.music(); r.step(1)
        XCTAssertFalse(r.ears.reactor.isDancing)
        XCTAssertEqual(r.ears.dancingIDs, [])
        XCTAssertFalse(r.rigs.contains { $0.brain.ears.dancing })
    }

    func testMusicWithoutTheHoldDoesNotDanceByDefault() {
        let r = Rig(suite(), owned: true)                    // owned, but the button is not held and the always-on switch is off
        r.music(); r.step(1)
        XCTAssertFalse(r.ears.reactor.isDancing)
        XCTAssertEqual(r.ears.dancingIDs, [])
    }

    func testACommandDuringTheHoldCutsTheDance() {
        let r = Rig(suite(), owned: true)
        r.ears.holdBegan(); r.music(); r.step(1)
        XCTAssertTrue(r.ears.reactor.isDancing)
        r.ears.commandHeard()
        XCTAssertFalse(r.ears.reactor.isDancing)
        XCTAssertEqual(r.ears.dancingIDs, [])
        XCTAssertFalse(r.rigs.contains { $0.brain.ears.dancing })
        r.step(0.5)
        XCTAssertFalse(r.ears.reactor.isDancing, "and it stays cut")
    }

    func testTheVoiceCoordinatorTellsEarsWhenACommandWasUnderstood() {
        let ears = Ears.shared
        let r = Rig(suite(), owned: true)
        let savedOwned = ears.owned
        ears.owned = { true }
        ears.debugSetJellies(r.rigs.enumerated().map { EarsReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) })
        defer { ears.holdEnded(); ears.reactor.reset([]); ears.owned = savedOwned; ears.debugSetJellies([]) }
        ears.holdBegan()
        ears.reactor.handle(.musicStarted(EarBeat(bpm: 120, anchor: CACurrentMediaTime(), strength: 3)), jellies: r.rigs.enumerated().map { EarsReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }, now: CACurrentMediaTime())
        XCTAssertTrue(ears.reactor.isDancing)
        r.care.voice.finish(VoiceDecision(reaction: .perform(.sit)), transcript: "sit")
        XCTAssertFalse(ears.reactor.isDancing, "a spoken command wins over the dance")
        // nothing matched (lyrics): the dance is not cut
        ears.reactor.handle(.musicStarted(EarBeat(bpm: 120, anchor: CACurrentMediaTime(), strength: 3)), jellies: r.rigs.enumerated().map { EarsReactor.Jelly(id: $0.offset, brain: $0.element.brain, sim: $0.element.sim) }, now: CACurrentMediaTime())
        r.care.voice.finish(VoiceDecision(reaction: .puzzled, noMatch: true), transcript: "la la la")
        XCTAssertTrue(ears.reactor.isDancing, "an unmatched transcript (singing along) does not cut the dance")
    }

    func testReleaseEndsListeningAndTheDanceEndsAfterTheTail() {
        let r = Rig(suite(), owned: true)
        _ = r.care.voice.mode.begin()
        r.ears.holdBegan(); r.music(); r.step(2)
        XCTAssertTrue(r.ears.reactor.isDancing)
        r.ears.holdEnded()
        _ = r.care.voice.mode.endHold()                      // the voice is now processing: still no reason to stop
        XCTAssertFalse(r.ears.holding)
        r.step(EarsDance.tail - 0.8)
        XCTAssertTrue(r.ears.reactor.isDancing, "still dancing through the tail")
        XCTAssertEqual(r.ears.dancingIDs, [0, 1])
        r.step(1.8)
        XCTAssertFalse(r.ears.reactor.isDancing)
        XCTAssertEqual(r.ears.dancingIDs, [])
        XCTAssertTrue(r.rigs[0].brain.ears.isNeutral)
        // music heard after the release does not start a new one
        r.music(); r.step(1)
        XCTAssertFalse(r.ears.reactor.isDancing)
    }

    func testReleaseWithNoMusicChangesNothing() {
        let r = Rig(suite(), owned: true)
        r.ears.holdBegan(); r.step(1); r.ears.holdEnded(); r.step(1)
        XCTAssertFalse(r.ears.reactor.isDancing)
        XCTAssertEqual(r.ears.dancingIDs, [])
    }

    // MARK: the choreography

    func testWithNoBeatYetTheySwayGentlyAndTheBeatThenSteersTheSameSway() {
        let room = EarsReactorTests.Room(count: 1); EarsReactorTests.keep.append(room)
        room.handle(.musicStarted(nil))
        var rollMax: Float = 0, sqMin: Float = 1, step: Float = 0, prev: Float = 0
        room.run(10) { let e = room.rigs[0].brain.ears; rollMax = max(rollMax, abs(e.roll)); sqMin = min(sqMin, e.squash); step = max(step, abs(e.roll - prev)); prev = e.roll }
        XCTAssertGreaterThan(rollMax, 0.03, "it sways with no beat")
        XCTAssertLessThan(rollMax, 0.07, "gently")
        XCTAssertGreaterThan(sqMin, 0.95)
        XCTAssertFalse(room.reactor.log.contains { $0.hasPrefix("hop") || $0.hasPrefix("spin") }, "\(room.reactor.log)")
        // the beat comes: the same clock is steered (no jump), the sway grows into the beat
        room.handle(.musicBeat(EarBeat(bpm: 100, anchor: room.now + 0.2, strength: 3)))
        room.run(8) { let e = room.rigs[0].brain.ears; rollMax = max(rollMax, abs(e.roll)); step = max(step, abs(e.roll - prev)); prev = e.roll }
        XCTAssertGreaterThan(rollMax, 0.075, "the full sway once the beat is known")
        XCTAssertLessThan(step, 0.012, "no pop when the beat is found")
        room.handle(.musicBeatLost)
        room.run(0.2)
        XCTAssertNil(room.reactor.dance?.beat)
        room.handle(.musicStopped)
        room.run(EarsDance.tail + 1.2)
        XCTAssertFalse(room.reactor.isDancing)
    }
}
