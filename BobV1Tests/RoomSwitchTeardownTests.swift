//
//  RoomSwitchTeardownTests.swift
//  RoomSwitch is a @MainActor @Observable class. Without `nonisolated deinit {}` its deinit is an ISOLATED deinit: the runtime enters
//  swift_task_deinitOnExecutor, and tearing a GameCare down (which owns one) crashed in the runtime with
//  "pointer being freed was not allocated" (StopLookupScope) in StoreTests / DiningFlowTests.testBerriesByFinger.
//  Every other Observable model in the app already opts out; this pins RoomSwitch (and LaunchGate) to the same rule: dropping them on ANY thread is safe.
//

import XCTest
@testable import BobV1

final class RoomSwitchTeardownTests: XCTestCase {
    /// Released off the main actor, in bulk, the way a test's GameCare goes away.
    func testRoomSwitchCanBeReleasedOffTheMainActor() async {
        for _ in 0..<20 {
            let box = await MainActor.run { Box(RoomSwitch()) }
            await Task.detached { _ = box.value; box.value = nil }.value
        }
    }

    func testLaunchGateCanBeReleasedOffTheMainActor() async {
        for _ in 0..<20 {
            let box = await MainActor.run { Box(LaunchGate(clock: { 0 })) }
            await Task.detached { box.value = nil }.value
        }
    }

    @MainActor func testGameCareTeardownLoop() {
        for _ in 0..<25 {
            var care: GameCare? = GameCare(jellyCount: 1, persistent: false)
            care?.roomSwitch.begin(to: .loft)
            care = nil
        }
    }

    private final class Box<T: AnyObject>: @unchecked Sendable {
        var value: T?
        init(_ v: T) { value = v }
    }
}
