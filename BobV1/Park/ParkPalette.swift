//
//  ParkPalette.swift
//  LOOK-DEV ONLY (branch park-palette-lab, never merged as is): the park's man-made pieces (bench, lamp, fence, gate piers, path edging, rocks, slide, seesaw, hopscotch court, blooms) in ONE shared
//  colour scheme, as dev-switchable variants for pictures. Launch argument `-ParkPalette <today|room|ui|meadow|green>`; `-ParkPaletteTint r,g,b` (0...1) overrides the tint of `ui`.
//  Absent or unknown = `today`: `current` is nil and every call site keeps its OLD literal (`ParkPalette.current?.role ?? <old literal>`), so the default park is bit-identical.
//  Roles are sRGB floats; call sites convert with `ParkShapes.srgb` / `OKLab.srgbToLinear` exactly as they did for the old literals.
//

import simd
import Foundation

nonisolated enum ParkPalette {
    enum Variant: String { case today, room, ui, meadow, green }

    struct Colours {
        /// dark structure: bench frames, lamp post, slide posts, seesaw bumpers, fence
        var frame: SIMD3<Float>
        /// bench slats, slide timber + step, seesaw beam + fulcrum
        var wood: SIMD3<Float>
        /// the main accent: slide chute, seesaw cushions
        var seat: SIMD3<Float>
        /// light: seesaw handles / caps, slide side walls, gate pier caps, chalk lines, lamp glass rim
        var trim: SIMD3<Float>
        /// piers, path edging, rocks
        var stone: SIMD3<Float>
        /// the hopscotch asphalt (its own darkness: chalk / asphalt contrast stays >= 4.5)
        var asphalt: SIMD3<Float>
        /// the three bloom tints (cream / gold / violet slots)
        var bloom: [SIMD3<Float>]
        /// the hopscotch numbers
        var chalkNumber: SIMD3<Float>
    }

    /// The variant chosen at launch (read once).
    static let variant: Variant = {
        let s = (UserDefaults.standard.string(forKey: "ParkPalette") ?? "today").lowercased()
        return Variant(rawValue: s) ?? .today
    }()

    /// nil = today: the caller keeps its old literal.
    static let current: Colours? = {
        switch variant {
        case .today: return nil
        case .room: return fromSwatches(RoomTheme())
        case .ui: return fromSwatches(RoomTheme(tint: uiTint))
        case .green: return fromSwatches(RoomTheme(tint: SIMD3(0.56, 0.74, 0.44), chromaScale: 0.7, lightnessShift: 0.02))
        case .meadow:
            let accent = hex(0x6EB3D1), cream = hex(0xF7F0E0), frame = hex(0x3D4A44)
            let light = toSrgb(mixLinear(OKLab.srgbToLinear(accent), SIMD3(1, 1, 1), 0.5))          // the accent's light tint (half way to white in linear light)
            return Colours(frame: frame, wood: hex(0xA67C5F), seat: accent, trim: cream, stone: hex(0x8C8780), asphalt: frame, bloom: [cream, light, cream], chalkNumber: light)
        }
    }()

    // MARK: call-site helpers (return LINEAR, ready for the builders; `old` is returned untouched in `today`)

    static func linear(_ role: KeyPath<Colours, SIMD3<Float>>, or old: SIMD3<Float>) -> SIMD3<Float> {
        guard let p = current else { return old }
        return OKLab.srgbToLinear(p[keyPath: role])
    }
    static func bloom(_ i: Int, or old: SIMD3<Float>) -> SIMD3<Float> {
        guard let p = current else { return old }
        return OKLab.srgbToLinear(p.bloom[i])
    }

    // MARK: the one-tint recipe (the living room's: one hue, five value steps)

    /// frame = swatch 1, wood = 2, seat = 3, trim = 4, stone = 2 darkened toward 1, asphalt = 1 toward 0, blooms = 4 / 3 / 2, numbers = 3. (`swatch(i)` is linear: stored here as sRGB.)
    private static func fromSwatches(_ theme: RoomTheme) -> Colours {
        let s = theme.swatches
        func c(_ l: SIMD3<Float>) -> SIMD3<Float> { toSrgb(l) }
        return Colours(frame: c(s[1]), wood: c(s[2]), seat: c(s[3]), trim: c(s[4]), stone: c(mixLinear(s[2], s[1], 0.4)), asphalt: c(mixLinear(s[1], s[0], 0.5)),
                       bloom: [c(s[4]), c(s[3]), c(s[2])], chalkNumber: c(s[3]))
    }

    /// The tint of `ui`: `-ParkPaletteTint r,g,b` when given, else the player's saved UI theme colour (UserDefaults "ThemeColor.v1" = a ThemePreset raw value, its `hex`; Sky Blue when unset).
    private static let uiTint: SIMD3<Float> = {
        if let t = UserDefaults.standard.string(forKey: "ParkPaletteTint") {
            let v = t.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            if v.count == 3 { return SIMD3(v[0], v[1], v[2]) }
        }
        // the presets' main colours (ThemePreset.hex, UI/ThemeColor.swift), copied so this stays nonisolated
        let table: [String: UInt32] = ["sky": 0x5A97D6, "pink": 0xEE8DB6, "mint": 0x5FC4A0, "lavender": 0x9D8CDF, "yellow": 0xF2C14E, "peach": 0xF4A27A, "navy": 0x26335F, "teal": 0x2FA3A6]
        let h = table[UserDefaults.standard.string(forKey: "ThemeColor.v1") ?? "sky"] ?? 0x5A97D6
        return SIMD3(Float(h >> 16 & 255) / 255, Float(h >> 8 & 255) / 255, Float(h & 255) / 255)
    }()

    // MARK: colour helpers

    /// 0xRRGGBB to sRGB 0...1 (the roles are sRGB).
    private static func hex(_ h: UInt32) -> SIMD3<Float> { SIMD3(Float(h >> 16 & 255) / 255, Float(h >> 8 & 255) / 255, Float(h & 255) / 255) }

    /// Plain lerp (callers pass LINEAR colours when they want a blend in linear light).
    private static func mixLinear(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    static func toSrgb(_ c: SIMD3<Float>) -> SIMD3<Float> {
        func f(_ v: Float) -> Float { let x = min(max(v, 0), 1); return x <= 0.0031308 ? x * 12.92 : 1.055 * powf(x, 1 / 2.4) - 0.055 }
        return SIMD3(f(c.x), f(c.y), f(c.z))
    }
}

/// The park seesaw in the palette's colours. nil in `today` (the seesaw is then not touched at all, the baked art draws as it always did). Like `ParkSlideSkin`: the loaded art is recoloured once by
/// colour class and positions, normals, AO, weights and pivots stay as they are. Each baked vertex colour (LINEAR, decor_seesaw.bin; tools/make_park_seesaw/build_seesaw.py:26-31) is assigned to
/// the nearest of the five baked colours (cushions, beam, fulcrum, handles / caps, bumpers; they are far apart in linear space) and takes that class's role colour times the vertex's own
/// brightness relative to the class colour (so the baked shading survives), clamped to 0.55...1.3 as the slide skin does.
nonisolated enum ParkSeesawSkin {
    static let art: DecorMeshes.Art? = {
        guard let p = ParkPalette.current, var a = DecorMeshes.loaded[.seesaw] else { return nil }
        func lin(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { OKLab.srgbToLinear(SIMD3(r, g, b)) }
        func lum(_ c: SIMD3<Float>) -> Float { simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722)) }
        // baked classes (sRGB literals of build_seesaw.py) and the role each takes; the fulcrum keeps its baked step below the beam (0.52 / 0.64 of it)
        let baked: [SIMD3<Float>] = [lin(0.72, 0.41, 0.28), lin(0.64, 0.46, 0.27), lin(0.52, 0.35, 0.20), lin(0.88, 0.84, 0.74), lin(0.125, 0.3375, 0.225)]
        let wood = OKLab.srgbToLinear(p.wood)
        let roles: [SIMD3<Float>] = [OKLab.srgbToLinear(p.seat), wood, wood * (lum(baked[2]) / lum(baked[1])), OKLab.srgbToLinear(p.trim), OKLab.srgbToLinear(p.frame)]
        for pi in a.parts.indices {
            for i in 0..<a.parts[pi].colors.count {
                let c = a.parts[pi].colors[i]
                var best = 0, bestD = Float.infinity
                for k in baked.indices { let d = simd_length_squared(c - baked[k]); if d < bestD { bestD = d; best = k } }
                let ratio = min(1.3, max(0.55, lum(c) / max(lum(baked[best]), 1e-4)))
                a.parts[pi].colors[i] = simd_min(roles[best] * ratio, SIMD3(repeating: 1))
            }
        }
        return a
    }()
}
