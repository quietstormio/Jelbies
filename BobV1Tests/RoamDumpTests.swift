//
//  RoamDumpTests.swift
//  Not a regression test: dumps the roaming polygon (rows, half widths, screen numbers) when ROAM_DUMP_DIR is set (TEST_RUNNER_ROAM_DIR).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RoamDumpTests: XCTestCase {
    override func tearDown() { GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0) }

    func testDumpRoam() throws {
        guard let d = ProcessInfo.processInfo.environment["ROAM_DUMP_DIR"], !d.isEmpty else { throw XCTSkip("ROAM_DUMP_DIR not set") }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        let tag = ProcessInfo.processInfo.environment["ROAM_DUMP_TAG"] ?? "old"
        for (name, aspect) in [("port", Float(440.0 / 956.0)), ("land", Float(956.0 / 440.0))] {
            GameCamera.configureRoom(count: 3, option: .A, wide: 2)
            _ = GameCamera.camera(aspect: aspect)
            guard let rf = GameCamera.refreshRoam(aspect: aspect) else { return XCTFail("no polygon") }
            let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
            var rows = [[String: Float]]()
            for (z, h) in zip(rf.zs, rf.hw) { rows.append(["z": z, "hw": h]) }
            func hgt(_ z: Float) -> Float {
                let a = GameCamera.screenPoint(floor: SIMD2(0, z), y: 0, size: size)!, b = GameCamera.screenPoint(floor: SIMD2(0, z), y: 1.25, size: size)!
                return Float(a.y - b.y) / 1000
            }
            let info: [String: Any] = ["aspect": aspect, "rows": rows, "minZ": rf.minZ, "maxZ": rf.maxZ,
                                       "bodyHeightFracAtCentre": hgt(0), "bodyHeightFracAtFront": hgt(rf.maxZ), "bodyHeightFracAtBack": hgt(rf.minZ),
                                       "frontFloorYFrac": Float(GameCamera.screenPoint(floor: SIMD2(0, rf.maxZ + 0.75), size: size)!.y) / 1000]
            let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: d + "/roam_\(tag)_\(name).json"))
        }
    }
}
