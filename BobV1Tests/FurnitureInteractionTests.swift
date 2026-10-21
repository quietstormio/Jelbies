//
//  FurnitureInteractionTests.swift
//  The second decor batch's interactions: each starts, completes, leaves the Jelly on the room's floor and lets go of the piece; the seat variants (hop-on sit,
//  rock, sway, cuddle), the boops, the kicks and rolls, the spinning top and the slide each do what they say. FeetAttach / ArmCap run the same moves
//  (FeetAttachTests.batch2Decor). Soccer (the ball, the goal, the stomp kick, the dribble, the pass, the shot) is SoccerTests.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FurnitureInteractionTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    override func setUp() { DecorField.shared.clear(); room() }
    override func tearDown() { DecorField.shared.clear(); GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }
    private func room() { GameCamera.configureRoom(count: 3, option: .A, wide: 2); _ = GameCamera.camera(aspect: 440 / 956) }

    func installed(_ kind: DecorKind, at p: SIMD2<Float>, from: SIMD2<Float> = SIMD2(-1.0, 1.0)) -> MotionRig {
        room()
        DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: p.x, z: p.y)])
        let r = MotionRig(game: true)
        Self.keep.append(r)
        r.brain.anticsEnabled = true
        r.brain.sleepEnabled = true
        r.brain.abortScript(r.sim, r.skinner)
        r.sim.teleport(toXZ: from)
        for _ in 0..<120 { r.sim.step() }
        r.brain.currentPose(r.sim)
        return r
    }
    static let at = SIMD2<Float>(2.8, 0.6)

    /// Starts `move` on the piece, runs to the end; returns what was seen.
    @discardableResult
    func play(_ kind: DecorKind, _ move: IdleKind, at p: SIMD2<Float> = FurnitureInteractionTests.at, from: SIMD2<Float> = SIMD2(-1.0, 1.0), seconds: Float = 40, fate: Int? = nil,
              each: ((MotionRig) -> Void)? = nil, file: StaticString = #filePath, line: UInt = #line) -> MotionRig {
        let r = installed(kind, at: p, from: from)
        r.brain.soccerModeForce = fate
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(move, r.sim), "\(kind) \(move) starts", file: file, line: line)
        XCTAssertNotNil(DecorField.shared.occupant[7], "\(kind) \(move) holds the piece", file: file, line: line)
        var sawField = false
        r.run(seconds, until: { r.brain.idleState.kind == nil && r.t > 1 }) {
            DecorField.shared.tick(dt: 1.0 / 60)
            if let a = DecorField.shared.anim[7], a.active { sawField = true }
            each?(r)
        }
        XCTAssertNil(r.brain.idleState.kind, "\(kind) \(move) finished", file: file, line: line)
        XCTAssertNil(DecorField.shared.occupant[7], "\(kind) \(move) let go", file: file, line: line)
        XCTAssertTrue(sawField, "\(kind) \(move) moved the piece", file: file, line: line)
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5, "\(kind) \(move): he is back on the room's floor", file: file, line: line)
        r.run(2) { DecorField.shared.tick(dt: 1.0 / 60) }
        XCTAssertLessThan(r.sim.centroid().y, 1.0, "\(kind) \(move): he stands on the floor (centroid \(r.sim.centroid().y))", file: file, line: line)
        XCTAssertNil(r.brain.idleState.kind, file: file, line: line)
        return r
    }

    // MARK: sits

    func testEverySeatHopsOnRestsOnTopAndHopsOff() {
        let seats: [(DecorKind, Float)] = [(.pouf, 0.47), (.armchair, 0.52), (.loveseat, 0.52), (.diningset, 0.47), (.rockingchair, 0.6), (.swing, 0.6)]
        for (kind, y) in seats {
            var stages: [Int] = [], seated = 0, floorErr: Float = 0, maxTop: Float = 0
            let r = play(kind, .decorSit, at: SIMD2(2.8, 0.6), seconds: 50) { r in
                let st = r.brain.idleState.bagStage
                if r.brain.idleState.kind == .decorSit, stages.last != st { stages.append(st) }
                if st == 2, r.brain.bagFloorOn, r.brain.idleState.phaseT > 1.3, let sw = DecorField.shared.seatWorld(7, seat: r.brain.idleState.seat) {
                    seated += 1; floorErr = max(floorErr, abs(r.sim.floorY - sw.y)); maxTop = max(maxTop, sw.y)
                }
            }
            _ = r
            XCTAssertEqual(stages, [0, 1, 2, 3], "\(kind): turn, hop on, on top, hop off")
            XCTAssertGreaterThan(seated, 100, "\(kind): he rests on the seat")
            XCTAssertLessThan(floorErr, 0.003, "\(kind): his floor is the seat's top")
            XCTAssertGreaterThan(maxTop, y - 0.2, "\(kind): up on the seat (\(maxTop))")
        }
    }

    func testRockingChairRocksAndCarriesTheSitterAndTheSwingSways() {
        for (kind, amp) in [(DecorKind.rockingchair, Float(0.14)), (.swing, 0.22)] {
            var maxAngle: Float = 0, maxShift: Float = 0, seatedY: [Float] = []
            play(kind, .decorSit, seconds: 50) { r in
                guard r.brain.idleState.bagStage == 2, r.brain.idleState.phase == 2, let a = DecorField.shared.anim[7] else { return }
                maxAngle = max(maxAngle, abs(kind == .swing ? DecorModels.swingAngle(a) : DecorModels.rockAngle(a)))
                maxShift = max(maxShift, abs(r.brain.idleState.seatShift.y))
                seatedY.append(r.sim.floorY)
            }
            XCTAssertGreaterThan(maxAngle, amp * 0.5, "\(kind) rocks")
            XCTAssertLessThanOrEqual(maxAngle, amp + 1e-4, "\(kind) stays within its amplitude")
            XCTAssertGreaterThan(maxShift, 0.03, "\(kind): the sitter follows the seat point")
            XCTAssertGreaterThan((seatedY.max() ?? 0) - (seatedY.min() ?? 0), 0.0005, "\(kind): his floor moves with the seat")
        }
    }

    func testDiningStoolsFaceTheTableAndTwoJelliesTakeOneStoolEach() {
        let r = installed(.diningset, at: SIMD2(2.6, 0.6))
        let f = DecorField.shared.foot(7)!
        XCTAssertEqual(DecorField.shared.freeSeat(f), 0)
        DecorField.shared.take(7, seat: 0, by: 1)
        XCTAssertEqual(DecorField.shared.freeSeat(f), 1, "the second Jelly takes the other stool")
        XCTAssertTrue(DecorField.shared.available(f))
        DecorField.shared.take(7, seat: 1, by: 2)
        XCTAssertFalse(DecorField.shared.available(f), "both stools taken")
        XCTAssertEqual(DecorKind.diningset.seatFacing(0), .pi / 2); XCTAssertEqual(DecorKind.diningset.seatFacing(1), -.pi / 2)
        _ = r
    }

    // MARK: peek / boop

    func testPeeksAndBoopsStartFinishAndMoveThePiece() {
        for (kind, move) in [(DecorKind.bookshelf, IdleKind.decorPeek), (.wardrobe, .decorPeek), (.duck, .decorBoop), (.drum, .decorBoop), (.monstera, .decorBoop), (.spintop, .decorBoop)] {
            var peakKick: Float = 0, peakPeek: Float = 0, peakSpin: Float = 0
            play(kind, move, seconds: 30) { _ in
                if let a = DecorField.shared.anim[7] { peakKick = max(peakKick, a.kick); peakPeek = max(peakPeek, a.peek); peakSpin = max(peakSpin, a.spin) }
            }
            XCTAssertGreaterThan(peakKick, 0.3, "\(kind): wobble / wiggle / dip")
            if move == .decorPeek { XCTAssertGreaterThan(peakPeek, 0.5, "\(kind): leans in to look") }
            if kind == .spintop { XCTAssertGreaterThan(peakSpin, 10, "a boop sets the top spinning") }
        }
    }

    func testSpinningTopSpinsWobblesFallsAndRightsItself() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .spintop, x: 3, z: 0.5)])
        DecorField.shared.spinTop(7)
        var maxFall: Float = 0, fell = false, rightedAt: Float = -1, t: Float = 0
        var tilts: [Float] = []
        for _ in 0..<(60 * 14) {
            DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60
            guard let a = DecorField.shared.anim[7] else { continue }
            tilts.append(DecorField.topTilt(a).angle)
            if a.fallT >= 0 { fell = true; maxFall = max(maxFall, DecorField.topTilt(a).angle) }
            if fell, a.fallT < 0, rightedAt < 0 { rightedAt = t }
        }
        XCTAssertTrue(fell, "it falls over once it is slow")
        XCTAssertEqual(maxFall, 0.35, accuracy: 0.02, "it tips to 0.35 rad")
        XCTAssertGreaterThan(rightedAt, 0, "then rights itself")
        XCTAssertGreaterThan(tilts[300], tilts[10], "the wobble grows as it slows")
        XCTAssertEqual(DecorField.shared.anim[7]?.spin, 0)
        XCTAssertFalse(DecorField.shared.anim[7]?.active ?? true, "and rests")
    }

    // MARK: kicks

    func testKickingTheBlocksTumblesEachBlockAndTheTowerRestacks() {
        var maxSep: Float = 0
        play(.blocks, .decorKick, at: SIMD2(0.8, 0.8), seconds: 30) { _ in
            if let a = DecorField.shared.anim[7], a.tumbling { maxSep = max(maxSep, a.blocks.map { simd_length(SIMD2($0.pos.x, $0.pos.z)) }.max() ?? 0) }
        }
        XCTAssertGreaterThan(maxSep, 0.8, "the blocks fly apart")
        let a = DecorField.shared.anim[7]!
        XCTAssertTrue(a.tumbling, "they lie where they fell for a while")
        XCTAssertTrue(a.blocks.allSatisfy { $0.rest || $0.pos.y < 0.25 }, "on the floor")
        var t: Float = 0
        while DecorField.shared.anim[7]?.tumbling == true && t < 30 { DecorField.shared.tick(dt: 1.0 / 60); t += 1.0 / 60 }
        XCTAssertLessThan(t, 24, "after ~20 s the tower restacks itself")
        XCTAssertFalse(DecorField.shared.anim[7]!.tumbling)
        DecorField.shared.tumble(7, direction: SIMD2(1, 0))
        DecorField.shared.set(DecorField.shared.placed)
        DecorField.shared.held = 7
        DecorField.shared.tick(dt: 1.0 / 60)
        XCTAssertFalse(DecorField.shared.anim[7]!.tumbling, "picked up: it restacks at once")
        DecorField.shared.held = nil
    }

    func testToyCarRollsFollowsItsHeadingAndSpinsItsWheelsAndYarnTrails() {
        for kind in [DecorKind.toycar, .yarnball, .soccerball] {
            DecorField.shared.set([PlacedDecor(uid: 7, kind: kind, x: 0.8, z: 0.8)])
            DecorField.shared.kickBall(7, direction: SIMD2(1, 0), speed: 3)
            for _ in 0..<30 { DecorField.shared.tick(dt: 1.0 / 60) }
            let a = DecorField.shared.anim[7]!
            XCTAssertGreaterThan(a.pos.x, 1.2, "\(kind) rolls")
            if kind == .toycar {
                XCTAssertEqual(a.heading, atan2f(-1, 0), accuracy: 0.3, "the car's nose follows its velocity")
                XCTAssertGreaterThan(a.wheel, 3, "the wheels turn (v / 0.17)")
            }
            if kind == .yarnball { XCTAssertEqual(a.heading, atan2f(-1, 0), accuracy: 0.6, "the strand trails opposite to the way it rolls") }
            for _ in 0..<(60 * 8) { DecorField.shared.tick(dt: 1.0 / 60) }
            XCTAssertFalse(DecorField.shared.anim[7]!.moving, "\(kind) stops")
            // it draws (a mesh with the art's triangles)
            XCTAssertGreaterThan(DecorModels.build(feet: DecorField.shared.feet, field: DecorField.shared, time: 0.3).indices.count / 3, 100)
        }
    }

    func testEveryRollerStartsAndFinishesAsAKick() {
        for kind in [DecorKind.toycar, .yarnball] { play(kind, .decorKick, at: SIMD2(0.8, 0.8), seconds: 30) }
    }

    // MARK: slide

    func testTheSlideClimbsSitsRidesThePathAndExitsOnTheFloor() {
        var stages: [Int] = [], maxY: Float = 0, floorErr: Float = 0, riding = 0, lastZ: Float = -9, endPz: Float = 0
        let c = SIMD2<Float>(2.6, 0.9)
        let r = play(.slide, .decorSlide, at: c, from: SIMD2(1.0, -0.2), seconds: 60) { r in
            let st = r.brain.idleState.slideStage
            if r.brain.idleState.kind == .decorSlide, stages.last != st { stages.append(st) }
            maxY = max(maxY, r.sim.floorY)
            if st == 5 { riding += 1; lastZ = r.brain.pz; let at = BlobBrain.slideAt(r.brain.idleState.slideS); floorErr = max(floorErr, abs(r.sim.floorY - at.y)) }
            endPz = r.brain.pz
        }
        _ = r
        XCTAssertEqual(stages, [0, 1, 4, 5, 6], "turn, hop up the steps, sit, ride, get up")
        XCTAssertGreaterThan(maxY, 0.6, "he reaches the platform")
        XCTAssertGreaterThan(riding, 20, "he rides")
        XCTAssertLessThan(floorErr, 0.02, "his floor follows the chute")
        XCTAssertEqual(lastZ, c.y + 1.75 * DecorKind.slide.scale, accuracy: 0.4, "he ends 0.35 beyond the chute")
        _ = endPz
    }

    // MARK: the pet bed

    func testTheSleeperHopsIntoThePetBedCurlsUpWithTheMaskOnAndHopsOut() {
        let r = installed(.petbed, at: SIMD2(2.3, 0.4), from: SIMD2(-0.5, 1.4))
        let set = SleepMaskSet(); set.soundOn = false
        r.brain.idleForced = true
        XCTAssertTrue(r.brain.idleStart(.sleep, r.sim), "he goes to bed")
        r.brain.sleep.hold = 3
        XCTAssertEqual(r.brain.sleep.bed, 7, "the pet bed is the preferred solo spot")
        XCTAssertEqual(DecorField.shared.occupant[7], r.brain.steerID)
        var hops: [Int] = [], lyingFloor: Float = -1, inside = false, maskShown = false, hopOut = false
        for _ in 0..<(60 * 60) {
            r.tick(); DecorField.shared.tick(dt: 1.0 / 60)
            set.tick(id: 0, brain: r.brain, sim: r.sim, raceBusy: false, dt: r.sim.stepDt); set.stepPuffs(dt: r.sim.stepDt)
            if r.brain.idleState.kind == .sleep, hops.last != r.brain.sleep.bedHop { hops.append(r.brain.sleep.bedHop) }
            if r.brain.idleState.kind == .sleep, r.brain.sleep.bedHop == 3 { hopOut = true }
            if r.brain.isNapping {
                lyingFloor = r.sim.floorY
                let c = r.sim.centroid()
                inside = abs(c.x - 2.3) < DecorKind.petbed.spec.half.x && abs(c.z - 0.45) < DecorKind.petbed.spec.half.y
                if set.phase(0) == .shown { maskShown = true }
            }
            if r.brain.idleState.kind == nil, r.t > 5 { break }
        }
        XCTAssertEqual(hops, [0, 1, 2, 0, 3], "walk, turn, hop in, sleep, hop out")
        XCTAssertEqual(lyingFloor, 0.12 * DecorKind.petbed.scale, accuracy: 0.01, "he lies on the mattress")
        XCTAssertTrue(inside, "curled up inside the bed")
        XCTAssertTrue(maskShown, "the sleep mask goes on")
        XCTAssertTrue(hopOut)
        XCTAssertNil(r.brain.idleState.kind)
        XCTAssertNil(DecorField.shared.occupant[7])
        XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5)
        r.run(2) {}
        XCTAssertLessThan(r.sim.centroid().y, 1.0)
    }

    // MARK: the two-Jelly socials

    func testTwoJelliesCuddleOnTheLoveseat() {
        DecorField.shared.set([PlacedDecor(uid: 7, kind: .loveseat, x: 2.2, z: 0.2)])
        let lab = SocialTests.Lab(n: 2, positions: [SIMD2(-0.6, 1.4), SIMD2(-1.9, 0.2)], quiet: true, seed: 5)
        let a = lab.rigs[0], b = lab.rigs[1]
        XCTAssertTrue(a.brain.socialStart(.cuddle, with: b.brain, a.sim), "the cuddle starts")
        var bothSeated = 0, maxCuddle: [Float] = [0, 0], seats = Set<Int>()
        for _ in 0..<(60 * 70) {
            lab.tick(watching: false); DecorField.shared.tick(dt: 1.0 / 60)
            for r in lab.rigs { r.skinner.jelly.tick(brain: r.brain, sim: r.sim, dt: r.sim.stepDt) }
            let on = lab.rigs.map { $0.brain.idleState.kind == .decorSit && $0.brain.idleState.bagStage == 2 && $0.brain.idleState.phase == 2 }
            if on[0] && on[1] { bothSeated += 1; seats = [a.brain.idleState.seat, b.brain.idleState.seat] }
            for i in 0..<2 { maxCuddle[i] = max(maxCuddle[i], lab.rigs[i].brain.idleState.cuddle) }
            if a.brain.social == nil, b.brain.social == nil, a.brain.idleState.kind == nil, b.brain.idleState.kind == nil, bothSeated > 0 { break }
        }
        XCTAssertGreaterThan(bothSeated, 120, "both are settled on the sofa together")
        XCTAssertEqual(seats, [0, 1], "one on each cushion")
        XCTAssertGreaterThan(maxCuddle[0], 0.8); XCTAssertGreaterThan(maxCuddle[1], 0.8)
        for r in lab.rigs { XCTAssertEqual(r.sim.floorY, 0, accuracy: 1e-5); XCTAssertNil(r.brain.idleState.kind) }
        XCTAssertNil(DecorField.shared.occupant[7])
        XCTAssertTrue((lab.events[0] + lab.events[1]).contains { if case .ended(.cuddle, _, .done) = $0 { return true }; return false }, "the cuddle ended well")
    }
}
