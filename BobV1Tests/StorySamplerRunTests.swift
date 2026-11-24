//
//  StorySamplerRunTests.swift
//  housemate-notes-r1: three home bodies run for a few game minutes through the real brain tick: the habit counters (near / shared / partner) must grow, be saved and survive a reload.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class StorySamplerRunTests: XCTestCase {
    func testThreeHomeBodiesRecordSharedLifeAndItSurvivesAReload() {
        let n = "story.sampler.\(UUID().uuidString)"; let d = UserDefaults(suiteName: n)!; d.removePersistentDomain(forName: n)
        let store = StoryHabitStore.shared
        let oldDefaults = store.defaults, oldResolve = store.resolve
        store.reset(); store.defaults = d; store.resolve = { $0 }
        defer { store.reset(); store.defaults = oldDefaults; store.resolve = oldResolve }
        let lab = SocialTests.Lab(n: 3, positions: [SIMD2(-1.2, 0.5), SIMD2(0.4, 1.0), SIMD2(1.6, 0.4)], quiet: false, seed: 21)
        for r in lab.rigs { r.brain.homeRoom = true }
        for _ in 0..<(60 * 60 * 3) { lab.tick() }          // three game minutes
        store.flush()
        for id in 0..<3 {
            let h = store.habits(id)
            XCTAssertGreaterThan(h.total, 100, "body \(id) was sampled")
            let others = (0..<3).filter { $0 != id }
            for o in others { XCTAssertGreaterThan(h.sharedEver(with: o), 0, "body \(id) shared time with \(o): near \(h.near ?? [:]) partner \(h.partner)") }
        }
        // saved and read back from the defaults (a relaunch)
        let before = store.habits(0)
        store.reset()
        let after = store.habits(0)
        XCTAssertEqual(after.total, before.total, accuracy: 1)
        XCTAssertEqual(after.shared, before.shared)
        NSLog("[storysample-test] total %.0f near %@ shared %@ partner %@", after.total, "\(after.near ?? [:])", "\(after.shared ?? [:])", "\(after.partner)")
    }
}
