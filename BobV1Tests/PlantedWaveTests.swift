//
//  PlantedWaveTests.swift
//  "Watch arms and feet" (user): on the Jelly Spring (very large pedestal view) the hello wave's lifted foot piece reads as a loose lump. `BlobBrain.plantedWave` (set by
//  `GameCare.plantedWave`, from `ShowcaseStage(plantedWave:)`, from `AdoptionCenter.springPlantedWave`) keeps both feet planted for the wave only; everywhere else the wave lifts as before.
//    1. planted: every frame of a full wave has foot lift 0 (so swing 0 and tilt 0: they are `lift * constant`), no bean request from the wave, the same arm path values and the same end time as unplanted,
//    2. unplanted (the default): the wave's foot lift is `WaveScript.footLift(armT)` frame for frame, and two seeded runs agree on every number,
//    3. the Jelly Spring builds its stage planted (`AdoptionCenter.springPlantedWave`, `ShowcaseStage.plantedWave`); the REAL stage (a View in a running app) is checked on the phone line, see the notes,
//    4. `-SpringWaveFoot 1` (UserDefaults "SpringWaveFoot") restores the lift on the Spring.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class PlantedWaveTests: XCTestCase {
    struct Frame: Equatable { var armT: Float; var lift: Float; var asked: Bool; var s0: Float; var s1: Float }
    struct Run { var frames: [Frame] = []; var endFrame = -1; var armSide = 0 }

    func waveRun(planted: Bool) -> Run {
        UserDefaults.standard.set(1, forKey: "BlobWaveSide")
        defer { UserDefaults.standard.removeObject(forKey: "BlobWaveSide") }
        let r = WaveInterruptTests.rig(.none)
        let b = r.brain
        b.plantedWave = planted
        b.request(.wave)
        var run = Run(), started = false
        for n in 0..<(60 * 8) {
            r.tick(); r.render()
            if b.armActive { started = true; run.armSide = b.armSide }
            if started, b.armActive || WaveInterruptTests.isWave(b) {
                run.frames.append(Frame(armT: b.armT, lift: b.waveLiftApplied, asked: b.waveAskedBeans, s0: b.armSkinS[0], s1: b.armSkinS[1]))
            }
            if started, !b.armActive, !WaveInterruptTests.isWave(b) { run.endFrame = n; break }
        }
        return run
    }

    // 1
    func testPlantedWaveNeverLiftsOrAsksForABean() {
        let planted = waveRun(planted: true), old = waveRun(planted: false)
        XCTAssertGreaterThan(planted.frames.count, 60, "the wave ran")
        for (i, f) in planted.frames.enumerated() {
            XCTAssertEqual(f.lift, 0, "frame \(i): foot lift (swing and tilt are lift x constant)")
            XCTAssertFalse(f.asked, "frame \(i): the wave asked for a foot piece")
        }
        // the arm goes through its full path and the script ends at the same time
        XCTAssertEqual(planted.frames.map(\.armT), old.frames.map(\.armT))
        XCTAssertEqual(planted.frames.map(\.s0), old.frames.map(\.s0))
        XCTAssertEqual(planted.frames.map(\.s1), old.frames.map(\.s1))
        XCTAssertEqual(planted.endFrame, old.endFrame)
        XCTAssertGreaterThan(old.frames.map(\.lift).max() ?? 0, 0.95, "sanity: the unplanted wave does lift")
        XCTAssertTrue(old.frames.contains { $0.asked }, "sanity: the unplanted wave asks for the foot piece")
    }

    // 2
    func testUnplantedWaveIsTodaysWaveFrameForFrame() {
        let a = waveRun(planted: false), b = waveRun(planted: false)
        XCTAssertEqual(a.frames, b.frames, "seeded runs agree on every number")
        XCTAssertFalse(BlobBrain().plantedWave, "default is false")
        for (i, f) in a.frames.enumerated() where f.lift != 0 || f.armT > 0.3 {
            XCTAssertEqual(f.lift, WaveScript.footLift(at: f.armT), accuracy: 1e-6, "frame \(i)")
        }
    }

    // 3
    func testTheSpringBuildsItsStagePlanted() {
        UserDefaults.standard.removeObject(forKey: "SpringWaveFoot")
        XCTAssertTrue(AdoptionCenter.springPlantedWave)
        XCTAssertFalse(ShowcaseStage(roster: [0]).plantedWave, "other showcase stages keep the lift")
        XCTAssertTrue(ShowcaseStage(roster: [0], plantedWave: AdoptionCenter.springPlantedWave).plantedWave)
        let care = GameCare(roster: [0], persistent: false, preview: true)
        XCTAssertFalse(care.plantedWave)
        // (that AdoptionCenter passes it at `ShowcaseStage(...)`, and that a page switch's rebuilt stage keeps it, is the real-app check: no unit test can build that View)
    }

    // 4
    func testSpringWaveFootSwitchRestoresTheLift() {
        UserDefaults.standard.set(true, forKey: "SpringWaveFoot")
        defer { UserDefaults.standard.removeObject(forKey: "SpringWaveFoot") }
        XCTAssertFalse(AdoptionCenter.springPlantedWave)
        let run = waveRun(planted: AdoptionCenter.springPlantedWave)
        XCTAssertGreaterThan(run.frames.map(\.lift).max() ?? 0, 0.95)
    }
}
