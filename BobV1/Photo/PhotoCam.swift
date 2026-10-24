//
//  PhotoCam.swift
//  Photo mode's camera: an orbit / zoom / pan layered on whatever pose the game camera has (applied last in GameCamera.camera), inside safe limits
//  so the view never leaves the room. Off (identity) outside Photo mode; closing restores the game camera exactly.
//

import simd
import Foundation

enum PhotoCam {
    nonisolated(unsafe) static var active = false
    nonisolated(unsafe) static var yaw: Float = 0
    nonisolated(unsafe) static var pitch: Float = 0
    nonisolated(unsafe) static var zoom: Float = 1          // eye distance multiplier
    nonisolated(unsafe) static var pan = SIMD2<Float>(0, 0)  // target offset: right, up (world units)
    /// A tap on a Jelbie while Photo mode is up (the stage's single tap routes here).
    nonisolated(unsafe) static var onTapJelly: ((Int) -> Void)?

    static let yawLimit: Float = 0.7, pitchRange: ClosedRange<Float> = -0.12...0.30, zoomRange: ClosedRange<Float> = 0.35...1.08
    static let panX: Float = 2.4, panY: Float = 1.0

    static func reset() { yaw = 0; pitch = 0; zoom = 1; pan = .zero }
    static func orbit(dx: Float, dy: Float) {
        yaw = min(max(yaw - dx * 0.006, -yawLimit), yawLimit)
        pitch = min(max(pitch + dy * 0.004, pitchRange.lowerBound), pitchRange.upperBound)
    }
    static func zoom(by scale: Float) { zoom = min(max(zoom / max(scale, 0.01), zoomRange.lowerBound), zoomRange.upperBound) }
    static func drag(dx: Float, dy: Float) {
        let k = 0.01 * zoom
        pan.x = min(max(pan.x - dx * k, -panX), panX); pan.y = min(max(pan.y + dy * k, -panY), panY)
    }

    /// The game camera's pose, orbited / zoomed / panned.
    static func apply(eye e: SIMD3<Float>, target t: SIMD3<Float>) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let v = e - t, len = simd_length(v)
        guard len > 1e-3 else { return (e, t) }
        let y0 = atan2f(v.x, v.z), p0 = asinf(min(max(v.y / len, -1), 1))
        let y = y0 + yaw, p = min(max(p0 + pitch, 0.08), 0.75), r = len * zoom
        let right = SIMD3<Float>(cosf(y), 0, -sinf(y))
        let t2 = t + right * pan.x + SIMD3<Float>(0, pan.y, 0)
        return (t2 + SIMD3<Float>(sinf(y) * cosf(p), sinf(p), cosf(y) * cosf(p)) * r, t2)
    }
}
