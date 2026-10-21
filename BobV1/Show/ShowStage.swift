//
//  ShowStage.swift
//  The Jelly Show's stage set as a RoomMesh (the room renderer draws it instead of the living room while `showVisible`, like the race track):
//  a dark plum hall, a round lilac platform with a cream rim and a pale spotlight pool, two rose curtains and a valance, a deep backdrop with
//  star lights. Plus where the Jelbies stand on it and how the camera frames them (the focus close-up's maths, pulled back for the row).
//  Colours are the approved mockups' (#3B2E4F hall, #4E3D68 backdrop, #6B5487 platform, #C25A78 curtains, #FFF3C9 lights), linear.
//

import simd
import Foundation

nonisolated enum ShowModels {
    static func srgb(_ hex: UInt32, _ mul: Float = 1) -> SIMD3<Float> {
        OKLab.srgbToLinear(SIMD3(Float((hex >> 16) & 255), Float((hex >> 8) & 255), Float(hex & 255)) / 255 * mul)
    }
    static let hall = srgb(0x3B2E4F), backdrop = srgb(0x4E3D68), platform = srgb(0x6B5487), platformDeep = srgb(0x4E3D68)
    static let curtain = srgb(0xC25A78), curtainDeep = srgb(0x9E3F5D), rim = srgb(0xFFF3C9, 0.8), light = srgb(0xFFF3C9), pool = srgb(0xFFF3C9, 0.55)
    static let gold = srgb(0xFFE07A)
    /// The room shader's swatches on the stage: ground bounce (plum), haze (deep plum), sky light (a warm cream from the spotlights).
    static let swatch2 = srgb(0x3B2E4F), swatch3 = srgb(0x2A2038), swatch4 = srgb(0xFFF3C9, 0.9)
    /// Fog: start, end, max (a soft dark fall-off behind the backdrop).
    static let fog = SIMD3<Float>(16, 40, 0.35)

    /// The platform: centre (x, z) and radius; the Jelbies stand on it (its top is `platformY`).
    static let centre = SIMD2<Float>(0, 2.0)
    static let radius: Float = 3.0
    static let platformY: Float = 0.0           // the platform is a rim around floor level so the feet keep the room's floor height
    static let backdropZ: Float = -2.6
    static let curtainX: Float = 3.6

    static func build() -> RoomMesh {
        let b = RoomMeshBuilder()
        let up = SIMD3<Float>(0, 1, 0)
        b.material = .plain
        // the hall floor, dark, everywhere
        b.color = hall
        b.flatQuad(SIMD3(-40, -0.01, -40), SIMD3(-40, -0.01, 40), SIMD3(40, -0.01, 40), SIMD3(40, -0.01, -40), normal: up)
        // the platform: a shallow lilac disc with a cream rim, flush with the floor so the bodies stand on it as on the room floor
        var prof: [RoomMeshBuilder.ProfilePoint] = []
        prof.append(.init(r: 0, y: 0.0, nr: 0, ny: 1))
        prof.append(.init(r: radius - 0.22, y: 0.0, nr: 0, ny: 1))
        prof.append(.init(r: radius - 0.10, y: 0.0, nr: 0.3, ny: 1))
        prof.append(.init(r: radius, y: -0.01, nr: 1, ny: 0.2))
        b.lathe(cx: centre.x, cz: centre.y, profile: prof, segments: 64, color: platform)
        // the cream rim ring and a pale spotlight pool in the middle
        func ring(_ r0: Float, _ r1: Float, _ y: Float, _ col: SIMD3<Float>, _ N: Int = 64) {
            b.color = col
            for j in 0..<N {
                let a0 = Float(j) / Float(N) * 2 * .pi, a1 = Float(j + 1) / Float(N) * 2 * .pi
                let c0 = SIMD2(cosf(a0), sinf(a0)), c1 = SIMD2(cosf(a1), sinf(a1))
                b.flatQuad(SIMD3(centre.x + c0.x * r0, y, centre.y + c0.y * r0), SIMD3(centre.x + c1.x * r0, y, centre.y + c1.y * r0),
                           SIMD3(centre.x + c1.x * r1, y, centre.y + c1.y * r1), SIMD3(centre.x + c0.x * r1, y, centre.y + c0.y * r1), normal: up)
            }
        }
        ring(radius - 0.22, radius - 0.08, 0.004, rim)
        b.material = .glow
        ring(0, 1.55, 0.003, pool)
        ring(1.55, 1.9, 0.003, srgb(0xFFF3C9, 0.42))
        ring(1.9, 2.3, 0.003, srgb(0x8E74AA))
        b.material = .plain
        // the backdrop wall and the wings (deep plum), tall enough for every camera
        b.color = backdrop
        b.flatQuad(SIMD3(-30, -0.5, backdropZ), SIMD3(30, -0.5, backdropZ), SIMD3(30, 14, backdropZ), SIMD3(-30, 14, backdropZ), normal: SIMD3(0, 0, 1))
        b.flatQuad(SIMD3(-9, -0.5, backdropZ), SIMD3(-9, -0.5, 12), SIMD3(-9, 14, 12), SIMD3(-9, 14, backdropZ), normal: SIMD3(1, 0, 0))
        b.flatQuad(SIMD3(9, -0.5, 12), SIMD3(9, -0.5, backdropZ), SIMD3(9, 14, backdropZ), SIMD3(9, 14, 12), normal: SIMD3(-1, 0, 0))
        // star lights on the backdrop (small emissive beads), a seeded scatter that keeps the middle clear for the Jelbies
        b.material = .glow
        var rng = RaceRNG(seed: 0x5107)
        for _ in 0..<42 {
            let x = rng.range(-8.5, 8.5), y = rng.range(1.2, 9.5)
            if abs(x) < 2.6 && y < 4.2 { continue }
            let s = rng.range(0.035, 0.07)
            b.roundedBox(centre: SIMD3(x, y, backdropZ + 0.05), half: SIMD3(s, s, 0.03), radius: s * 0.9, segments: 2, aoFloor: false, color: rng.next() < 0.3 ? gold : light)
        }
        b.material = .plain
        // a soft spotlight halo on the backdrop behind the stage middle (plain, a little lighter than the wall: the glow material paints the sky)
        for (r, hex) in [(3.0, 0x5A4878), (2.1, 0x66548A), (1.3, 0x72609A)] as [(Float, UInt32)] {
            b.color = srgb(hex)
            let N = 40
            for j in 0..<N {
                let a0 = Float(j) / Float(N) * 2 * .pi, a1 = Float(j + 1) / Float(N) * 2 * .pi
                let cy: Float = 2.6
                b.flatQuad(SIMD3(0, cy, backdropZ + 0.02), SIMD3(cosf(a0) * r, cy + sinf(a0) * r * 0.8, backdropZ + 0.02), SIMD3(cosf(a1) * r, cy + sinf(a1) * r * 0.8, backdropZ + 0.02), SIMD3(0, cy, backdropZ + 0.02), normal: SIMD3(0, 0, 1))
            }
        }
        // the curtains: two tall rose columns with soft folds, and a valance across the top
        for side in [Float(-1), 1] {
            let x = side * curtainX
            b.roundedBox(centre: SIMD3(x, 2.9, -1.6), half: SIMD3(0.55, 3.1, 0.42), radius: 0.3, segments: 5, aoFloor: true, color: curtain)
            for k in 0..<3 {
                let fx = x + side * (0.1 + Float(k) * 0.16)
                b.roundedBox(centre: SIMD3(fx, 2.9, -1.6 + 0.3 + Float(k) * 0.08), half: SIMD3(0.09, 3.0, 0.1), radius: 0.08, segments: 2, aoFloor: true, color: k % 2 == 0 ? curtainDeep : curtain)
            }
            // a gold tie-back
            b.roundedBox(centre: SIMD3(x - side * 0.15, 2.2, -1.25), half: SIMD3(0.5, 0.12, 0.16), radius: 0.11, segments: 3, aoFloor: false, color: gold)
        }
        b.roundedBox(centre: SIMD3(0, 6.2, -1.7), half: SIMD3(curtainX + 0.7, 0.5, 0.45), radius: 0.3, segments: 4, aoFloor: false, color: curtain)
        for k in 0..<7 {
            let x = -3.6 + Float(k) * 1.2
            b.roundedBox(centre: SIMD3(x, 5.75, -1.45), half: SIMD3(0.42, 0.28, 0.2), radius: 0.2, segments: 3, aoFloor: false, color: curtainDeep)
        }
        return b.mesh
    }
}

/// Where the Jelbies stand on the stage and how the camera frames them.
nonisolated enum ShowStage {
    /// The player's spot (the front middle of the platform); the rival bodies stand either side, a little behind.
    static let playerSpot = SIMD2<Float>(0, 2.3)
    static func spots(bodies n: Int) -> [SIMD2<Float>] {
        (0..<max(n, 1)).map { k in
            if k == 0 { return playerSpot }
            let side: Float = k % 2 == 1 ? -1 : 1, rank = Float((k + 1) / 2)
            return SIMD2(playerSpot.x + side * rank * 1.35, playerSpot.y - 0.45)
        }
    }
    /// A parked Jelly (a body the show does not need) waits far off to the side, out of every camera.
    static func parkSpot(_ id: Int) -> SIMD2<Float> { SIMD2(40 + Float(id) * 4, 2) }
}

/// How the stage camera frames the show this frame (the glue sets it per round; the stage reads it with the show's camera blend).
nonisolated struct ShowFrame: Equatable, Sendable {
    /// The spots framed (one: the solo rounds; several: the dance row).
    var spots: [SIMD2<Float>]
    /// Where the bodies' middle sits on screen (0 top ... 1 bottom): high, the chrome takes the bottom.
    var screenY: Float
    /// Share of the screen width the bodies fill (looser than the close-up: the stage set stays visible).
    var fill: Float
    /// A phone on its side: where the bodies sit and how big (the cards take the right / the middle); `landLeft`: a solo body goes to the left third.
    var landScreenY: Float = 0.5
    var landFill: Float = 0.8
    var landLeft = true
    static let look = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.30, fill: 0.46)
    static let trick = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.33, fill: 0.50, landScreenY: 0.52, landFill: 0.78)
    static func dance(bodies n: Int) -> ShowFrame { ShowFrame(spots: ShowStage.spots(bodies: n), screenY: 0.30, fill: n > 1 ? 0.84 : 0.46, landScreenY: 0.28, landFill: n > 1 ? 1.15 : 0.6, landLeft: false) }
    static let results = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.27, fill: 0.44, landScreenY: 0.22, landFill: 0.5, landLeft: false)
    static let practice = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.34, fill: 0.5, landScreenY: 0.3, landFill: 0.6, landLeft: false)
}
