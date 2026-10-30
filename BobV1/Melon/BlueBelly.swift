//
//  BlueBelly.swift
//  MOCKUP (user picks before anything ships): a lighter blue on the front of the blue species (character 0, Bob / Blueberry) for distinction.
//  The shaders (Shaders.metal, GfxBodyFast.metal, GfxJersey.metal, BathShaders.metal) draw it in rest space like the blush, so it follows the body
//  as it squishes and never slides. It rides in `u.shape.w` (the body shaders never read `shape`), set by `MelonRenderer.applyPalette` for any body
//  whose palette is the baby blue; every other colour gets 0 (pixel-identical to before). No per-frame allocation: one enum compare and one vector compare.
//    off   no patch (the shipped look, and the default until the user picks)
//    A     "Front":         the whole front of the body, blending softly round the sides
//    B1    "Belly, subtle": a soft-edged lighter oval on the lower front belly
//    B2    "Belly, clear":  the same oval, a bit larger, lighter and crisper
//  Light tone = the shaded body blue taken 40 % (A), 36 % (B1) or 44 % (B2) toward white, in the shader (so it is always derived from the real body colour).
//  DEBUG capture aid: launch with `-BlueBelly off|A|B1|B2`.
//

import Foundation

nonisolated enum BlueBelly: Int, CaseIterable {
    case off = 0, front, bellySubtle, bellyClear

    /// The variant in force. Off until the user picks; tests / captures set it directly.
    nonisolated(unsafe) static var current: BlueBelly = launchValue

    static let launchValue: BlueBelly = {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "BlueBelly") { return parse(s) ?? .off }
        #endif
        return .off
    }()

    static func parse(_ s: String) -> BlueBelly? {
        switch s.lowercased() {
        case "off", "0", "none": return .off
        case "a", "front": return .front
        case "b1": return .bellySubtle
        case "b2": return .bellyClear
        default: return nil
        }
    }

    /// The baby blue body colour (lit tone): the one palette that gets the patch.
    static let blueFlesh: SIMD3<Float> = PaletteKey.blue.palette.flesh

    /// The shader mode for a body painted with `palette` (0 = none).
    @inline(__always) static func mode(for palette: Palette) -> Float {
        let c = current
        return c == .off || palette.flesh != blueFlesh ? 0 : Float(c.rawValue)
    }
}
