//
//  DiningTierTests.swift
//  Nintendogs-style appetite: how much he eats or drinks depends on his tier. Full / Quenched refuses (head shake, label, tray poofs, no need
//  change), Normal takes 1 piece, Hungry 2, Famished / Parched the whole serving, faster. Each piece adds MealAppetite.gainPerPiece to the need.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class DiningTierTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []

    private func setup(hunger: Float, thirst: Float) -> MealRun {
        let m = MealRun()
        Self.keep.append(m)
        m.care.needs.set(.hunger, hunger); m.care.needs.set(.thirst, thirst)
        m.moveAway()
        return m
    }

    func testPiecesPerTier() {
        XCTAssertEqual(NeedTier.allCases.map { MealAppetite.pieces($0) }, [0, 1, 2, 3], "Full 0, Normal 1, Hungry 2, Famished 3")
        XCTAssertGreaterThan(MealAppetite.pace(.famished), MealAppetite.pace(.hungry), "famished is eager")
        XCTAssertEqual(NeedTier.of(level: 0.9), .full); XCTAssertEqual(NeedTier.of(level: 0.7), .normal)
        XCTAssertEqual(NeedTier.of(level: 0.35), .hungry); XCTAssertEqual(NeedTier.of(level: 0.1), .famished)
        // the gain: a whole serving from anywhere Famished ends Full; Normal + 1 bite stays in 0.8...1; Hungry + 2 lands 0.8...1
        XCTAssertGreaterThanOrEqual(0 + 3 * MealAppetite.gainPerPiece, NeedsTuning.fullFrom)
        XCTAssertGreaterThanOrEqual(NeedsTuning.famishedBelow + 2 * MealAppetite.gainPerPiece, 0.8)
    }

    /// (tier name, start level, pieces) for food.
    private let cases: [(String, Float, Int)] = [("normal", 0.7, 1), ("hungry", 0.35, 2), ("famished", 0.1, 3)]

    func testFoodBitesPerTier() {
        for (name, level, pieces) in cases {
            let m = setup(hunger: level, thirst: 1)
            m.meal("berries")
            XCTAssertEqual(m.runs { $0.holding }, pieces, "\(name): bites eaten")
            XCTAssertEqual(m.tray.bitesLeft, [3 - pieces], "\(name): the leftovers poof with the tray")
            XCTAssertEqual(m.tray.phase, .absent, "\(name): tray gone")
            let after = m.care.needs.level(.hunger)
            let expected = min(1, level + Float(pieces) * MealAppetite.gainPerPiece)
            XCTAssertEqual(after, expected, accuracy: 0.02, "\(name): the gain is proportional to what was eaten")
            MotionLog.write("DINETIER food \(name): \(level) -> \(after) after \(pieces) bite(s)")
            XCTAssertEqual(m.care.needs.level(.thirst), 1, accuracy: 0.01, "\(name): thirst untouched")
        }
    }

    func testDrinkGulpsPerTier() {
        for (name, level, pieces) in cases {
            let m = setup(hunger: 1, thirst: level)
            m.meal("water")
            let drunk = m.tray.drunk[0]
            XCTAssertEqual(drunk, Float(pieces) / 3, accuracy: 0.02, "\(name): share drunk (a partial drink never empties the bottle)")
            if pieces < 3 { XCTAssertGreaterThan(m.tray.drinkFill, 0.4, "\(name): the bottle is not drained") }
            let after = m.care.needs.level(.thirst)
            XCTAssertEqual(after, min(1, level + Float(pieces) * MealAppetite.gainPerPiece), accuracy: 0.02, "\(name): thirst gain")
            XCTAssertEqual(m.care.needs.level(.hunger), 1, accuracy: 0.01)
        }
    }

    func testFamishedEatsAllAndLandsNearFull() {
        for (id, kind) in [("berries", NeedKind.hunger), ("pizza", .hunger), ("water", .thirst), ("soda", .thirst)] {
            let m = setup(hunger: kind == .hunger ? 0.05 : 1, thirst: kind == .thirst ? 0.05 : 1)
            m.meal(id)
            XCTAssertGreaterThanOrEqual(m.care.needs.level(kind), NeedsTuning.fullFrom, "\(id): famished ends Full")
            XCTAssertEqual(m.care.needs.tier(kind), .full)
        }
    }

    func testFamishedIsFasterPerPiece() {
        func perPiece(_ level: Float, _ pieces: Int) -> Float {
            let m = setup(hunger: level, thirst: 1)
            m.care.eagerWhenFamished = true
            m.meal("berries")
            let d = m.dineFrames
            XCTAssertEqual(m.runs { $0.holding }, pieces)
            let land = d.compactMap { $0.landDist }
            XCTAssertGreaterThanOrEqual(land.count, 3 * pieces, "every bite lands (eager too)")
            XCTAssertLessThan(land.max() ?? 1, 0.03, "the bite still lands in his mouth at the eager pace")
            XCTAssertLessThanOrEqual(d.map { $0.armS }.max() ?? 1, Float(ArmPath.nubGrabS) + 0.001, "the nub never extends")
            return Float(d.count) * m.rig.sim.stepDt / Float(pieces)
        }
        let eager = perPiece(0.05, 3), calm = perPiece(0.35, 2)
        MotionLog.write("DINETIER seconds per bite: famished \(eager), hungry \(calm)")
        XCTAssertLessThan(eager, calm, "a shorter beat between bites when famished")
    }

    /// Full / Quenched: the tray comes, he shakes his head with the label up, nothing is eaten or held, the tray poofs, the need is untouched; the arms
    /// stay stubby and the feet attached over the whole refusal.
    func testFullRefuses() {
        for (id, kind) in [("berries", NeedKind.hunger), ("pizza", .hunger), ("water", .thirst)] {
            let m = setup(hunger: 0.95, thirst: 0.95)
            let before = m.care.needs.level(kind)
            let c = Consumables.with(id: id)!
            if c.kind == .food { m.care.feed(id) } else { m.care.drink(id) }
            var label: String?, trayShown = false, holds = 0, refusingFrames = 0, maxTwist: Float = 0
            var feet = FeetAttachTests.FootFrame(soleRise: -.infinity, centreHeight: -.infinity, radius: 0, overlap: -.infinity), feetFrames = 0
            var armExposed = 0.0, armFrames = 0, armPath = 0
            let started = m.rig.t
            m.run(40) {
                if m.tray.isPresent { trayShown = true }
                if let n = m.care.notice { label = n }
                if m.brain.dineHolding { holds += 1 }
                if m.brain.isRefusing {
                    refusingFrames += 1
                    maxTwist = max(maxTwist, abs(m.brain.dine.cur.twist))
                    if m.brain.armPathActive { armPath += 1 }
                    if let f = FeetAttachTests.footFrame(m.rig) { FeetAttachTests.accumulate(&feet, f); feetFrames += 1 }
                    if m.brain.armG > 0.5 {
                        for si in 0..<2 {
                            let g = m.brain.armLastGeom[si]
                            armExposed = max(armExposed, ArmCap.exposed(a: SIMD3<Double>(g.a), b: SIMD3<Double>(g.b), r2: Double(g.r2))); armFrames += 1
                        }
                    }
                }
                return m.tray.phase == .absent && !m.care.trayOut && m.rig.t - started > 2
            }
            XCTAssertTrue(trayShown, "\(id): the tray still appears")
            XCTAssertEqual(label, MealAppetite.refusalText(kind), "\(id): the label")
            XCTAssertEqual(holds, 0, "\(id): nothing is picked up")
            XCTAssertEqual(m.care.needs.level(kind), before, accuracy: 0.002, "\(id): no need change (only the slow real-time decay)")
            XCTAssertLessThanOrEqual(m.care.needs.level(kind), before, "\(id): never gains")
            XCTAssertEqual(m.tray.phase, .absent, "\(id): the tray poofs")
            XCTAssertGreaterThan(Float(refusingFrames) / 60, 1.2, "\(id): a visible beat")
            XCTAssertGreaterThan(maxTwist, 0.25, "\(id): he shakes his head")
            XCTAssertLessThan(maxTwist, 0.5)
            XCTAssertEqual(armPath, 0, "\(id): no keyframe arm reach")
            XCTAssertEqual(m.brain.mouthOpen, 0)
            XCTAssertNil(m.care.notice, "\(id): the label is gone")
            XCTAssertGreaterThan(feetFrames, 20, "\(id): beans out during the refusal")
            FeetAttachTests.check("refusal \(id)", feet, frames: feetFrames)
            if armFrames > 0 { XCTAssertLessThanOrEqual(armExposed, ArmCap.maximum * 1.02, "\(id): arms stay stubby") }
            XCTAssertTrue(m.tray.pieceInHand.allSatisfy { $0 == nil })
        }
    }

    /// Eating is paid per bite: a Call after one bite keeps that bite's gain.
    func testGainIsPaidPerBite() {
        let m = setup(hunger: 0.05, thirst: 1)
        m.care.feed("berries")
        m.run(40) { m.tray.bitesLeft[0] <= 2 && m.tray.phase == .present }
        m.run(0.2)
        XCTAssertEqual(m.care.needs.level(.hunger), 0.05 + MealAppetite.gainPerPiece, accuracy: 0.02, "one bite eaten so far")
    }
}
