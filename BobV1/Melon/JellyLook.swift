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
    /// Phone test build switch: set to e.g. (level: 1, all: true) to make that level the default for all species (or the blue body only with all: false)
    /// without launch arguments. Leave nil when committing; launch arguments still win where DevArgs.enabled.
    static let phoneTest: (level: Int, all: Bool)? = (1, true)
    nonisolated(unsafe) static var dbgFrame = 0

    /// Neon cap (species-generic rule in the jelly shader: bright AND saturated colours, i.e. yellow and green, are softened and deepened; Blue, Lavender, Teddy, Pearl, Panda are untouched).
    /// Presets for the owner's pick: classic = off (today), a = softer, b = softer + a bit deeper, c = clearly deeper. `-JellyNeon a|b|c` (dev args) or the single overrides -JellySoft -JellyDeepen -JellyNeonY0 -JellyNeonY1.
    static let neon: (soft: Float, deepen: Float, y0: Float, y1: Float) = {
        guard DevArgs.enabled, let k = UserDefaults.standard.string(forKey: "JellyNeon") else { return (0, 0, 0.57, 0.72) }
        switch k.lowercased() {
        case "a": return (0.30, 0.00, 0.57, 0.72)
        case "b": return (0.35, 0.12, 0.57, 0.72)
        case "c": return (0.40, 0.26, 0.57, 0.72)
        default: return (0, 0, 0.57, 0.72)
        }
    }()

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

    /// 7 x float4 for the fragment shader (buffer 7): [0] = (on, see, core, gloss), [1] = (glow, rim, sat, smooth), [2] = (bend, edge, tint, warm), [3] = (bubbles, deep, dk, ck), [4] = (highlight shift x, y, flat, belly paint scale), [5] = (band low, band high, band lift), [6] = (neon soften, neon deepen, neon luminance start, end).
    static func params(level: Int) -> [SIMD4<Float>] {
        guard level > 0 else { return [SIMD4<Float>](repeating: .zero, count: 7) }
        // Round 4 presets (matched by measured numbers to the user's reference picture): L1 = the picture's look, opaque; L2 / L3 = the same, see-through.
        // `core` ([0].z) and `edge` ([2].y) are unused; `sat` is 0 (`deep` darkens and saturates instead); `rim` = the light band's strength.
        //                         see   core  gloss glow  rim   sat   smooth edge  tint warm  bub  deep  dk    ck
        let p: [[Float]] = [[0.00, 0.00, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0],
                            [0.60, 0.00, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0],
                            [0.70, 0.85, 0.40, 0.70, 1.00, 0.00, 1.00, 0.0, 1.6, 0.8, 1.0, 1.0, 0.80, 2.0]]
        var v = p[min(level, 3) - 1]
        for (i, k) in ["See", "Core", "Gloss", "Glow", "Rim", "Sat", "Smooth", "Edge", "Tint", "Warm", "Bubbles", "Deep", "Dk", "Ck"].enumerated() { if let o = overrides[k] { v[i] = o } }
        return [SIMD4(1, v[0], v[1], v[2]), SIMD4(v[3], v[4], v[5], v[6]), SIMD4(overrides["Bend"] ?? 0, v[7], v[8], v[9]), SIMD4(v[10], v[11], v[12], v[13]),
                SIMD4(overrides["HiX"] ?? -0.03, overrides["HiY"] ?? 0.06, overrides["Flat"] ?? 0.7, overrides["Belly"] ?? 0.2),
                SIMD4(overrides["BandLo"] ?? 0.12, overrides["BandHi"] ?? 0.70, overrides["Lift"] ?? 2.1, 0),
                SIMD4(overrides["Soft"] ?? neon.soft, overrides["Deepen"] ?? neon.deepen, overrides["NeonY0"] ?? neon.y0, overrides["NeonY1"] ?? neon.y1)]
    }

    /// 0 = not a jelly body (matte as before), 1 = jelly shading on the opaque pipeline, 2 = see-through (own pass, blended).
    /// Panda (BlueBelly mode 51) draws in two parts and stays matte; bath and jersey bodies are decided by the caller.
    static func kind(flesh: SIMD4<Float>, bellyMode: Float) -> Int {
        guard level > 0 else { return 0 }
        // the blue species by its palette colour with a tolerance (an adopted Blue's uniform is not always bit-equal to the palette); `all` = every body, Panda included
        let b = BlueBelly.blueFlesh
        guard all || (abs(flesh.x - b.x) < 0.01 && abs(flesh.y - b.y) < 0.01 && abs(flesh.z - b.z) < 0.01) else { return 0 }
        return params(level: level)[0].y > 0.001 ? 2 : 1
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
