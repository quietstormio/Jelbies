//
//  OrientationForce.swift
//  Capture aid: `-ForceOrientation left|right|portrait` asks the window scene for that orientation at launch (the simulator window cannot always be rotated by hand).
//  "left" = UIInterfaceOrientation.landscapeLeft, "right" = .landscapeRight (the Dynamic Island on the other side).
//

import UIKit

enum OrientationForce {
    @MainActor static func apply() {
        guard let v = UserDefaults.standard.string(forKey: "ForceOrientation") else { return }
        let mask: UIInterfaceOrientationMask = v == "left" ? .landscapeLeft : v == "right" ? .landscapeRight : .portrait
        let want: UIInterfaceOrientation = v == "left" ? .landscapeLeft : v == "right" ? .landscapeRight : .portrait
        Task { @MainActor in
            // the first frames can be busy (the room builds): ask again until the scene is where it was told to be
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { continue }
                if scene.interfaceOrientation == want { return }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            }
        }
    }
}
