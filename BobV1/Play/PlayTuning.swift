//
//  PlayTuning.swift
//  The dials of Play mode (the ball and the bubble wand) added by play-frame-r1 (owner 2026-11-19: "keep them in the screen along with the ball ... zoom in like you're
//  doing but not as much ... make them run a little more when a ball is out").
//    camZoom   how far the room camera goes toward the play camera: 0 = the room's normal camera, 1 = the old play camera (the one the owner's screenshot shows).
//    old       `-PlayOld 1` (dev builds): every number of the old play mode (camera 1, no frame clamps, the old chase speed), for before / after.
//

import Foundation
import simd

/// How a ball is played (owner 2026-11-22: "the soccer ball should be mostly kicking and they can bounce it off their head ... the beach ball can be bounce off their head and kicked back but not as kick involved"). ONE table of numbers; step 2 / 3 read it (step 1: not used yet).
nonisolated struct BallStyle {
    /// Of the balls that come down through the air, how many are headed (the rest are let drop and kicked: a trap, then a foot).
    var headShare: Float
    /// How many balls go to a friend before they go back to the player (with two or three Jelmiko), and the most passes in one chain. A header passes in the air, a kick along the floor.
    var chainChance: Float
    var chainMax: Int
}

nonisolated enum PlayTuning {
    /// Soccer: a ground game (about 9 touches in 10 with the feet, half the balls passed 1...3 times); beach: an air game (about 60% headers, one ball in five to a friend); bouncy and footbag: as before.
    static func style(_ kind: DecorKind) -> BallStyle {
        switch kind {
        case .soccerball: return BallStyle(headShare: 0.12, chainChance: 0.5, chainMax: 3)
        case .beachball: return BallStyle(headShare: 0.9, chainChance: 0.2, chainMax: 1)
        default: return BallStyle(headShare: 1, chainChance: 0.16, chainMax: 1)
        }
    }
    /// A pass goes to a friend at least this far from the passer (bodies and faces never come close at a pass).
    static let passMinDist: Float = 1.3
    /// ... and at most this far (a pass is slow enough to follow with the eye: 0.8 to 1.1 s of travel).
    static let passMaxDist: Float = 3.4

    /// Dev builds only: `-BallReturnOld 1` = the header's approach (walk, turn onto the player, crouch, jump) is off: the ball returns as it did before play-ball-r2.
    nonisolated(unsafe) static var ballReturnOld: Bool = DevArgs.enabled && (UserDefaults.standard.integer(forKey: "BallReturnOld") != 0 || ProcessInfo.processInfo.environment["BALL_RETURN_OLD"] == "1")
    /// Dev builds only: `-PlayOld 1` = the play mode as it was (camera, floor, speed).
    nonisolated(unsafe) static var old: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "PlayOld") != 0
    /// Launch value of the camera dial (`-PlayZoom <0...1>`, dev builds); tests set `zoomOverride`.
    static var launchZoom: Float? {
        guard DevArgs.enabled, UserDefaults.standard.object(forKey: "PlayZoom") != nil else { return nil }
        return Float(min(max(UserDefaults.standard.double(forKey: "PlayZoom"), 0), 1))
    }
    nonisolated(unsafe) static var zoomOverride: Float?
    /// 0 = the room's normal camera ... 1 = the old play camera. Default 0.25 (a slight push-in).
    static let defaultCamZoom: Float = 0.25
    static var camZoom: Float { old ? 1 : (zoomOverride ?? launchZoom ?? defaultCamZoom) }
    /// While a ball is live the chase walks cover the ground this many times as fast as before (owner: "run a little more"; 15-25 % faster).
    static var chaseGain: Float = 1.27
    /// The ready steps of the ones not going for the ball: how far toward it (a fraction of the gap beyond `supportMinDist`), at most how far, how often.
    static var supportReach: Float = 0.65, supportMaxStep: Float = 1.6, supportMinDist: Float = 1.1, supportMinStep: Float = 0.38, supportMaxDist: Float = 3.2, supportEvery: Float = 1.5

    /// The bubble wand: how far the Jelmiko's own area may reach past the size the old play view gave them (sideways, in depth). Bubbles are not limited by it.
    static var wandSpreadK: Float = 1.5, wandDepthK: Float = 1.3
    /// The header's return flight to the hand: slope and cap (seconds before the floaty-ball factor). The old values are 0.07 and 1.25; a wider view puts the hand further away.
    static var returnFlightSlope: Float = 0.05, returnFlightCap: Float = 1.0
    /// How far nearer the camera than the old play view's row the Jelmiko line stands (world units), so the ball's trips to and from the hand keep about the old length. Not further: a weak return then lands beyond what the Jelmiko can follow (PlayTossTests `testAMissedBall...` fails at 1.75).
    static var rowForward: Float = 1.0
    /// A loose ball resting where nobody sends it back is lobbed to the hand after this long (old 2 s).
    static var restRescue: Float = 2
    /// The throw's flight to the Jelmiko: seconds per unit of range (old 0.085).
    static var throwFlightSlope: Float = 0.085

    /// How far (screen points) a body standing at floor point `p` sticks out of a screen of `size` through the camera now: 0 = whole on screen. The body box is 0.9 sideways
    /// (wings, spines, sway), 0.8 deep and 1.25 body heights tall (ears, antennas, hat), as HUDLayout.frontBandTop reads it. Tests and the `-PlayDemo` / `-BubbleDemo` log use it.
    @MainActor static func edgeCut(_ p: SIMD2<Float>, size: CGSize) -> CGFloat {
        let e = GameCamera.roamLateralExtent, d: Float = 0.8, h = BobShape.H * 1.25
        var cs = [SIMD3<Float>]()
        for cx in [p.x - e, p.x + e] { for cy in [Float(0), h] { for cz in [p.y - d, p.y + d] { cs.append(SIMD3(cx, cy, cz)) } } }
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let pts = Silhouette.project(cs, viewProj: cam.viewProj, size: size)
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(), let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return 999 }
        return max(0, -x0, x1 - size.width, -y0, y1 - size.height)
    }
}
