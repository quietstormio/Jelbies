//
//  BathSootSeedZeroTests.swift
//  Bob's soot (style 0) must render exactly as it did before the per-Jelly placement seed existed. The frames' pixel hashes were recorded
//  from the code BEFORE that change; this test re-renders them and compares.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class BathSootSeedZeroTests: XCTestCase {
    /// Pixel hashes of Bob's soot frames recorded from the code before the per-Jelly seed existed (301 x 655, Bob at (0.4, 0.6)).
    static let baseline = """
room_30 ae3421c0dfeee476
close_30 90bf003cf2f3f02e
back_30 50df78fdfb9608de
side_30 a07f72ebc97c6c2f
room_70 fee3fd61b7cf9707
close_70 ceb632531c51980d
back_70 159a053c8d58f292
side_70 8990d7bc1e4b77f5
room_95 1fe88fd8b71c9ec5
close_95 641234f112c58dc9
back_95 ee9cc67379a6371b
side_95 542950caec71c9cd
"""

    static func fnv(_ img: LockImage) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in img.bgra { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func testBobSootStyleZeroIsPixelIdenticalToBefore() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        var lines: [String] = []
        for d: Float in [0.3, 0.7, 0.95] {
            for (n, cam) in [("room", BathCaptureTests.roomCam(s)), ("close", BathCaptureTests.roomCam(s, focus: 1)), ("back", BathCaptureTests.orbitCam(s, azimuth: .pi)), ("side", BathCaptureTests.orbitCam(s, azimuth: .pi / 2))] {
                lines.append("\(n)_\(Int(d * 100)) " + Self.fnv(BathCaptureTests.render(s, look: BathCaptureTests.sooty(d), camera: cam)))
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        XCTAssertEqual(text, Self.baseline + "\n", "Bob's soot changed")
    }
}
