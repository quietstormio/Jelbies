//
//  ReleaseSwitchesTests.swift
//  Saved PerfLog / FootLog flags and the -ShowAuto / -ShowRank / -ParkToys capture arguments act only where dev arguments are on.
//

import XCTest
@testable import BobV1

@MainActor
final class ReleaseSwitchesTests: XCTestCase {
    private func suite() -> (UserDefaults, () -> Void) {
        let n = "ReleaseSwitchesTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        return (d, { d.removePersistentDomain(forName: n) })
    }

    func testSavedLogFlagsNeedTheDevSwitch() {
        let (d, done) = suite(); defer { done() }
        let wasP = PerfMeter.on, wasF = FootLog.on; defer { PerfMeter.on = wasP; FootLog.on = wasF }
        d.set(true, forKey: "PerfLog"); d.set(true, forKey: "FootLog")
        PerfMeter.configure(defaults: d, devArgs: false); FootLog.configure(defaults: d, devArgs: false)
        XCTAssertFalse(PerfMeter.on); XCTAssertFalse(FootLog.on)
        XCTAssertTrue(d.bool(forKey: "PerfLog"), "the saved value is left alone")
        FootLog.configure(defaults: d, devArgs: true)
        XCTAssertTrue(FootLog.on)
        PerfMeter.on = false
    }

    func testShowCaptureArgumentsNeedTheDevSwitch() {
        let (d, done) = suite(); defer { done() }
        d.set(1, forKey: "ShowAuto"); d.set("ocean", forKey: "ShowRank")
        XCTAssertFalse(ShowCaptureArgs.auto(devArgs: false, defaults: d)); XCTAssertNil(ShowCaptureArgs.rank(devArgs: false, defaults: d))
        XCTAssertTrue(ShowCaptureArgs.auto(devArgs: true, defaults: d)); XCTAssertEqual(ShowCaptureArgs.rank(devArgs: true, defaults: d), .ocean)
    }

    func testParkToysNeedsTheDevSwitch() {
        let (d, done) = suite(); defer { done() }
        d.set("seesaw", forKey: "ParkToys")
        XCTAssertFalse(ParkVisitPlan.allInPlayAlways(devArgs: false, defaults: d, environment: [:]))
        XCTAssertTrue(ParkVisitPlan.allInPlayAlways(devArgs: true, defaults: d, environment: [:]))
        XCTAssertTrue(ParkVisitPlan.allInPlayAlways(devArgs: false, defaults: d, environment: ["XCTestConfigurationFilePath": "x"]))
    }

    func testFoodCaptureArgumentsNeedTheDevSwitch() {
        let (d, done) = suite(); defer { done() }
        d.set(1, forKey: "FoodSeed")
        XCTAssertFalse(FoodCaptureArgs.foodSeed(devArgs: false, defaults: d)); XCTAssertTrue(FoodCaptureArgs.foodSeed(devArgs: true, defaults: d))
        XCTAssertNil(FoodCaptureArgs.feedID("feed:sushi", devArgs: false)); XCTAssertEqual(FoodCaptureArgs.feedID("feed:sushi", devArgs: true), "sushi")
        XCTAssertNil(FoodCaptureArgs.feedID("clean", devArgs: true))
    }
}
