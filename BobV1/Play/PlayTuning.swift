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
    static var chaseGain: Float = 1.2
    /// The ready steps of the ones not going for the ball: how far toward it (a fraction of the gap beyond `supportMinDist`), at most how far, how often.
    static var supportReach: Float = 0.5, supportMaxStep: Float = 1.4, supportMinDist: Float = 1.6, supportEvery: Float = 1.4
}
