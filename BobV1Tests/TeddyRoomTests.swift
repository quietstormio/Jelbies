//
//  TeddyRoomTests.swift
//  Capture (TEDDY_DIR set): one Teddy in the room through the game camera, portrait and landscape (the headless renderer; the simulator cannot be rotated from the shell).
//

import XCTest
import simd
import UIKit
@testable import BobV1

extension FeatureCaptureTests {
    func testTeddyRoomBothOrientations() throws {
        let d = try teddyDir(); teddyTone()
        DayClock.shared.forcedHour = 12
        for land in [false, true] {
            if land { W = 1311 * 2; H = 603 * 2 } else { W = 603 * 2; H = 1311 * 2 }
            GameCamera.configureRoom(count: 1)
            _ = GameCamera.camera(aspect: Float(W) / Float(H))
            let c = Char(id: 4)
            let lab = setUpLab([SIMD2(0.3, 0.5)], chars: [c], seed: 5)
            let r = lab.rigs[0]
            r.brain.idleForced = true; _ = r.brain.idleStart(.look, r.sim); r.brain.idleState.goalYaw = r.faceYaw; r.brain.idleState.hold = 0.01
            for _ in 0..<120 { lab.tick(watching: false) }
            let (ren, target) = try renderer(lab)
            let dd = dress(lab, [c])
            let cam = GameCamera.camera(aspect: Float(W) / Float(H), focus: 0)
            let img = composite(lab, dd, [c], ren, target, cam: cam)
            let pose = r.sim.bodyPose(iterations: 3)
            let k = cam.viewProj * SIMD4<Float>(pose.centroid.x, pose.centroid.y, pose.centroid.z, 1)
            let cx = (k.x / k.w * 0.5 + 0.5) * Float(W), cy = (1 - (k.y / k.w * 0.5 + 0.5)) * Float(H)
            let half = Float(land ? 330 : 420)
            let rect = CGRect(x: CGFloat(cx - half * (land ? 1.6 : 1)), y: CGFloat(cy - half), width: CGFloat(half * 2 * (land ? 1.6 : 1)), height: CGFloat(half * 2)).intersection(CGRect(x: 0, y: 0, width: W, height: H))
            if let cg = img.cgImage()?.cropping(to: rect) {
                try writePNG(tlabel(UIImage(cgImage: cg), ["Teddy in the room, game camera, \(land ? "landscape" : "portrait") (headless real renderer)"]), d + (land ? "/08_room_landscape.png" : "/07_room_portrait.png"))
            }
        }
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
    }
}
