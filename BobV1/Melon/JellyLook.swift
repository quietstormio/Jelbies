//
//  JellyLook.swift
//  Lab: a "made of jelly" look for the blue body (glossy, soft light through the body, optionally see-through). Developer switch, OFF by default.
//  Only the colour of a body changes: shape, motion, physics, face, feet and wear are not touched. The shader side is fsSoftMatteFast in GfxBodyFast.metal
//  (function constant 5 compiles the jelly maths in; the stock pipelines never set it, so they stay as they were).
//
//  Launch arguments (read once, only where DevArgs.enabled): -JellyLook 0...3, -JellyAll 1 (every species, not only blue),
//  tuning overrides -JellySee -JellyCore -JellyGloss -JellyGlow -JellyRim -JellySat -JellySmooth -JellyBend (floats; absent = the preset's value).
//

import Foundation
import Metal
import simd

nonisolated enum JellyLook {
    /// The level a build ships with. Stays 0.
    static let launchLevel = 0
    /// The ONE build switch: set to (level: 1, all: true) to make the jelly look the default for all species (per-species style / level / neon: `profile(forFlesh:)`),
    /// or (1, false) for the blue body only, without launch arguments. Stays nil in a commit; launch arguments still win where DevArgs.enabled.
    static let phoneTest: (level: Int, all: Bool)? = (1, true)

    /// Look style of a body: A = round 4 (the owner's locked Blue look: its colour maths, highlight shapes), B = round 5 (the species' own colour, softer highlight).
    /// Rides in the jelly parameter buffer ([0].x: 1 = B, 2 = A), so all three body shaders (plain, bath, jersey) pick it per draw without another pipeline.
    enum Style: Int { case b = 1, a = 2 }
    /// Neon cap (species-generic rule in the shader: bright AND saturated colours are softened and deepened). Presets: a = softer, b = softer + a bit deeper, c = clearly deeper.
    struct Neon { var soft: Float, deepen: Float, y0: Float, y1: Float
        static let off = Neon(soft: 0, deepen: 0, y0: 0.50, y1: 0.68)
        static let c = Neon(soft: 0.15, deepen: 0.22, y0: 0.50, y1: 0.68)
        static func preset(_ k: String) -> Neon? {
            switch k.lowercased() {
            case "a": return Neon(soft: 0.30, deepen: 0.00, y0: 0.50, y1: 0.68)
            case "b": return Neon(soft: 0.18, deepen: 0.10, y0: 0.50, y1: 0.68)
            case "c": return .c
            case "off": return .off
            default: return nil
            }
        }
    }
    /// Dev override (capture aid): `-JellyNeon a|b|c|off` replaces the per-species neon of every body. nil = the species table.
    static let neonOverride: Neon? = {
        guard DevArgs.enabled, let k = UserDefaults.standard.string(forKey: "JellyNeon") else { return nil }
        return Neon.preset(k)
    }()

    /// The species groups the look treats differently (a body is matched by its palette colour, nearest reference within a tolerance: an adopted Jelbie's shade and the rare jewel tones vary a little).
    enum Species { case blue, yellow, green, other }
    /// Species -> (style, level, neon): Blue = (A, 1, off), Green = (B, 1, C), Yellow = (B, 2, off), Lavender / Teddy / Pearl / Panda / visitors = (B, 1, off).
    struct Profile { var species: Species; var style: Style; var level: Int; var neon: Neon }
    static func profile(species: Species) -> Profile {
        switch species {
        case .blue: return Profile(species: .blue, style: .a, level: 1, neon: .off)
        case .green: return Profile(species: .green, style: .b, level: 1, neon: .c)
        case .yellow: return Profile(species: .yellow, style: .b, level: 2, neon: .off)
        case .other: return Profile(species: .other, style: .b, level: 1, neon: .off)
        }
    }
    /// The references (flesh colours) and how far a body may be from one and still be that species (RGB distance).
    nonisolated(unsafe) static var speciesTolerance: Float = 0.12
    static func classify(flesh f: SIMD4<Float>) -> Species {
        let v = SIMD3<Float>(f.x, f.y, f.z)
        let refs: [(SIMD3<Float>, Species)] = [
            (PaletteKey.blue.palette.flesh, .blue), (JellyVariantBook.exclusives[0].fleshV, .blue),
            (PaletteKey.yellow.palette.flesh, .yellow), (JellyVariantBook.exclusives[1].fleshV, .yellow),
            (JellyPalettes.green.flesh, .green), (JellyVariantBook.exclusives[2].fleshV, .green),
            (JellyPalettes.lavender.flesh, .other), (JellyVariantBook.exclusives[3].fleshV, .other),
            (WhiteWing.palette.flesh, .other), (PandaLook.flesh, .other)] + TeddyLook.tones.map { ($0.flesh, Species.other) }
        var best = Species.other, bd = speciesTolerance
        for (c, sp) in refs { let d = simd_length(v - c); if d < bd { bd = d; best = sp } }
        return best
    }
    /// What a body with this flesh colour is drawn with. A master level of 2 or 3 (dev argument / test) forces that level in style B for every body.
    /// `speciesID` (JellyRoster species id, from the body's palette) wins when known; otherwise the colour decides.
    static func species(id: Int) -> Species { id == 0 ? .blue : id == 1 ? .yellow : id == 2 ? .green : .other }
    static func profile(forFlesh f: SIMD4<Float>, speciesID: Int = -1) -> Profile {
        var p = profile(species: speciesID >= 0 ? species(id: speciesID) : classify(flesh: f))
        if level >= 2 { p.style = .b; p.level = level }
        if let n = neonOverride { p.neon = n }
        return p
    }
    /// The level a body with this flesh colour is drawn at.
    static func level(forFlesh f: SIMD4<Float>, speciesID: Int = -1) -> Int { level > 0 ? profile(forFlesh: f, speciesID: speciesID).level : 0 }

    private static func argFloat(_ key: String) -> Float? {
        guard DevArgs.enabled, UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return Float(UserDefaults.standard.double(forKey: key))
    }

    /// The level actually used (settable so tests can switch it; read once from -JellyLook otherwise).
    nonisolated(unsafe) static var level: Int = {
        guard DevArgs.enabled, UserDefaults.standard.object(forKey: "JellyLook") != nil else { return phoneTest.map { max(0, min(3, $0.level)) } ?? launchLevel }
        return max(0, min(3, UserDefaults.standard.integer(forKey: "JellyLook")))
    }()
    /// -JellyAll 1: every species gets the look (default: the blue body only).
    nonisolated(unsafe) static var all: Bool = (DevArgs.enabled && UserDefaults.standard.object(forKey: "JellyAll") != nil) ? UserDefaults.standard.integer(forKey: "JellyAll") != 0 : (phoneTest?.all ?? false)

    /// Optional tuning overrides: see, core, gloss, glow, rim, sat, smooth, bend.
    nonisolated(unsafe) static var overrides: [String: Float] = {
        var o: [String: Float] = [:]
        for k in ["See", "Core", "Gloss", "Glow", "Rim", "Sat", "Smooth", "Bend", "Edge", "Tint", "Warm", "Bubbles", "Deep", "Dk", "Ck", "HiX", "HiY", "Flat", "Belly", "BandLo", "BandHi", "Lift", "Soft", "Deepen", "NeonY0", "NeonY1"] { if let v = argFloat("Jelly" + k) { o[k] = v } }
        return o
    }()

    /// 7 x float4 for the fragment shader (buffer 7): [0] = (style: 1 = B / round 5, 2 = A / round 4; 0 = off, see, core, gloss), [1] = (glow, rim, sat, smooth), [2] = (bend, edge, tint, warm), [3] = (bubbles, deep, dk, ck), [4] = (highlight shift x, y, flat, belly paint scale), [5] = (band low, band high, band lift), [6] = (neon soften, neon deepen, neon luminance start, end).
    /// nil = not a jelly body (all zeros = off).
    static func params(forFlesh f: SIMD4<Float>?, speciesID: Int = -1) -> [SIMD4<Float>] { f.map { params(profile: profile(forFlesh: $0, speciesID: speciesID)) } ?? [SIMD4<Float>](repeating: .zero, count: 7) }
    static func params(profile pr: Profile) -> [SIMD4<Float>] {
        guard pr.level > 0 else { return [SIMD4<Float>](repeating: .zero, count: 7) }
        let styleA = pr.style == .a
        // `core` ([0].z) and `edge` ([2].y) are unused at level 1; `sat` is 0 (`deep` darkens and saturates instead); `rim` = the light band's strength.
        //                         see   core  gloss glow  rim   sat   smooth edge  tint warm  bub  deep  dk    ck
        // Style A = round 4 as the owner locked it (07a2982d: level 1, opaque, gloss 0.35, deeper flatter more saturated colour, highlight shift 0,0).
        // Style B = round 5: L1 opaque; L2 = see-through at the rim only; L3 adds the core.
        let pA: [Float] = [0.00, 0.35, 0.35, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.50, 1.7]
        let pB: [[Float]] = [[0.00, 0.00, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0],
                             [0.60, 0.00, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0],
                             [0.70, 0.85, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0]]
        var v = styleA ? pA : pB[min(pr.level, 3) - 1]
        for (i, k) in ["See", "Core", "Gloss", "Glow", "Rim", "Sat", "Smooth", "Edge", "Tint", "Warm", "Bubbles", "Deep", "Dk", "Ck"].enumerated() { if let o = overrides[k] { v[i] = o } }
        let hi: SIMD2<Float> = styleA ? SIMD2(0, 0) : SIMD2(-0.03, 0.06)          // round 4 has no highlight shift (its highlight shapes sit at the numbers in the shader)
        let nn = styleA ? Neon.off : pr.neon
        return [SIMD4(Float(pr.style.rawValue), v[0], v[1], v[2]), SIMD4(v[3], v[4], v[5], v[6]), SIMD4(overrides["Bend"] ?? 0, v[7], v[8], v[9]), SIMD4(v[10], v[11], v[12], v[13]),
                SIMD4(overrides["HiX"] ?? hi.x, overrides["HiY"] ?? hi.y, overrides["Flat"] ?? 0.7, overrides["Belly"] ?? 0.2),
                SIMD4(overrides["BandLo"] ?? 0.12, overrides["BandHi"] ?? 0.70, overrides["Lift"] ?? 2.1, 0),
                SIMD4(overrides["Soft"] ?? nn.soft, overrides["Deepen"] ?? nn.deepen, overrides["NeonY0"] ?? nn.y0, overrides["NeonY1"] ?? nn.y1)]
    }

    /// 0 = not a jelly body (matte as before), 1 = jelly shading on the opaque pipeline, 2 = see-through (own pass, blended).
    /// Bath and jersey bodies are decided by the caller (they draw the opaque finish inside their own shaders).
    static func kind(flesh: SIMD4<Float>, bellyMode: Float, speciesID: Int = -1) -> Int {
        guard level > 0 else { return 0 }
        let pr = profile(forFlesh: flesh, speciesID: speciesID)
        // default: every species; `all` false (a test / dev argument) = the blue body only
        guard all || pr.species == .blue else { return 0 }
        return params(profile: pr)[0].y > 0.001 ? 2 : 1
    }

    // MARK: pipelines

    /// The stock matte-spec pipeline (same function constants as MelonPipelines.makeMatteSpec) plus constant 5 = true (the jelly maths compiled in).
    static func makePipeline(device: MTLDevice, library: MTLLibrary, vd: MTLVertexDescriptor, tier: Int, belly: Bool, teddy: Bool, probe: Int, fibre: Int, blended: Bool, dualSource: Bool = true) -> MTLRenderPipelineState? {
        let cv = MTLFunctionConstantValues()
        var t = Int32(tier), bl = belly, td = teddy, pr = Int32(probe), fm = Int32(fibre), on = true
        cv.setConstantValue(&t, type: .int, index: 0)
        cv.setConstantValue(&bl, type: .bool, index: 1)
        cv.setConstantValue(&td, type: .bool, index: 2)
        cv.setConstantValue(&pr, type: .int, index: 3)
        cv.setConstantValue(&fm, type: .int, index: 4)
        cv.setConstantValue(&on, type: .bool, index: 5)
        guard let fs = try? library.makeFunction(name: blended && dualSource ? "fsSoftMatteFastSee" : "fsSoftMatteFast", constantValues: cv), let vs = library.makeFunction(name: "vsJelly") else {
            print("JellyLook: fsSoftMatteFast unavailable"); return nil
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = blended ? "jelly look blended" : "jelly look opaque"
        d.vertexFunction = vs; d.fragmentFunction = fs
        d.vertexDescriptor = vd
        let ca = d.colorAttachments[0]!
        ca.pixelFormat = MelonRenderer.hdrFormat
        if blended {      // colour over what is behind; the stored alpha stays 0 as in the opaque pipeline
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = .add; ca.alphaBlendOperation = .add
            ca.sourceRGBBlendFactor = .one; ca.destinationRGBBlendFactor = dualSource ? .source1Color : .oneMinusSourceAlpha
            ca.sourceAlphaBlendFactor = .zero; ca.destinationAlphaBlendFactor = .zero
        }
        d.depthAttachmentPixelFormat = MelonRenderer.depthFormat
        d.rasterSampleCount = MelonRenderer.msaa
        guard let p = try? device.makeRenderPipelineState(descriptor: d) else { print("JellyLook: pipeline failed"); return nil }
        return p
    }

    /// Depth-only copy of the body draw (no fragment function, empty colour mask): the nearest surface of a see-through body.
    static func makeDepthOnly(device: MTLDevice, library: MTLLibrary, vd: MTLVertexDescriptor) -> MTLRenderPipelineState? {
        guard let vs = library.makeFunction(name: "vsJelly") else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.label = "jelly look depth"
        d.vertexFunction = vs
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = MelonRenderer.hdrFormat
        d.colorAttachments[0].writeMask = []
        d.depthAttachmentPixelFormat = MelonRenderer.depthFormat
        d.rasterSampleCount = MelonRenderer.msaa
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    /// Depth compare lessEqual, no depth write (the blended colour draw after the pre-pass).
    static func makeLessEqualNoWrite(device: MTLDevice) -> MTLDepthStencilState? {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = false
        return device.makeDepthStencilState(descriptor: d)
    }
}
