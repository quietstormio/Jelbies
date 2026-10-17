//
//  GfxSavings.swift
//  Cheaper rendering with no visible change. Pure logic (no Metal / UIKit) so it unit tests:
//    - GfxFlags          launch-argument switches (-RoomCache, -MetalFX, -IdleRest), default ON in the app, OFF under XCTest.
//    - RoomCacheState    when the static-room colour cache may be built / used (invalidation state machine + counters).
//    - RoomFootprint     the screen rect that Bob (and his shadow / contact AO, and the dining tray) can change in the room.
//    - IdleRestGovernor  30 fps while nothing moves for 2 s; instant wake.
//

import Foundation
import simd

// MARK: - Flags

nonisolated enum GfxFlags {
    /// `-Name 1/0` wins; otherwise `defaultOn` outside XCTest (golden renders and unit tests keep the old path unless a test opts in).
    static func flag(_ name: String, defaultOn: Bool) -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: name) != nil { return d.bool(forKey: name) }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        return defaultOn
    }
    static var roomCache: Bool { flag("RoomCache", defaultOn: true) }
    /// MetalFX defaults OFF everywhere: spatial upscaling is a visible (softer) trade, not an identical one; the user opts in.
    static var metalFX: Bool { flag("MetalFX", defaultOn: false) }
    static var idleRest: Bool { flag("IdleRest", defaultOn: true) }
    /// Render scale (in native-pixel multiples) MetalFX renders at when the adaptive scaler is not driving it. -MetalFXScale 2.
    static var metalFXScale: Double { let v = UserDefaults.standard.double(forKey: "MetalFXScale"); return v >= 1 ? v : 2 }
}

// MARK: - Room cache invalidation

/// Everything that changes a pixel of the static room (shadow / contact-AO never do: they are re-shaded inside the footprint).
nonisolated struct RoomCacheKey: Equatable {
    var viewProj = matrix_identity_float4x4
    var camPos = SIMD3<Float>(repeating: 0)
    var width = 0, height = 0
    var themeTint = SIMD3<Float>(repeating: 0)
    var propsVersion = 0
    var keyDir = SIMD3<Float>(repeating: 0)
    var keyIntensity: Float = 0
    var fog = SIMD3<Float>(repeating: 0)
}

nonisolated enum RoomCacheMiss: String, CaseIterable {
    case disabled, camera, size, theme, props, light, settling, footprint
}

nonisolated enum RoomCacheAction: Equatable {
    /// Render the room the old way this frame.
    case bypass(RoomCacheMiss)
    /// Re-render the cache texture, then use it this frame.
    case build
    /// Draw the cached colour, re-shade only the footprint.
    case use
}

/// Pure state machine. The cache is only (re)built after the key has been unchanged for `settleFrames` frames, so a camera blend,
/// a carried bowl or a resize never pays for a cache that the next frame throws away.
nonisolated struct RoomCacheState {
    static let settleFrames = 3
    /// Above this share of the viewport the footprint saves too little (focus close-up): old path, cache kept.
    static let maxFootprint: Float = 0.5

    private(set) var key: RoomCacheKey?
    private(set) var stable = 0
    private(set) var built = false
    private(set) var frames = 0, hits = 0, builds = 0
    private(set) var misses: [RoomCacheMiss: Int] = [:]
    /// Footprint share of the last used frame (for the log).
    private(set) var lastFootprint: Float = 0
    /// Sum of footprint shares over hit frames: pixels shaded = this x viewport.
    private(set) var footprintSum: Float = 0

    mutating func frame(key k: RoomCacheKey, footprint: Float, enabled: Bool) -> RoomCacheAction {
        frames += 1
        guard enabled else { return miss(.disabled) }
        if let old = key, old != k {
            let reason = Self.reason(old, k)
            key = k; stable = 0; built = false
            return miss(reason)
        }
        if key == nil { key = k; stable = 0; built = false; return miss(.settling) }
        stable += 1
        lastFootprint = footprint
        if footprint > Self.maxFootprint { return miss(.footprint) }
        if !built {
            if stable < Self.settleFrames { return miss(.settling) }
            built = true; builds += 1; hits += 1; footprintSum += footprint
            return .build
        }
        hits += 1; footprintSum += footprint
        return .use
    }

    /// Drops the cache (device change, texture loss, tests).
    mutating func invalidate() { key = nil; stable = 0; built = false }

    private mutating func miss(_ m: RoomCacheMiss) -> RoomCacheAction { misses[m, default: 0] += 1; return .bypass(m) }

    static func reason(_ a: RoomCacheKey, _ b: RoomCacheKey) -> RoomCacheMiss {
        if a.width != b.width || a.height != b.height { return .size }
        if a.themeTint != b.themeTint { return .theme }
        if a.propsVersion != b.propsVersion { return .props }
        if a.keyDir != b.keyDir || a.keyIntensity != b.keyIntensity || a.fog != b.fog { return .light }
        return .camera
    }

    var hitRate: Double { frames > 0 ? Double(hits) / Double(frames) : 0 }
    /// "hit 87% build 2 miss camera 12 settling 6 ..." for the env log.
    var summary: String {
        let m = RoomCacheMiss.allCases.compactMap { r in misses[r].map { "\(r.rawValue) \($0)" } }.joined(separator: ", ")
        let avgFP = hits > 0 ? Double(footprintSum) / Double(hits) : 0
        return String(format: "hit %.0f%% of %d (builds %d, footprint %.0f%%; miss: %@)", hitRate * 100, frames, builds, avgFP * 100, m.isEmpty ? "-" : m)
    }
    mutating func resetCounters() { frames = 0; hits = 0; builds = 0; misses = [:]; footprintSum = 0 }
}

// MARK: - Footprint

/// Screen rect (pixels, y down) outside which Bob, his shadow and his contact AO cannot change the room's colour or depth.
nonisolated enum RoomFootprint {
    struct Rect: Equatable { var x: Int, y: Int, w: Int, h: Int
        var area: Int { w * h } }

    /// Slack around the AABB (world units): shadow PCF (+-0.04), contact-AO rings (0.26), normal offset, jelly overshoot.
    static let margin: Float = 0.4

    /// - bounds: Bob's world AABB (and the dining tray's, merged by the caller); `lightDir` = direction TOWARD the shadow light.
    /// - Returns the padded pixel rect, or the full viewport if any corner is at or behind the camera.
    static func rect(min lo: SIMD3<Float>, max hi: SIMD3<Float>, shadowDir: SIMD3<Float>, viewProj: simd_float4x4, width: Int, height: Int, pad: Int = 4) -> Rect {
        let full = Rect(x: 0, y: 0, w: width, h: height)
        let m = margin
        let a = lo - SIMD3(m, 0, m), b = hi + SIMD3(m, 0, m)
        var pts: [SIMD3<Float>] = []
        for i in 0..<8 {
            let p = SIMD3<Float>((i & 1) == 0 ? a.x : b.x, (i & 2) == 0 ? max(a.y - m, -0.2) : b.y + m, (i & 4) == 0 ? a.z : b.z)
            pts.append(p)
            // straight down onto the floor (contact AO) and along the shadow ray onto the floor / anything below him
            pts.append(SIMD3(p.x, 0, p.z))
            if shadowDir.y > 0.05 {
                let t = Swift.max(p.y, 0) / shadowDir.y
                pts.append(SIMD3(p.x - shadowDir.x * t, 0, p.z - shadowDir.z * t))
            }
        }
        var x0 = Float.infinity, y0 = Float.infinity, x1 = -Float.infinity, y1 = -Float.infinity
        for p in pts {
            let c = viewProj * SIMD4<Float>(p, 1)
            if !(c.w > 0.05) { return full }          // behind the camera, or NaN
            let nx = c.x / c.w, ny = c.y / c.w
            let sx = (nx * 0.5 + 0.5) * Float(width), sy = (0.5 - ny * 0.5) * Float(height)
            if !sx.isFinite || !sy.isFinite { return full }
            x0 = Swift.min(x0, sx); x1 = Swift.max(x1, sx); y0 = Swift.min(y0, sy); y1 = Swift.max(y1, sy)
        }
        let ix0 = Swift.max(0, Int(x0.rounded(.down)) - pad), iy0 = Swift.max(0, Int(y0.rounded(.down)) - pad)
        let ix1 = Swift.min(width, Int(x1.rounded(.up)) + pad), iy1 = Swift.min(height, Int(y1.rounded(.up)) + pad)
        guard ix1 > ix0, iy1 > iy0 else { return Rect(x: 0, y: 0, w: 1, h: 1) }
        return Rect(x: ix0, y: iy0, w: ix1 - ix0, h: iy1 - iy0)
    }

    static func share(_ r: Rect, width: Int, height: Int) -> Float { Float(r.area) / Float(Swift.max(width * height, 1)) }
}

// MARK: - Idle rest frame rate

/// Wants 30 fps once everything has been still for `restAfter` seconds; any activity returns to full rate at once.
nonisolated struct IdleRestGovernor {
    static let restAfter = 2.0
    /// Mean sim kinetic energy per unit mass (1/2 v^2) under which Bob counts as still.
    static let calmEnergy: Float = 2e-3

    private(set) var calmT = 0.0
    private(set) var resting = false

    /// `active` = any touch / script / walk / UI animation. `energy` = sim kinetic energy (nil = unknown, counts as active).
    /// Returns true if the resting state flipped.
    mutating func update(dt: Double, active: Bool, energy: Float?) -> Bool {
        guard dt > 0, dt < 0.5 else { return false }
        let busy = active || energy == nil || energy! > Self.calmEnergy
        if busy {
            calmT = 0
            if resting { resting = false; return true }
            return false
        }
        calmT += dt
        if !resting, calmT >= Self.restAfter { resting = true; return true }
        return false
    }

    /// Instant wake (touch began, motion onset): call from the event handler, not from draw.
    mutating func wake() -> Bool {
        calmT = 0
        if resting { resting = false; return true }
        return false
    }
}
