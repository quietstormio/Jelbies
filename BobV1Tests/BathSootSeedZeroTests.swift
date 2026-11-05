//
//  BathSootSeedZeroTests.swift
//  Pins the CURRENT soot look for Bob (placement seed 1 = id + 1; re-recorded 2026-11-05 when the per-Jelly first-smear order and wider jitter
//  landed, by user request). Any further shader change to the soot must re-record these on purpose.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class BathSootSeedZeroTests: XCTestCase {
    /// Pixel hashes of Bob's soot frames recorded 2026-11-05 with seed 1 (301 x 655, Bob at (0.4, 0.6)).
    static let baseline = """
room_30 979078aa29af11de
close_30 305130ca11a79673
back_30 7fbc09f22dd97af1
side_30 f894145f2e21c3e1
room_70 2904d113e98f831c
close_70 6ca855165ea5d03e
back_70 a43d09ff0186a551
side_70 2c7cf76ae91e8926
room_95 7327e49e7b14bb40
close_95 ce0b7c57ece9602
back_95 fa0eca2f504d88da
side_95 e4d11e9be85bf31d
"""

    static func fnv(_ img: LockImage) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in img.bgra { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func testBobSootSeedOneMatchesRecordedLook() throws {
        let s = try XCTUnwrap(GfxLabScene(width: 301, height: 655))
        s.place(SIMD2(0.4, 0.6))
        var lines: [String] = []
        for d: Float in [0.3, 0.7, 0.95] {
            for (n, cam) in [("room", BathCaptureTests.roomCam(s)), ("close", BathCaptureTests.roomCam(s, focus: 1)), ("back", BathCaptureTests.orbitCam(s, azimuth: .pi)), ("side", BathCaptureTests.orbitCam(s, azimuth: .pi / 2))] {
                var l = BathCaptureTests.sooty(d); l.sootStyle = BathLook.sootSeed(jelly: 0)
                lines.append("\(n)_\(Int(d * 100)) " + Self.fnv(BathCaptureTests.render(s, look: l, camera: cam)))
            }
        }
        let text = lines.joined(separator: "\n") + "\n"
        XCTAssertEqual(text, Self.baseline + "\n", "Bob's soot changed:\n" + text)
    }
}
