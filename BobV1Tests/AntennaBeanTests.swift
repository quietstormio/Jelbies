//
//  AntennaBeanTests.swift
//  The green Jelmiko's two jelly antennas (AntennaBean): collapsed for everyone else, standing out, mirrored and rooted in the head when bare, never stretching or detaching over a walk +
//  hop + drop, wobbling (the tips lag the head), and the hat rule (AntennaFit): tucked under an enclosing hat and the antennae / ear headbands, out under nothing.
//

import XCTest
import simd
@testable import BobV1

extension FeatureCaptureTests {
    func antennaBlock(_ sk: [Float]) -> [[SIMD3<Float>]] {
        let f = MotionRig.renderMesh.armCapsule!.antennaFirst
        return AntennaBean.parts.map { part in
            (0..<part.count).map { let o = 6 * (f + part.first + $0); return SIMD3(sk[o], sk[o + 1], sk[o + 2]) }
        }
    }

    func testAntennasCollapsedForEveryOtherSpecies() throws {
        DayClock.shared.forcedHour = 12
        for id in [0, 1, 3, 4, 5] {
            let c = Char(id: id)
            let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
            let d = dress(lab, [c]); let r = lab.rigs[0]
            for _ in 0..<40 { lab.tick(watching: false); tick(d, 0, r, c) }
            XCTAssertFalse(r.skinner.antennaOn, "character \(id) has no antennas")
            for (pi, part) in antennaBlock(skin(r)).enumerated() {
                var worst: Float = 0
                for v in part.dropFirst() { worst = max(worst, simd_distance(v, part[0])) }
                XCTAssertLessThan(worst, 1e-4, "character \(id): antenna \(pi) is collapsed onto its pole")
            }
        }
    }

    func testAntennasBareStandMirroredAndRooted() throws {
        DayClock.shared.forcedHour = 12
        let c = Char(id: 2)
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
        let d = dress(lab, [c]); let r = lab.rigs[0]
        for _ in 0..<120 { lab.tick(watching: false); tick(d, 0, r, c) }
        XCTAssertTrue(r.skinner.antennaOn)
        XCTAssertEqual(r.skinner.antennaScale, 1, accuracy: 1e-4)
        let sk = skin(r)
        let blk = antennaBlock(sk)
        let tips = blk.map { $0[AntennaBean.parts[0].tipPole] }
        let c0 = r.sim.centroid()
        XCTAssertGreaterThan(tips[0].y - c0.y, 0.8, "the ball is well above the body centre")
        // mirrored about the body's own middle (a standing Jelmiko, little sway): the two tips are on opposite sides, about equally high
        XCTAssertLessThan(tips[0].x * tips[1].x, 0, "the tips are left and right")
        XCTAssertEqual(tips[0].y, tips[1].y, accuracy: 0.12, "both about equally high")
        // rooted: the first visible ring (s = 0) of each antenna lies on the head skin (within 6 cm of an egg vertex)
        let nEgg = eggVertexLimit()
        for part in AntennaBean.parts {
            let f = MotionRig.renderMesh.armCapsule!.antennaFirst
            let ringIdx = part.s.firstIndex(where: { $0 >= 0 })!
            var best = Float.infinity
            let o = 6 * (f + part.first + part.ringFirst + ringIdx * AntennaBean.around)
            let q = SIMD3(sk[o], sk[o + 1], sk[o + 2])
            for v in 0..<nEgg { best = min(best, simd_distance(q, SIMD3(sk[6 * v], sk[6 * v + 1], sk[6 * v + 2]))) }
            XCTAssertLessThan(best, 0.06, "\(part.name) root ring sits on the head")
        }
    }

    /// Walk, hop-ish drop and a turn: the stalk length (base pole to ball) stays within a bound of its rest length (it bends, never stretches), the ball never separates from its
    /// stalk, and the tips actually move relative to the head (the wobble).
    func testAntennasNeverStretchOverWalkAndDrop() throws {
        DayClock.shared.forcedHour = 12
        let c = Char(id: 2)
        let lab = setUpLab([SIMD2(-0.6, 0.4)], chars: [c], seed: 3)
        let d = dress(lab, [c]); let r = lab.rigs[0]
        let restLen = AntennaBean.parts.map { simd_distance(AntennaBean.localF[$0.first + $0.tipPole], AntennaBean.localF[$0.first]) }
        r.brain.requestNow(.goTo(SIMD2(0.9, 1.3)))
        var worst: Float = 0, spread: Float = 0, minRel: Float = .infinity, maxRel: Float = -.infinity
        for k in 0..<420 {
            lab.tick(watching: false); tick(d, 0, r, c)
            if k == 150 { r.brain.requestNow(.goTo(SIMD2(-0.7, 1.5))) }
            if k == 260 { for i in 0..<r.sim.n { r.sim.x[3 * i + 1] += 0.7 } }          // a drop
            let blk = antennaBlock(skin(r))
            for (pi, part) in blk.enumerated() {
                let len = simd_distance(part[AntennaBean.parts[pi].tipPole], part[0])
                worst = max(worst, abs(len / restLen[pi] - 1))
                let rel = (part[AntennaBean.parts[pi].tipPole] - r.sim.centroid()).x * (pi == 0 ? 1 : -1)
                minRel = min(minRel, rel); maxRel = max(maxRel, rel)
                for v in part { XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite) }
            }
            spread = max(spread, abs(simd_length(blk[0][AntennaBean.parts[0].tipPole] - blk[1][AntennaBean.parts[1].tipPole])))
        }
        print("[antennas] worst length change \(worst), tip outward range \(minRel)...\(maxRel), max tip gap \(spread)")
        XCTAssertLessThan(worst, 0.20, "the stalk bends, it never stretches (head squash included)")
        XCTAssertGreaterThan(maxRel - minRel, 0.03, "the tips wobble")
    }

    func testAntennaHatRule() throws {
        AntennaFit.clearCache()
        XCTAssertFalse(AntennaFit.tucked(worn: []), "bare: out")
        XCTAssertTrue(AntennaFit.tucked(worn: ["beanie_honey"]), "an enclosing beanie tucks them")
        XCTAssertTrue(AntennaFit.tucked(worn: ["bee_antennae"]), "the bee headband carries its own antennae: no four antennas")
        XCTAssertTrue(AntennaFit.tucked(worn: ["bunny_ears"]), "ear headbands tuck them")
        XCTAssertFalse(AntennaFit.tucked(worn: ["scarf_cosy"]), "a neck piece does not touch them")
        // the drive follows the rule with the pop fade: beanie on -> scale falls to 0, off -> back to 1
        DayClock.shared.forcedHour = 12
        let c = Char(id: 2)
        let lab = setUpLab([SIMD2(0.2, 0.6)], chars: [c], seed: 3)
        let d = dress(lab, [c]); let r = lab.rigs[0]
        for _ in 0..<30 { lab.tick(watching: false); d.feats[0].tick(id: 0, brain: r.brain, sim: r.sim, feature: .daisy, worn: ["beanie_honey"], hideAll: false, dt: 1.0 / 60) }
        XCTAssertEqual(r.brain.antennaScale, 0, accuracy: 1e-3)
        for _ in 0..<60 { lab.tick(watching: false); d.feats[0].tick(id: 0, brain: r.brain, sim: r.sim, feature: .daisy, worn: [], hideAll: false, dt: 1.0 / 60) }
        XCTAssertEqual(r.brain.antennaScale, 1, accuracy: 1e-3)
    }

    func testAntennaBlockBudget() {
        print("[antennas] block vertices \(AntennaBean.vertexCount), triangles \(AntennaBean.built.block.tri.count / 3), body mesh vertices \(MotionRig.renderMesh.vertexCount)")
        XCTAssertLessThan(AntennaBean.vertexCount, 800)
    }
}
