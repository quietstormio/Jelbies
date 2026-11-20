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
    /// Where the player's Jelbie waits while a rival performs in the middle, and where the rivals stand during the Trick round. The performer alone stands in the middle and the camera is
    /// close on it (2026-11-17, the owner: "zoom in or something to them"), so the others wait BEHIND it in a back row, each whole body and face in the picture and clear of the performer (the camera looks down 0.45 rad, so the row stands above her head):
    /// rival 0 back left, rival 1 back right, the player's Jelbie back middle, and rival 2 fully OFF the picture (right; left on its side) where she walks on from. Never a body half cut by the screen edge.
    /// Every mark is 1.5+ from every other.
    static let playerAside = SIMD2<Float>(0, -1.0)
    /// `sideways` (a phone / tablet on its side): the chrome column is on the right, so rival 2 waits off the picture to the LEFT instead.
    static func rivalRest(_ k: Int, sideways: Bool = false) -> SIMD2<Float> {
        let fixed = [SIMD2<Float>(-1.4, 0.4), SIMD2(1.4, 0.4), SIMD2(sideways ? -3.4 : 3.4, 2.6)]
        return k < fixed.count ? fixed[k] : SIMD2(1.3 + Float(k - 2) * 1.2, 0.6)
    }
    /// Where entrant k waits in the wing before she walks on to her rest spot (just outside the wide shot: left, left, right; a phone on its side: all from the left).
    static func wingSpot(_ k: Int, sideways: Bool, wide: Bool = false) -> SIMD2<Float> {
        if sideways { return [SIMD2<Float>(-6.5, 2.0), SIMD2(-7.2, 0.4), SIMD2(-6.0, -1.2)][min(k, 2)] }
        var p = [SIMD2<Float>(-4.7, 2.0), SIMD2(-5.4, 0.5), SIMD2(4.9, 0.6)][min(k, 2)]
        if wide { p.x += p.x < 0 ? -0.7 : 0.7 }          // (iPad portrait: the wide shot is wider, 0.80 fill instead of 0.88)
        return p
    }
    /// A parked Jelly (a home Jelmiko the show does not need) waits far off to the LEFT, out of every camera: the borrowed rival bodies wait far to the right
    /// (`GameCare.showFarSpot`, x 40...; the visitor spawn row is x 40..., z 0), so no two bodies ever share a spot (z stays inside the room floor's depth range).
    static func parkSpot(_ id: Int) -> SIMD2<Float> { SIMD2(-40 - Float(id) * 4, 2) }
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
    /// With `landLeft`: how far (share of the visible width) the camera target moves off the body, i.e. the body sits at 0.5 - landShift of the width.
    var landShift: Float = 0.22
    /// The camera's elevation above level (rad); the close-up's 0.17 unless a frame says otherwise (the Trick round looks down a little more so the back row shows over the performer).
    var elevation: Float = GameCamera.focusElevation
    /// The Look round (trimmed screen: the creature 1.45x bigger and centred in the space the judge line left); `lookPad` keeps the tablet's old numbers.
    static let look = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.39, fill: 0.67)
    static let lookPad = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.30, fill: 0.46)
    static func look(pad: Bool) -> ShowFrame { pad ? lookPad : look }
    /// The Trick round (2026-11-17, "zoom in or something to them"): ONE frame for the whole round (his pick, his trick, every entrant's turn), so the camera never jumps. It is on the performer
    /// alone (the middle), as big as lets the whole back row (`ShowStage.playerAside`, `rivalRest`) stay in the picture: ~34% of a phone portrait's width, 15% of its height (iPad 19%).
    /// The body's middle sits at 0.41: its feet are above the trick menu, and the result toast sits in the floor below it. A phone on its side puts the performer in the left half.
    static func trick(pad: Bool) -> ShowFrame {
        func dev(_ key: String, _ v: Float) -> Float { DevArgs.enabled && UserDefaults.standard.object(forKey: key) != nil ? Float(UserDefaults.standard.double(forKey: key)) : v }
        return ShowFrame(spots: [ShowStage.playerSpot],
                         screenY: dev("ShowTrickSY", pad ? 0.42 : 0.41), fill: dev("ShowTrickFill", pad ? 0.30 : 0.32),
                         landScreenY: dev("ShowTrickLandSY", 0.50), landFill: dev("ShowTrickLandFill", pad ? 0.50 : 0.62), landLeft: true, landShift: dev("ShowTrickLandShift", pad ? 0.27 : 0.25),
                         elevation: dev("ShowTrickEl", 0.45))
    }
    static var trick: ShowFrame { trick(pad: false) }
    static var trickPad: ShowFrame { trick(pad: true) }
    /// `pad` (iPad idiom only): the row of four fills less of a tablet portrait's width, so the end Jelbies (nearer the camera) are not cropped; false = the phone's numbers.
    /// One dancer (the trimmed Dance screen): the phone portrait fills 0.55 of the width with the body's middle at 0.34 (was 0.46 / 0.30); on its side the body sits left of the
    /// middle (x 0.41) at screenY 0.42 with nothing over it (the cheer strip is top right, the lane between the foot buttons).
    static func dance(bodies n: Int, pad: Bool = false) -> ShowFrame {
        if n <= 1 && !pad { return ShowFrame(spots: ShowStage.spots(bodies: 1), screenY: 0.34, fill: 0.55, landScreenY: 0.38, landFill: 0.9, landLeft: true, landShift: 0.09) }
        return ShowFrame(spots: ShowStage.spots(bodies: n), screenY: pad ? 0.38 : 0.30, fill: n > 1 ? (pad ? 0.66 : 0.84) : 0.46, landScreenY: 0.28, landFill: n > 1 ? 1.15 : 0.6, landLeft: false)
    }
    /// Results: she stands above every card (portrait) / in the left half with the cards in a right column (a phone on its side).
    static let results = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.25, fill: 0.42, landScreenY: 0.42, landFill: 0.55, landLeft: true)
    static let resultsPad = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.27, fill: 0.44, landScreenY: 0.22, landFill: 0.5, landLeft: false)
    static func results(pad: Bool) -> ShowFrame { pad ? resultsPad : results }
    static let practice = ShowFrame(spots: [ShowStage.playerSpot], screenY: 0.34, fill: 0.5, landScreenY: 0.3, landFill: 0.6, landLeft: false)
}
