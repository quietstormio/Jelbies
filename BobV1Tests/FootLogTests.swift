//
//  FootLogTests.swift
//  FootLog (Melon/FootLog.swift): a displaced foot piece writes a foot_log.jsonl line with the documented fields; a clean frame writes nothing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FootLogTests: XCTestCase {
    private func tempLog() -> FootLog {
        let log = FootLog()
        log.url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foot_log_test_\(UUID().uuidString).jsonl")
        return log
    }
    private func lines(_ log: FootLog) -> [[String: Any]] {
        guard let d = try? Data(contentsOf: log.url), let s = String(data: d, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    func testDisplacedPieceWritesALineAndCleanFramesWriteNothing() throws {
        let was = FootLog.on; FootLog.on = true; defer { FootLog.on = was }
        FootLog.lastIntervalMs = 16.7
        var checked = false, cleanChecked = false
        let sc = OnePieceInvariantTests.gaitScenario("walk")!
        _ = OnePieceInvariantTests.run(sc, char: 4, shoes: false, pacing: .hz60, seed: 3) { frame, r, f in
            guard !checked, f.beans, f.blend > 0.9, frame > 40 else { return }
            // clean frame first: nothing displaced (the brain's own placement), the walk is not leashed
            r.render()
            let clean = self.tempLog()
            clean.recordOne(id: 7, skinner: r.skinner, brain: r.brain, now: 1, dt: 1.0 / 60, scene: "room")
            if r.skinner.joinLeash == [0, 0] && r.skinner.weldPull == [0, 0] && r.skinner.leashPre.allSatisfy({ $0 >= 1 || $0 >= 0 }) {
                XCTAssertEqual(self.lines(clean).count, 0, "no line when every piece is inside the body")
                cleanChecked = true
            }
            // now throw the left piece 40 cm out of the body
            checked = true
            var c = SIMD3<Float>.zero
            for i in 0..<FootBean.vertexCount { c += r.skinner.beanPos[0][i] }
            c /= Float(FootBean.vertexCount)
            let away = simd_normalize(c - r.sim.bodyPose(iterations: 4).centroid) * 0.4
            for i in 0..<FootBean.vertexCount { r.skinner.beanPos[0][i] += away; r.skinner.beanStart[0][i] += away }
            r.render()
            let log = self.tempLog()
            log.recordOne(id: 7, skinner: r.skinner, brain: r.brain, now: 2, dt: 1.0 / 60, scene: "room")
            let ls = self.lines(log)
            XCTAssertGreaterThanOrEqual(ls.count, 1, "a displaced piece writes a line")
            if let l = ls.first {
                XCTAssertEqual(l["piece"] as? String, "footL")
                XCTAssertEqual(l["actor"] as? Int, 7)
                XCTAssertEqual(l["scene"] as? String, "room")
                XCTAssertEqual(l["interval_ms"] as? Double, 16.7)
                XCTAssertGreaterThan((l["leash_cm"] as? Double ?? 0) + (l["tether_cm"] as? Double ?? 0) + (l["gap_cm"] as? Double ?? 0), 5)
                for k in ["t", "species", "gap_cm", "leash_cm", "tether_cm", "pole_hip_cm", "script", "idle", "activity", "gait_phase", "gait_busy", "volley", "volley_phase", "shoes", "tilt", "dt_ms", "blend", "thermal"] {
                    XCTAssertNotNil(l[k], "field \(k)")
                }
            }
            XCTAssertTrue(log.summary.hasPrefix("feet[") && !log.summary.contains("none"), log.summary)
            XCTAssertEqual(self.tempLog().summary, "feet[none]")
        }
        XCTAssertTrue(checked, "the displaced-piece check ran")
        XCTAssertTrue(cleanChecked, "the clean-frame check ran")
    }

    /// The move timeline: a hop then a flip give "move" lines naming them, with wall-clock stamps.
    func testMoveTimelineNamesHopThenFlip() throws {
        let was = FootLog.on; FootLog.on = true; defer { FootLog.on = was }
        let log = tempLog()
        let r = MotionRig(game: true, settle: 0.5)
        func tickLog() { r.tick(); log.recordMove(id: 3, key: 3, brain: r.brain, asleep: false, now: Double(r.t), scene: "room") }
        tickLog()
        r.brain.startHopPlay(sim: r.sim)
        for _ in 0..<240 { tickLog() }
        r.brain.startFlip(sim: r.sim)
        for _ in 0..<240 { tickLog() }
        let ms = lines(log).filter { $0["ev"] as? String == "move" }
        let tos = ms.compactMap { $0["to"] as? String }
        XCTAssertTrue(tos.contains { $0.hasPrefix("hopPlay") }, "hop named: \(tos)")
        XCTAssertTrue(tos.contains { $0.hasPrefix("flipPlay") }, "flip named: \(tos)")
        XCTAssertLessThan(tos.firstIndex { $0.hasPrefix("hopPlay") } ?? 99, tos.firstIndex { $0.hasPrefix("flipPlay") } ?? -1, "hop before flip")
        for k in ["t", "local", "id", "species", "from", "to", "scene", "interval_ms"] { XCTAssertNotNil(ms.first?[k], "field \(k)") }
        XCTAssertEqual((ms.first?["local"] as? String)?.count, 8)
        // unchanged move writes nothing
        let n = lines(log).count
        for _ in 0..<5 { log.recordMove(id: 3, key: 3, brain: r.brain, asleep: false, now: 0, scene: "room") }
        XCTAssertEqual(lines(log).count, n)
    }
}
