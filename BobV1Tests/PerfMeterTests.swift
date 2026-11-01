import XCTest
@testable import BobV1

final class PerfMeterTests: XCTestCase {
    func testWindowLineHasAllFields() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf_test_\(UUID().uuidString).jsonl")
        let m = PerfMeter()
        m.logURL = url; m.windowSeconds = 1e6          // flush by hand
        PerfMeter.on = true
        defer { PerfMeter.on = false; PerfMeter.context = nil; try? FileManager.default.removeItem(at: url) }
        PerfMeter.context = { PerfContext(scene: "room", jelbies: 3, preferredFPS: 60, maxFPS: 120, renderScale: 2.5, tier: "test") }
        var t = mach_absolute_time()
        for i in 0..<60 {
            t += UInt64(i % 7 == 0 ? 700_000 : 400_000)          // mach ticks
            m.beginFrame(t)
            for s in PerfStage.allCases { let s0 = mach_absolute_time(); usleep(20); m.cur[s.rawValue] += Double(mach_absolute_time() - s0) * 1e-5 }
            m.endFrame(t + 50_000)
            m.addGPU(Double(5 + i % 4))
        }
        let line = try XCTUnwrap(m.flush())
        for k in ["t", "scene", "jelbies", "device", "ios", "thermal", "low_power", "preferred_fps", "max_fps", "render_scale", "tier", "frames", "interval_ms", "pct_over_16_7ms", "pct_over_33ms", "frame_cpu_ms", "stages_cpu_ms", "gpu_ms", "longest_frame"] {
            XCTAssertNotNil(line[k], k)
        }
        let iv = try XCTUnwrap(line["interval_ms"] as? [String: Double])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(iv["p95"]), try XCTUnwrap(iv["p50"]))
        XCTAssertEqual(line["frames"] as? Int, 59)          // the first frame has no interval
        let st = try XCTUnwrap(line["stages_cpu_ms"] as? [String: Any])
        for s in PerfStage.allCases { XCTAssertNotNil(st[s.name], s.name) }
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["scene"] as? String, "room")
        m.writeSummary()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count, 2)
    }

    func testOffCostsNothing() {
        PerfMeter.on = false
        XCTAssertEqual(PerfMeter.begin(), 0)
    }
}
