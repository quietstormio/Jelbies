//
//  DeviceMotionFeed.swift
//  Phone tilt and shake for focus mode (CoreMotion, iPhone only). Runs only while Bob is in focus mode; the numbers feed
//  TouchPlay.motionFrame (gravity x for the tilt, user acceleration magnitude for a shake). No permission prompt is needed.
//

import Foundation
import CoreMotion

@MainActor
final class DeviceMotionFeed {
    static let shared = DeviceMotionFeed()
    private let manager = CMMotionManager()
    private(set) var running = false
    /// Gravity x in the device frame, -1...1 (tilt right = positive).
    private(set) var gravityX: Float = 0
    /// User acceleration magnitude in g (a hand shake is about 1.5 and up).
    private(set) var shake: Float = 0

    nonisolated deinit {}

    func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        if !on {
            manager.stopDeviceMotionUpdates()
            gravityX = 0; shake = 0
            return
        }
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            let gx = Float(m.gravity.x)
            let a = m.userAcceleration
            let mag = Float((a.x * a.x + a.y * a.y + a.z * a.z).squareRoot())
            MainActor.assumeIsolated {
                self?.gravityX = gx
                self?.shake = mag
            }
        }
    }
}
