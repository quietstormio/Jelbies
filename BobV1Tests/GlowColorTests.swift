import XCTest
import SwiftUI
@testable import BobV1

/// The voice edge glow colour: every theme keeps its picked hue and is lifted to a clear light (no dark vignette).
final class GlowColorTests: XCTestCase {
    private func hsb(_ hex: UInt32) -> (h: Double, s: Double, b: Double) {
        let r = Double(hex >> 16 & 255) / 255, g = Double(hex >> 8 & 255) / 255, b = Double(hex & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h = h * 60; if h < 0 { h += 360 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    func testEveryPresetGlowIsBrightSaturatedAndKeepsItsHue() {
        for p in ThemePreset.allCases {
            let g = p.glowHSB, o = hsb(p.hex)
            XCTAssertGreaterThanOrEqual(g.b, ThemePreset.glowMinBrightness, "\(p) brightness")
            XCTAssertGreaterThanOrEqual(g.s, ThemePreset.glowMinSaturation, "\(p) saturation")
            var dh = abs(g.h * 360 - o.h); if dh > 180 { dh = 360 - dh }
            XCTAssertLessThan(dh, 3, "\(p) hue moved \(dh) degrees")
        }
    }
}
