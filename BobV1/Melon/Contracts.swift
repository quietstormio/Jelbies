//
//  Contracts.swift
//  Shared types between geometry/physics, the Metal renderer and the SwiftUI layer.
//  All meshes are flat arrays (xyz triplets) so they can be handed to Metal without conversion.
//

import Foundation
import simd

/// Simulation (tetrahedral) mesh: rest positions, tets (4 indices each), per-particle region 0 flesh / 1 pale / 2 rind.
struct SimMesh {
    var rest: [Float]
    var tets: [UInt32]
    var region: [UInt8]
    var n2: Int
    var layers: Int
    /// Arm / foot particle chains (appendage particles are driven by the body but can be targeted independently by an
    /// animation: each one is tied to the body wall through its own tets). Empty for the legacy (Mint / Honey) mesh.
    var appendages: [SimAppendage] = []
}

/// One arm or foot: `particles` run from the root (nearest the body) to the tip (arms) or are the sole corners (feet).
struct SimAppendage {
    enum Kind { case arm, foot }
    var kind: Kind
    var side: Int              // -1 = -x, +1 = +x
    var particles: [Int]
}

/// Render surface (body incl. arm/foot nubs, then face decals). `mat` per vertex: 0 body, 1 eye, 3 eye glint, 4 brow
/// (1, 3, 4 live in the "seeds" range; the bubbles range is kept but empty).
/// Index ranges are expressed in *index counts* into `index`: body first, then seeds, then bubbles.
/// A curly antenna (Honey): render-only vertices skinned rigidly to a frame on the crown, with a spring-follow wobble
/// that grows toward the bobble at the tip.
struct AntennaInfo {
    var firstVertex: Int
    var vertexCount: Int
    var basePoints: [Float]     // rest-space frame: centre, centre + 0.1 up, centre + 0.1 side (9 floats)
    var tip: SIMD3<Float>       // rest-space bobble centre
    var weights: [Float]        // spring weight per antenna vertex (0 at the base, 1 at the bobble)
}

struct RenderMesh {
    var rest: [Float]          // xyz per vertex
    var restNormal: [Float]    // xyz per vertex
    var mat: [Float]           // one per vertex
    var index: [UInt32]
    var body: (first: Int, count: Int)
    var seeds: (first: Int, count: Int)
    var bubbles: (first: Int, count: Int)
    var seedCount: Int
    var antennae: [AntennaInfo] = []
    var vertexCount: Int { rest.count / 3 }
}

/// Linear-RGB colour variety (values match the web reference).
struct Palette {
    var name: String
    var flesh: SIMD3<Float>
    var fleshDeep: SIMD3<Float>
    var pale: SIMD3<Float>
    var skin: SIMD3<Float>
    var stripe: SIMD3<Float>
    var seed: SIMD3<Float>
    var shadowTint: SIMD3<Float>
    var uiFlesh: SIMD3<Float>   // linear RGB used for UI swatches / accent
    /// Lava-lamp tones: the shader drifts between deep (pale = flesh, skin = fleshDeep), mid (flesh / fleshDeep)
    /// and milky white (stripe = flesh, extra = fleshDeep). Filled in by PaletteKey.palette.
    var extra: SIMD3<Float> = [0, 0, 0]
    /// Marking id (see `BlobAppearance.Marking`) and the rest-pose body height the shader normalises marking coordinates by.
    var marking: Float = 0
    var bodyHeight: Float = 1.35
    /// Soft matte look (reference-matched colours held in `flesh` = lit tone, `fleshDeep` = shaded tone) instead of the glossy jelly.
    var matte = false
}

/// Bob's three colours, in the order they alternate. Soft pastel gummy/mochi jellies (linear RGB).
/// flesh = per-unit transmission tint (Beer-Lambert), fleshDeep = scattering albedo (milky body colour),
/// shadowTint = colour the floor shadow multiplies by, uiFlesh = UI swatch/accent, seed = eye colour #3A2620.
/// pale / skin / stripe are leftovers from the melon look: the Bob shader ignores them (kept so the struct is stable).
enum PaletteKey: String, CaseIterable, Identifiable {
    case blush, pink, yellow, blue
    var id: String { rawValue }
    /// #3A2620 in linear RGB.
    private static let eye = SIMD3<Float>(0.0423, 0.0194, 0.0144)
    /// The tuned base colour plus its two lava-lamp companions (a deeper shade and a milky white of the same hue).
    var palette: Palette {
        var p = base
        func clampT(_ c: SIMD3<Float>) -> SIMD3<Float> { simd_clamp(c, SIMD3(repeating: 0.01), SIMD3(repeating: 0.985)) }
        let f = p.flesh, d = p.fleshDeep
        p.pale = clampT(SIMD3(powf(f.x, 1.45), powf(f.y, 1.45), powf(f.z, 1.3)))      // deeper, more saturated
        p.skin = d * 0.82
        p.stripe = clampT(f + (SIMD3<Float>(repeating: 1) - f) * 0.62)                // milky: light absorption
        p.extra = d + (SIMD3<Float>(repeating: 1) - d) * 0.68
        if self == .blush {
            // Bob's reference colour: a soft pastel blush. The lava-lamp tones stay within a hair of each other so the
            // body reads as one gently shaded pink (no saturated core).
            p.pale = clampT(f * 0.985)
            p.skin = d * 0.985
            p.stripe = clampT(f + (SIMD3<Float>(repeating: 1) - f) * 0.35)
            p.extra = d + (SIMD3<Float>(repeating: 1) - d) * 0.30
            p.matte = true
        }
        return p
    }
    private var base: Palette {
        let unused = SIMD3<Float>(0.5, 0.5, 0.5)
        switch self {
        case .blush:
            return Palette(name: "Blush", flesh: [0.982, 0.725, 0.705], fleshDeep: [0.830, 0.479, 0.445],
                           pale: unused, skin: unused, stripe: unused, seed: Self.eye,
                           shadowTint: [0.80, 0.62, 0.60], uiFlesh: [0.95, 0.66, 0.63])
        case .pink:
            return Palette(name: "Pink", flesh: [0.97, 0.36, 0.56], fleshDeep: [0.80, 0.20, 0.36],
                           pale: unused, skin: unused, stripe: unused, seed: Self.eye,
                           shadowTint: [0.78, 0.50, 0.62], uiFlesh: [0.95, 0.42, 0.60])
        case .yellow:
            return Palette(name: "Yellow", flesh: [0.99, 0.78, 0.16], fleshDeep: [0.86, 0.58, 0.05],
                           pale: unused, skin: unused, stripe: unused, seed: Self.eye,
                           shadowTint: [0.80, 0.66, 0.36], uiFlesh: [0.98, 0.74, 0.16])
        case .blue:
            return Palette(name: "Light blue", flesh: [0.38, 0.70, 1.0], fleshDeep: [0.18, 0.46, 0.88],
                           pale: unused, skin: unused, stripe: unused, seed: Self.eye,
                           shadowTint: [0.46, 0.60, 0.80], uiFlesh: [0.30, 0.58, 0.95])
        }
    }
}

struct CameraState {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var pos = SIMD3<Float>(0, 0, 0)
    var fwd = SIMD3<Float>(0, 0, -1)
}

struct LightState {
    var dir = SIMD3<Float>(0, 1, 0)
    var intensity: Float = 2.3
    var lightVP = matrix_identity_float4x4   // key-light shadow map
    var topVP = matrix_identity_float4x4     // top-down height map (contact AO)
}

/// Per-frame values the renderer needs besides camera / light / palette.
struct FrameParams {
    var time: Float = 0
    var shape = SIMD4<Float>(0.58, 1.79, 0.075, 0.25)   // T, Ro, skin depth, pale depth
    var exposure: Float = 1
    var meshAlpha: Float = 0
    var bg = SIMD3<Float>(0.8, 0.8, 0.8)                // linear, already lifted for the tone-mapper toe
}

/// Studio sweep #E2DFDA in linear space, +0.04 to survive the tone-mapper toe (same as the web reference).
let melonBackgroundLinear: SIMD3<Float> = {
    func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
    return SIMD3<Float>(lin(0.886) + 0.04, lin(0.875) + 0.04, lin(0.855) + 0.04)
}()

/// Cream studio backdrop #FCF4E9 in linear space (Bob's reference photos). The matte look skips the film curve, so no toe lift.
let melonCreamLinear: SIMD3<Float> = {
    func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
    return SIMD3<Float>(lin(0.988), lin(0.957), lin(0.914))
}()

/// Tunable proportions of a Blob (a species; breeds tweak these). Lengths are world units (rest space, y up, face toward +z).
/// The body is a surface of revolution: a flat base disc, a superellipse bottom (boxy = flat-ish bottom) up to the widest
/// radius, then a rounder upper dome that is narrower than it is tall (egg).
struct BlobProportions: Equatable {
    var height: Float = 1.35
    var radius: Float = 0.70            // widest radius
    var widestT: Float = 0.38           // widest at this fraction of the height
    var baseRatio: Float = 0.60         // radius of the flat base disc / widest radius
    var bottomExp: Float = 2.8          // superellipse exponent below the widest point (2 round, higher = flatter bottom)
    var topExp: Float = 2.0             // exponent above (2 = ellipse dome)

    // eyes: vertical ovals on the +z side
    var eyeT: Float = 0.58              // centre height / H
    var eyeSpacingFrac: Float = 0.26    // ±x of each eye centre, as a fraction of the body width (2 * radius)
    var eyeRX: Float = 0.056            // half width of the oval
    var eyeRY: Float = 0.088            // half height of the oval (taller than wide)
    var eyeBump: Float = 0.013          // how far the eye bead rises above the surface

    // brows: short flat dark lines with rounded ends above each eye
    var browT: Float = 0.70             // height of the lower line / H
    var browHalfLen: Float = 0.072
    var browHalfThick: Float = 0.015
    var browLines: Int = 1              // stacked lines per eye
    var browGap: Float = 0.036          // vertical distance between stacked lines

    // arms: small rounded nubs low on each side, slightly forward
    var armT: Float = 0.40              // height / H
    var armAzimuth: Float = 1.15        // radians from +z (toward ±x)
    var armOut: Float = 0.035           // ellipsoid centre distance beyond the surface
    var armLength: Float = 0.105        // ellipsoid semi-axis along the arm
    var armWidth: Float = 0.085         // semi-axis across (horizontal)
    var armThick: Float = 0.08          // semi-axis vertical

    // feet: short stubby rounded nubs at the bottom front
    var footAzimuth: Float = 0.42       // radians from +z
    var footOut: Float = 0.06
    var footLength: Float = 0.13
    var footWidth: Float = 0.105
    var footHeight: Float = 0.07        // semi-axis vertical (centre sits at this height: sole on the floor)

    static let standard = BlobProportions()
}

extension BlobProportions {
    /// Every length scaled by `k` (per-individual size variation).
    func scaled(_ k: Float) -> BlobProportions {
        var q = self
        q.height *= k; q.radius *= k
        q.eyeRX *= k; q.eyeRY *= k; q.eyeBump *= k
        q.browHalfLen *= k; q.browHalfThick *= k; q.browGap *= k
        q.armOut *= k; q.armLength *= k; q.armWidth *= k; q.armThick *= k
        q.footOut *= k; q.footLength *= k; q.footWidth *= k; q.footHeight *= k
        return q
    }
}

/// Everything that makes one Blob individual look the way it does: breed (colours + extra feature), markings, size.
/// Pass it to `buildSimMesh` / `buildRenderMesh` / `buildEyeRig` (the same value to all three) and to the controller
/// through `MelonModel.appearance`. Colours are linear RGB.
struct BlobAppearance: Equatable {
    enum Breed: String, CaseIterable { case berry, mint, honey }
    enum Marking: Int, CaseIterable {
        case none = 0, starOnHead, spotOnHead, heartOnCheek, freckles, spotOnBack, whiteBelly
    }

    var breed: Breed = .berry
    var core: SIMD3<Float> = BlobAppearance.srgb(0xD3, 0x15, 0x5A)     // main colour
    var light: SIMD3<Float> = BlobAppearance.srgb(0xF0, 0x47, 0x7F)    // lighter areas / thin edges
    var deep: SIMD3<Float> = BlobAppearance.srgb(0x8E, 0x0B, 0x3A)     // thick / shadowed regions
    /// Per-individual brightness shift, about -0.15 ... 0.15.
    var shade: Float = 0
    var marking: Marking = .none
    /// Whole-body size multiplier, 0.95 ... 1.05.
    var sizeScale: Float = 1
    /// Spike height (Mint) / antenna length + bobble size (Honey), 0.8 ... 1.25.
    var featureScale: Float = 1
    /// Mint spikes 5...7, Honey antennae 1...2 (nil = breed default).
    var featureCount: Int? = nil
    /// Jitters spike spacing / antenna curl direction and tightness.
    var featureSeed: UInt32 = 1
    var proportions: BlobProportions = .standard

    /// Proportions with `sizeScale` applied: this is what geometry is built from.
    var effective: BlobProportions { proportions.scaled(sizeScale) }

    static func srgb(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> {
        func lin(_ c: Int) -> Float { let v = Float(c) / 255; return v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
        return SIMD3(lin(r), lin(g), lin(b))
    }

    static let berry = BlobAppearance()
    static let mint = BlobAppearance(breed: .mint, core: srgb(0x2F, 0xB8, 0xA0), light: srgb(0x6F, 0xDB, 0xC4), deep: srgb(0x14, 0x6E, 0x5E))
    static let honey = BlobAppearance(breed: .honey, core: srgb(0xF2, 0xA3, 0x25), light: srgb(0xF8, 0xC8, 0x6A), deep: srgb(0xB0, 0x68, 0x0A))

    /// Spike count (Mint) or antenna count (Honey); 0 for Berry.
    var resolvedFeatureCount: Int {
        switch breed {
        case .berry: return 0
        case .mint: return min(7, max(5, featureCount ?? 6))
        case .honey: return min(2, max(1, featureCount ?? 1))
        }
    }

    /// Shader palette: core drives the mid tone, light the milky tone, deep the thick/shadow tone.
    var palette: Palette {
        func clamp01(_ c: SIMD3<Float>) -> SIMD3<Float> { simd_clamp(c, SIMD3(repeating: 0.01), SIMD3(repeating: 0.985)) }
        func shifted(_ c: SIMD3<Float>) -> SIMD3<Float> { clamp01(c * (1 + shade)) }
        func rt(_ c: SIMD3<Float>, _ e: Float) -> SIMD3<Float> { SIMD3(powf(c.x, e), powf(c.y, e), powf(c.z, e)) }
        let c = shifted(core), l = shifted(light), d = shifted(deep)
        var p = Palette(name: breed.rawValue.capitalized, flesh: clamp01(rt(c, 0.55)), fleshDeep: c,
                        pale: clamp01(rt(d, 0.7)), skin: d, stripe: clamp01(rt(l, 0.6)),
                        seed: PaletteKey.pink.palette.seed, shadowTint: clamp01(rt(c, 0.35) * 0.9 + 0.12),
                        uiFlesh: l)
        p.extra = l
        p.marking = Float(marking.rawValue)
        p.bodyHeight = effective.height
        return p
    }
}

/// The solved body profile for one set of proportions (Double precision so sim hull and render surface agree).
struct BlobProfile {
    let p: BlobProportions
    let H: Double, R: Double, yw: Double, A: Double, B: Double, pb: Double, pt: Double, baseR: Double

    init(_ p: BlobProportions) {
        self.p = p
        H = Double(p.height); R = Double(p.radius); yw = Double(p.widestT) * H
        pb = Double(p.bottomExp); pt = Double(p.topExp)
        baseR = R * Double(p.baseRatio)
        let u0 = pow(1 - pow(Double(p.baseRatio), pb), 1 / pb)
        A = yw / u0
        B = H - yw
    }

    /// Radius and outward 2D normal (nr, ny) at height y.
    func sample(atHeight yIn: Double) -> (r: Double, nr: Double, ny: Double) {
        let y = min(max(yIn, 0), H)
        if y <= yw {
            let u = (yw - y) / A
            let r = R * pow(max(0, 1 - pow(u, pb)), 1 / pb)
            let nr = pow(r, pb - 1) / pow(R, pb), ny = -pow(u, pb - 1) / A
            let l = max(hypot(nr, ny), 1e-12)
            return (r, nr / l, ny / l)
        } else {
            let s = (y - yw) / B
            let r = R * pow(max(0, 1 - pow(s, pt)), 1 / pt)
            let nr = pow(r, pt - 1) / pow(R, pt), ny = pow(s, pt - 1) / B
            let l = max(hypot(nr, ny), 1e-12)
            return (r, nr / l, ny / l)
        }
    }
    func radius(atHeight y: Double) -> Double { sample(atHeight: y).r }

    /// The closed profile from the bottom centre, out along the base disc, up the body to the top centre, sampled about
    /// every `spacing` of arc length. Each sample: radius, height and outward normal (nr, ny); r = 0 at both ends.
    func profile(spacing: Float) -> [(r: Float, y: Float, nr: Float, ny: Float)] {
        var out: [(r: Float, y: Float, nr: Float, ny: Float)] = []
        let sp = Double(spacing)
        let nb = max(1, Int(ceil(baseR / sp)))
        for i in 0..<nb { out.append((Float(baseR * Double(i) / Double(nb)), 0, 0, -1)) }
        // dense polyline of the curve, then resample by arc length
        var dense: [(r: Double, y: Double)] = []
        let u0 = yw / A, phi0 = asin(pow(u0, pb / 2))
        let N = 1500
        for i in 0...N {
            let phi = phi0 * (1 - Double(i) / Double(N))
            dense.append((R * pow(cos(phi), 2 / pb), yw - A * pow(sin(phi), 2 / pb)))
        }
        for i in 1...N {
            let th = Double.pi / 2 * Double(i) / Double(N)
            dense.append((R * pow(cos(th), 2 / pt), yw + B * pow(sin(th), 2 / pt)))
        }
        var cum: [Double] = [0]
        for i in 1..<dense.count { cum.append(cum[i - 1] + hypot(dense[i].r - dense[i - 1].r, dense[i].y - dense[i - 1].y)) }
        let total = cum[cum.count - 1]
        let ns = max(8, Int(ceil(total / sp)))
        var j = 0
        for k in 0..<ns {
            let target = total * Double(k) / Double(ns)
            while j < cum.count - 2 && cum[j + 1] < target { j += 1 }
            let f = (target - cum[j]) / max(cum[j + 1] - cum[j], 1e-12)
            let r = dense[j].r + (dense[j + 1].r - dense[j].r) * f
            let y = dense[j].y + (dense[j + 1].y - dense[j].y) * f
            let s = sample(atHeight: y)
            out.append((Float(r), Float(y), Float(s.nr), Float(s.ny)))
        }
        out.append((0, Float(H), 0, 1))
        return out
    }

    /// Body surface point and outward normal at height y, azimuth th (measured from +z toward +x).
    func surface(y: Double, th: Double) -> (p: SIMD3<Double>, n: SIMD3<Double>) {
        let s = sample(atHeight: y)
        return (SIMD3(s.r * sin(th), y, s.r * cos(th)), simd_normalize(SIMD3(s.nr * sin(th), s.ny, s.nr * cos(th))))
    }

    /// Ellipsoidal appendage (arm or foot). Local frame: d outward axis, w across (horizontal), up vertical.
    struct Nub {
        var surfaceAnchor: SIMD3<Double>   // point on the body wall it grows from
        var center: SIMD3<Double>
        var d: SIMD3<Double>, w: SIMD3<Double>, up: SIMD3<Double>
        var semi: SIMD3<Double>            // along d, w, up
        var patchRadius: Double            // radius of the sim wall patch it is tied to
        var apexDist: Double               // sim apex distance from the anchor along d
        var isFoot: Bool
        var side: Double                   // -1 (-x) or +1 (+x)
    }

    /// Arms, feet and (Mint) the row of spikes down the centre line, from the crown down the back.
    func nubs(_ a: BlobAppearance) -> [Nub] {
        var res = nubs
        guard a.breed == .mint else { return res }
        let n = a.resolvedFeatureCount
        var rng = Mulberry(seed: a.featureSeed &* 2654435761 &+ 7)
        let yUp = SIMD3<Double>(0, 1, 0)
        let fs = Double(a.featureScale)
        for k in 0..<n {
            let f = Double(k) / Double(max(n - 1, 1))
            let size = fs * (1 - 0.58 * f) * (0.94 + 0.12 * rng.next())
            let len = 0.17 * H / 1.35 * size, wid = 0.078 * H / 1.35 * size
            var anchor: SIMD3<Double>, d: SIMD3<Double>
            if k == 0 {
                anchor = SIMD3(0, H, 0); d = simd_normalize(SIMD3(0, 1, -0.3))
            } else {
                let y = H * (0.88 - 0.50 * (Double(k - 1) / Double(max(n - 2, 1))) + (rng.next() - 0.5) * 0.02)
                let s = surface(y: y, th: Double.pi)
                anchor = s.p; d = simd_normalize(s.n + SIMD3(0, 0.45, 0))
            }
            let w = simd_normalize(simd_cross(yUp, d + SIMD3(1e-4, 0, 0)))
            let up = simd_cross(d, w)
            res.append(Nub(surfaceAnchor: anchor, center: anchor + d * (0.3 * len), d: d, w: w, up: up,
                           semi: SIMD3(len, wid, wid), patchRadius: 0.12 + 0.9 * wid, apexDist: 1.3 * len + 0.05,
                           isFoot: false, side: 0))
        }
        return res
    }

    var nubs: [Nub] {
        var res: [Nub] = []
        let yUp = SIMD3<Double>(0, 1, 0)
        for side in [-1.0, 1.0] {
            // arm
            do {
                let y = Double(p.armT) * H, th = side * Double(p.armAzimuth)
                let s = surface(y: y, th: th)
                var d = simd_normalize(SIMD3(s.n.x, s.n.y - 0.2, s.n.z))
                d = simd_normalize(d)
                let w = simd_normalize(simd_cross(yUp, d))
                let up = simd_cross(d, w)
                let c = s.p + d * Double(p.armOut)
                res.append(Nub(surfaceAnchor: s.p, center: c, d: d, w: w, up: up,
                               semi: SIMD3(Double(p.armLength), Double(p.armWidth), Double(p.armThick)),
                               patchRadius: 0.17, apexDist: Double(p.armOut + p.armLength) + 0.09, isFoot: false, side: side))
            }
            // foot
            do {
                let fy = Double(p.footHeight), th = side * Double(p.footAzimuth)
                let rr = radius(atHeight: fy)
                let d = SIMD3(sin(th), 0, cos(th))
                let anchor = SIMD3(rr * d.x, fy, rr * d.z)
                let w = simd_normalize(simd_cross(yUp, d))
                let c = anchor + d * Double(p.footOut)
                res.append(Nub(surfaceAnchor: anchor, center: c, d: d, w: w, up: yUp,
                               semi: SIMD3(Double(p.footLength), Double(p.footWidth), Double(p.footHeight)),
                               patchRadius: 0.15, apexDist: Double(p.footOut + p.footLength) + 0.07, isFoot: true, side: side))
            }
        }
        return res
    }
}

/// The standard Blob, with the shape constants the camera, locomotion and tests key off.
enum BlobShape {
    static let proportions = BlobProportions.standard
    static let profile = BlobProfile(proportions)
    static let H: Float = proportions.height
    static let R: Float = proportions.radius
    static var baseR: Float { Float(profile.baseR) }
    static func radius(atHeight y: Float) -> Float { Float(profile.radius(atHeight: Double(y))) }
    static func sample(atHeight y: Double) -> (r: Double, nr: Double, ny: Double) { profile.sample(atHeight: y) }

    /// Eye colour #3A2620 in linear RGB (brows share it).
    static let eyeColorSRGB = SIMD3<Float>(0x3A, 0x26, 0x20) / 255
}

typealias BobShape = BlobShape

// MARK: - Bob's body form (matches the reference model)

/// Bob's rest form: a soft egg whose front profile (half-width) and side profile (half-depth) differ, two teardrop
/// arms hanging down the sides, two small feet that lift the body off the floor. Defined as a signed distance field
/// (rest space: y up, floor at y = 0, face toward +z, symmetric in x). All lengths are world units.
/// Measured from the reference renders; H = `bodyH` (crown to underside, feet excluded).
enum BobForm {
    static let lift = 0.1039                       // underside height above the floor (the feet)
    static let bodyH = 1.2419
    static let top = lift + bodyH                // crown height = BlobShape.H
    static let halfW = 0.5836                     // widest half width (front), fitted to the reference silhouette
    static let halfD = 0.5200                     // widest half depth (side), fitted to the reference silhouettes

    struct Profile { var tw: Double, ratio: Double, pb: Double, pt: Double }
    static let front = Profile(tw: 0.4828, ratio: 0.4089, pb: 2.8358, pt: 2.1049)
    static let side = Profile(tw: 0.4167, ratio: 0.3954, pb: 2.1793, pt: 2.1664)

    /// Normalised profile (0...1 of the widest value) at height fraction t (0 underside, 1 crown).
    static func unit(_ t: Double, _ p: Profile) -> Double {
        if t <= p.tw {
            let u0 = pow(1 - pow(p.ratio, p.pb), 1 / p.pb)
            let A = p.tw / u0, u = (p.tw - t) / A
            return pow(max(0, 1 - pow(u, p.pb)), 1 / p.pb)
        }
        let s = (t - p.tw) / (1 - p.tw)
        return pow(max(0, 1 - pow(s, p.pt)), 1 / p.pt)
    }
    private static let lutN = 4096
    private static let lutA: [Double] = (0...lutN).map { halfW * unit(Double($0) / Double(lutN), front) }
    private static let lutC: [Double] = (0...lutN).map { halfD * unit(Double($0) / Double(lutN), side) }
    @inline(__always) private static func look(_ lut: [Double], _ t: Double) -> Double {
        let f = min(max(t, 0), 1) * Double(lutN)
        let i = min(Int(f), lutN - 1)
        return lut[i] + (lut[i + 1] - lut[i]) * (f - Double(i))
    }
    /// Half width (x) and half depth (z) of the body cross-section at height fraction t.
    static func halfWidth(t: Double) -> Double { look(lutA, t) }
    static func halfDepth(t: Double) -> Double { look(lutC, t) }

    // arms: an elongated ellipsoid hanging down the side (+x; mirrored), tilted a little outward toward the tip. It is smooth-unioned
    // with the body with a wide fillet at its root (top) and almost none at the tip, so the top flows into the body while the
    // free tip keeps an undercut against the wall.
    static let armC = SIMD3<Double>(0.545, 0.4516, 0.07)
    static let armTilt = 0.3818
    static let armUp = SIMD3<Double>(-sin(armTilt), cos(armTilt), 0)
    static let armPerp = SIMD3<Double>(cos(armTilt), sin(armTilt), 0)
    static let armSemi = SIMD3<Double>(0.1496, 0.1676, 0.13)          // across (x-y plane), along the axis, depth (z)
    // sim stations along the arm axis (top, tip) and their tube radius
    static let armTop = SIMD3<Double>(0.517, 0.605, 0.06), armTip = SIMD3<Double>(0.55, 0.46, 0.06)
    static let armTopR = 0.058, armTipR = 0.15
    static let armFlatten = 1.15
    static let footX = 0.2154, footZ = 0.075
    static let footRadii = SIMD3<Double>(0.155, 0.18, 0.135)
    static let footCY = 0.16                                 // centre below the sole line: the floor clamp in footSDF cuts a flat sole
    static let footExp = 2.6                      // 2 = ellipsoid; higher = boxier (flat sole, straight sides)

    static let bellyRise = 0.0306
    static let armBlend = 0.04, armTipBlend = 0.02, footBlend = 0.02

    @inline(__always) static func smin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    /// Egg only (pseudo distance, exact sign).
    static func bodySDF(_ p: SIMD3<Double>) -> Double {
        let t = (p.y - lift) / bodyH
        let a = max(halfWidth(t: t), 1e-3), c = max(halfDepth(t: t), 1e-3)
        let rho = ((p.x / a) * (p.x / a) + (p.z / c) * (p.z / c)).squareRoot()
        let f = (rho - 1) * min(a, c)
        // the underside is a shallow dome (lowest at the centre, rising toward the rim) so the feet tuck under a rounded belly
        let q = min((p.x / 0.389) * (p.x / 0.389) + (p.z / 0.341) * (p.z / 0.341), 2.5)
        let bottom = lift + bellyRise * q
        return max(f, max(bottom - p.y, p.y - top))
    }

    static func roundCone(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ r1: Double, _ r2: Double) -> Double {
        let ba = b - a, l2 = simd_dot(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1 / l2
        let pa = p - a, y = simd_dot(pa, ba), z = y - l2
        let w = pa * l2 - ba * y
        let x2 = simd_dot(w, w), y2 = y * y * l2, z2 = z * z * l2
        let k = (rr < 0 ? -1.0 : 1.0) * rr * rr * x2
        if (z < 0 ? -1.0 : 1.0) * a2 * z2 > k { return (x2 + z2).squareRoot() * il2 - r2 }
        if (y < 0 ? -1.0 : 1.0) * a2 * y2 < k { return (x2 + y2).squareRoot() * il2 - r1 }
        return ((x2 * a2 * il2).squareRoot() + y * rr) * il2 - r1
    }
    /// Arm: a teardrop (round cone) hanging from the body wall: a narrow top that emerges smoothly from the surface and a fat round
    /// bulb at the bottom (armTop/armTopR -> armTip/armTipR, the same stations the sim uses). Returns the distance (pseudo) and
    /// h = 0 at the top ... 1 at the bulb.
    static func armSDF(_ q: SIMD3<Double>) -> (d: Double, t: Double) {
        // the drop is squeezed in z (armFlatten > 1): round ball seen from the front, slim thumb seen from the side
        let a = SIMD3(armTop.x, armTop.y, armTop.z * armFlatten), b = SIMD3(armTip.x, armTip.y, armTip.z * armFlatten)
        let qq = SIMD3(q.x, q.y, q.z * armFlatten)
        let ba = b - a
        let h = min(max(simd_dot(qq - a, ba) / simd_dot(ba, ba), 0), 1)
        return (roundCone(qq, a, b, armTopR, armTipR) / armFlatten.squareRoot(), h)
    }
    static func footSDF(_ q: SIMD3<Double>) -> Double {
        let p = q - SIMD3(footX, footCY, footZ)
        if footExp != 2 {
            // superellipsoid (flatter sole, straighter sides): scaled-norm distance estimate, exact sign
            let e = simd_abs(p / footRadii)
            let kn = pow(pow(e.x, footExp) + pow(e.y, footExp) + pow(e.z, footExp), 1 / footExp)
            return max((kn - 1) * footRadii.min(), -q.y)      // flat sole on the floor plane
        }
        let k0 = simd_length(p / footRadii), k1 = simd_length(p / (footRadii * footRadii))
        return k1 > 1e-12 ? k0 * (k0 - 1) / k1 : -footRadii.min()
    }

    /// Whole body: egg smooth-unioned with both arms and both feet.
    static func sdf(_ p: SIMD3<Double>) -> Double {
        let q = SIMD3(abs(p.x), p.y, p.z)
        let arm = armSDF(q)
        let u = 1 - min(max(arm.t / 0.55, 0), 1)          // 1 at the narrow top (wide fillet), 0 at the bulb (tight crease)
        let k = armTipBlend + (armBlend - armTipBlend) * (u * u * (3 - 2 * u))
        var d = smin(bodySDF(p), arm.d, k)
        d = smin(d, footSDF(q), footBlend)
        return d
    }

    static func gradient(_ p: SIMD3<Double>, e: Double = 0.0015) -> SIMD3<Double> {
        SIMD3(sdf(p + SIMD3(e, 0, 0)) - sdf(p - SIMD3(e, 0, 0)),
              sdf(p + SIMD3(0, e, 0)) - sdf(p - SIMD3(0, e, 0)),
              sdf(p + SIMD3(0, 0, e)) - sdf(p - SIMD3(0, 0, e))) / (2 * e)
    }
    static func normal(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let g = gradient(p)
        return simd_length(g) > 1e-12 ? simd_normalize(g) : SIMD3(0, 0, 1)
    }
    /// Crease occlusion 0 (open) ... 1 (deep crease) from marching a few steps out along the normal.
    static func occlusion(_ p: SIMD3<Double>, _ n: SIMD3<Double>) -> Double {
        var occ = 0.0, w = 1.0
        for k in 1...5 {
            let h = 0.05 * Double(k)
            occ += max(h - sdf(p + n * h), 0) / h * w
            w *= 0.7
        }
        return min(max(occ * 1.1, 0), 1)
    }
    /// Move p onto the surface (Newton steps along the gradient).
    static func project(_ p0: SIMD3<Double>, steps: Int = 4) -> SIMD3<Double> {
        var p = p0
        for _ in 0..<steps {
            let f = sdf(p), g = gradient(p), l2 = simd_dot(g, g)
            if l2 < 1e-12 { break }
            p -= g * (f / l2)
        }
        return p
    }
    /// Front surface (z > 0) at (x, y): bisection along z.
    static func frontSurface(x: Double, y: Double) -> SIMD3<Double> {
        var lo = 0.0, hi = 1.0
        for _ in 0..<44 {
            let m = 0.5 * (lo + hi)
            if sdf(SIMD3(x, y, m)) < 0 { lo = m } else { hi = m }
        }
        return SIMD3(x, y, 0.5 * (lo + hi))
    }

    // face: measured against the reference silhouette (positions relative to the body, camera-independent where possible)
    static let eyeX = 0.215
    static let eyeY = 0.82
    static let eyeHalfW = 0.0488
    static let eyeHalfH = 0.0605
    static let browY = 0.945
    static let browHalfLen = 0.069
    static let browHalfThick = 0.0115
}
