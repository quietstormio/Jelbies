//
//  EarsHoldTests.swift
//  Music Ears is hold-to-listen: the mic button held + music heard = every Jelbie dances (and shows the music-note bubble, `Ears.dancingIDs`);
//  not owned = no dance; a command during the hold wins; releasing ends the dance after `EarsDance.tail`. Plus the choreography: a confident beat
//  is followed (bounce, sway, arm wave, hop and twirl phrases), no confident beat = a gentle sway that claims no tempo.
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

    func testAConfidentBeatDancesOnTheBeatWithTheArmsWavingAHopAndATwirl() {
        let room = EarsReactorTests.Room(count: 1); EarsReactorTests.keep.append(room)
        room.handle(.musicStarted(EarBeat(bpm: 120, anchor: room.now + 0.2, strength: 3)))
        var armMax: Float = 0, rollMax: Float = 0
        room.run(14) { let b = room.rigs[0].brain; armMax = max(armMax, b.armDirW); rollMax = max(rollMax, abs(b.ears.roll)) }
        XCTAssertGreaterThan(armMax, 0.9, "the arm wave is up")
        XCTAssertGreaterThan(rollMax, 0.05, "side-to-side sways")
        XCTAssertTrue(room.reactor.log.contains { $0.hasPrefix("hop 0 beat 8") }, "\(room.reactor.log)")
        XCTAssertTrue(room.reactor.log.contains { $0.hasPrefix("spin 0 beat 24") }, "a twirl now and then: \(room.reactor.log)")
        room.handle(.musicStopped)
        room.run(EarsDance.tail + 1.2)
        XCTAssertFalse(room.reactor.isDancing)
        XCTAssertEqual(room.rigs[0].brain.armDirW, 0, "the arms come back down")
    }

    func testWithoutAConfidentBeatTheyOnlySwayGentlyAndClaimNoTempo() {
        let room = EarsReactorTests.Room(count: 1); EarsReactorTests.keep.append(room)
        room.handle(.musicStarted(EarBeat(bpm: 120, anchor: room.now, strength: 1.2)))       // a weak estimate
        var sqMin: Float = 1, rollMax: Float = 0
        room.run(15) { let b = room.rigs[0].brain; sqMin = min(sqMin, b.ears.squash); rollMax = max(rollMax, abs(b.ears.roll)) }
        XCTAssertFalse(room.reactor.log.contains { $0.hasPrefix("hop") || $0.hasPrefix("spin") }, "no beat-locked moves: \(room.reactor.log)")
        XCTAssertGreaterThan(sqMin, 0.95, "a soft bob, not the beat bounce")
        XCTAssertLessThan(rollMax, 0.07)
        XCTAssertGreaterThan(rollMax, 0.02, "but it does sway")
        // the tracker loses a beat it had: back to the gentle sway
        room.handle(.musicBeat(EarBeat(bpm: 120, anchor: room.now, strength: 3)))
        room.run(1)
        room.handle(.musicBeatLost)
        room.run(0.2)
        XCTAssertNil(room.reactor.dance?.beat)
    }
}
