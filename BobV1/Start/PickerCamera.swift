//
//  PickerCamera.swift
//  The species picker's camera: dragging on the stage orbits the camera around the Jelbie (a limited swing left and right, a little tilt, never under
//  the floor or straight overhead), with soft inertia, and a pinch zooms a little. It drives PhotoCam (the same orbit layer Photo mode uses on the
//  game camera, clamped again in PhotoCam.apply), and hands the game camera back exactly on `release()`.
//

import Foundation

@MainActor
final class PickerCamera {
    static let yawLimit: Float = .infinity,  pitchRange: ClosedRange<Float> = -0.06...0.26, zoomRange: ClosedRange<Float> = 1.1...2.6, startZoom: Float = 1.6
    /// The resting 3/4 view per character: Pip's tail and spikes sit behind the body and only clear its silhouette past ~70 degrees, so his view is turned
    /// further (a simulator capture flag, -PickerYaw, can try others).
    static func startYaw(_ character: Int) -> Float {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.object(forKey: "PickerYaw") != nil { return UserDefaults.standard.float(forKey: "PickerYaw") }
        #endif
        switch character { case 1: return 1.2; case 3: return 0.7; default: return 0.5 }
    }
    private var yaw0: Float = 0.5
    /// Page changed: the new species' resting view (zoom and tilt reset).
    func setSpecies(_ c: Int) { coasting?.cancel(); vYaw = 0; yaw0 = Self.startYaw(c); PhotoCam.reset(); PhotoCam.zoom = Self.startZoom; PhotoCam.yaw = yaw0 }
    private var vYaw: Float = 0
    private var coasting: Task<Void, Never>?
    private var zoomBase: Float = 1
    var reduceMotion = false

    func engage() { PhotoCam.reset(); PhotoCam.zoom = Self.startZoom; PhotoCam.yaw = yaw0; PhotoCam.active = true }
    func release() { coasting?.cancel(); PhotoCam.active = false; PhotoCam.reset() }
    func reset() { coasting?.cancel(); vYaw = 0; PhotoCam.reset(); PhotoCam.zoom = Self.startZoom; PhotoCam.yaw = yaw0 }

    func drag(dx: Float, dy: Float) {
        coasting?.cancel()
        let y = PhotoCam.yaw - dx * 0.007
        PhotoCam.yaw = min(max(y, -Self.yawLimit), Self.yawLimit)
        PhotoCam.pitch = min(max(PhotoCam.pitch + dy * 0.003, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        vYaw = -dx * 0.007 * 60 * 0.5 + vYaw * 0.5          // rad/s, smoothed
    }

    /// Finger up: coast on with the last speed, easing out (and stopping at the swing limit).
    func endDrag() {
        coasting?.cancel()
        guard !reduceMotion, abs(vYaw) > 0.05 else { vYaw = 0; return }
        coasting = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, abs(self.vYaw) > 0.02 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                let y = PhotoCam.yaw + self.vYaw / 60
                PhotoCam.yaw = min(max(y, -Self.yawLimit), Self.yawLimit)
                if abs(PhotoCam.yaw) >= Self.yawLimit { self.vYaw = 0 }
                self.vYaw *= 0.94
            }
        }
    }

    func beginZoom() { zoomBase = PhotoCam.zoom }
    func zoom(magnification m: Float) { PhotoCam.zoom = min(max(zoomBase / max(m, 0.05), Self.zoomRange.lowerBound), Self.zoomRange.upperBound) }
}
