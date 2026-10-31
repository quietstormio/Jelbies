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
//    C1    "Tall oval":     B2's tone and edge as ONE marking from the belly up to the forehead, about B2's width all the way
//    C2    "Egg":           the same, B2's width at the belly narrowing toward the forehead
//    C2w / C2ww  the egg about 12 % / 22 % wider (belly half-width 0.375 / 0.41, forehead 0.32 / 0.35); C2w3 / C2w4 about 32 % / 42 % (0.44 / 0.475, forehead 0.38 / 0.41)
//  Light tone = the shaded body blue taken 40 % (A), 36 % (B1) or 44 % (B2) toward white, in the shader (so it is always derived from the real body colour).
//  DEBUG capture aid: launch with `-BlueBelly off|A|B1|B2|C1|C2|C2w|C2ww|C2w3|C2w4`.
//

import Foundation

nonisolated enum BlueBelly: Int, CaseIterable {
    case off = 0, front, bellySubtle, bellyClear, tallOval, egg, eggWide, eggWider, eggW3, eggW4
    /// Darker, still-blue tones of the two widest eggs (raw value = shape mode + 10 x tone: 1 = D1, 2 = D2).
    case eggW3D1 = 18, eggW3D2 = 28, eggW4D1 = 19, eggW4D2 = 29

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
        case "c1": return .tallOval
        case "c2": return .egg
        case "c2w": return .eggWide
        case "c2ww": return .eggWider
        case "c2w3": return .eggW3
        case "c2w4": return .eggW4
        case "c2w3d1": return .eggW3D1
        case "c2w3d2": return .eggW3D2
        case "c2w4d1": return .eggW4D1
        case "c2w4d2": return .eggW4D2
        default: return nil
        }
    }

    /// The baby blue body colour (lit tone): the one palette that gets the patch.
    static let blueFlesh: SIMD3<Float> = PaletteKey.blue.palette.flesh

    /// The shader mode for a body painted with `palette` (0 = none).
    @inline(__always) static func mode(for palette: Palette) -> Float {
        // Teddy (the light-brown species) always has the clear belly oval (B2's shape, clear of the mouth) in a warm cream-tan lift of the shaded body (tone 3), whatever the blue mockup says
        if palette.flesh == TeddyLook.current.flesh { return TeddyEarsVariant.active == .cream ? 43 : 33 }        // 43 = the same plus the cream inner ear (tone 4, shader teddyEarMask)        // shape 3 (clear oval) in tone 3 (warm cream-tan)
        let c = current
        return c == .off || palette.flesh != blueFlesh ? 0 : Float(c.rawValue)
    }
}
