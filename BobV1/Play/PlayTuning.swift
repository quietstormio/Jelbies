//
//  PlayTuning.swift
//  The dials of Play mode (the ball and the bubble wand) added by play-frame-r1 (owner 2026-11-19: "keep them in the screen along with the ball ... zoom in like you're
//  doing but not as much ... make them run a little more when a ball is out").
//    camZoom   how far the room camera goes toward the play camera: 0 = the room's normal camera, 1 = the old play camera (the one the owner's screenshot shows).
//    old       `-PlayOld 1` (dev builds): every number of the old play mode (camera 1, no frame clamps, the old chase speed), for before / after.
//

import Foundation
import simd

nonisolated enum PlayTuning {
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
