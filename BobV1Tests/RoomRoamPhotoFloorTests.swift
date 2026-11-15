//
//  RoomRoamPhotoFloorTests.swift
//  The roaming floor is the floor of the GAME's camera. `GameCamera.refreshRoam` used to read the bottom edge of the screen through whatever pose `camera()` returned,
//  so a rebuild while Photo mode's / the species picker's orbit (PhotoCam) or the contact capture pose (ContactDemo.pose) was on gave a floor the game never shows:
//  under the picker's naming view a portrait phone's front row was 11.78 instead of 9.03 (a body walks off the bottom of the screen once the game camera is back).
//  Now `refreshRoam` asks for the game pose (`gamePose: true`): the floor, its free spans and the round wall are the same whatever those two overlays are doing.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class RoomRoamPhotoFloorTests: XCTestCase {
    private static let aspects: [(name: String, aspect: Float)] = [
        ("phone portrait", 393 / 852), ("phone landscape", 852 / 393), ("tablet portrait", 820 / 1180), ("tablet landscape", 1180 / 820),
    ]

    /// Everything these tests change in the camera's statics and in the two overlays; `restore` puts it back.
    private struct Globals {
        let floor = GameCamera.roamFloor, centre = GameCamera.arenaCenter, radius = GameCamera.arenaRadius, walkMaxZ = GameCamera.walkMaxZ, aspect = GameCamera.aspect
        let active = PhotoCam.active, yaw = PhotoCam.yaw, pitch = PhotoCam.pitch, zoom = PhotoCam.zoom, pan = PhotoCam.pan, pose = ContactDemo.pose
        @MainActor func restore() {
            PhotoCam.active = active; PhotoCam.yaw = yaw; PhotoCam.pitch = pitch; PhotoCam.zoom = zoom; PhotoCam.pan = pan; ContactDemo.pose = pose
            GameCamera.configureRoom(count: 1)
            if let f = floor { GameCamera.roamFloor = f; RoomLayout.setFront(z: f.maxZ + 0.8) } else { GameCamera.clearRoam() }
            GameCamera.arenaCenter = centre; GameCamera.arenaRadius = radius; GameCamera.walkMaxZ = walkMaxZ; GameCamera.aspect = aspect
        }
    }

    /// One state of the two overlays that `camera()` lays over the game's pose.
    private struct Look {
        var name: String
        var photo = true
        var yaw: Float = 0, pitch: Float = 0, zoom: Float = 1, pan = SIMD2<Float>(0, 0)
        var demo: (eye: SIMD3<Float>, target: SIMD3<Float>)? = nil
        /// false: the overlay is on but leaves the pose where it is (Photo mode just opened, nothing dragged yet)
        var moves = true
        func apply() {
            PhotoCam.active = photo; PhotoCam.yaw = yaw; PhotoCam.pitch = pitch; PhotoCam.zoom = zoom; PhotoCam.pan = pan
            ContactDemo.pose = demo
        }
        static func off() { PhotoCam.active = false; PhotoCam.reset(); ContactDemo.pose = nil }
    }

    /// Photo mode at rest and at its limits, the species picker's three views, the contact capture's side orbit and its tracked pose.
    private var looks: [Look] {
        [
            Look(name: "Photo mode just opened", moves: false),
            Look(name: "picker naming view", yaw: PickerCamera.nameYaw, zoom: PickerCamera.startZoom),
            Look(name: "picker page, Pip's turn", yaw: PickerCamera.startYaw(1), zoom: PickerCamera.startZoom),
            Look(name: "picker row", yaw: PickerCamera.rowYaw(0), zoom: PickerCamera.rowZoom),
            Look(name: "Photo mode far right, high, out", yaw: PhotoCam.yawLimit, pitch: PhotoCam.pitchRange.upperBound, zoom: PhotoCam.zoomRange.upperBound, pan: SIMD2<Float>(PhotoCam.panX, PhotoCam.panY)),
            Look(name: "Photo mode far left, low, in", yaw: -PhotoCam.yawLimit, pitch: PhotoCam.pitchRange.lowerBound, zoom: PhotoCam.zoomRange.lowerBound, pan: SIMD2<Float>(-PhotoCam.panX, -PhotoCam.panY)),
            Look(name: "contact capture, side orbit", yaw: 1.2, pitch: -0.3, zoom: 0.8, pan: SIMD2<Float>(0, 0.45)),
            Look(name: "contact capture, tracked pose", photo: false, demo: (eye: SIMD3<Float>(6, 9, 12), target: SIMD3<Float>(0, 0.6, 1))),
        ]
    }

    /// The floor (rows, half widths, free spans) and the round wall built from it are the same under every look as with both overlays off.
    func testTheFloorIsTheGameCamerasWhateverTheOverlaysDo() {
        let g = Globals(); defer { g.restore() }
        for (name, aspect) in Self.aspects {
            GameCamera.configureRoom(count: 1)
            Look.off()
            guard let base = GameCamera.refreshRoam(aspect: aspect) else { XCTFail("\(name): no floor"); continue }
            let centre = GameCamera.arenaCenter, radius = GameCamera.arenaRadius
            print(String(format: "[photofloor] %@: game floor z %.2f..%.2f, %d rows, hwMax %.2f, wall (%.2f,%.2f) r %.2f", name, base.minZ, base.maxZ, base.zs.count, base.hw.max() ?? 0, centre.x, centre.y, radius))
            for look in looks {
                look.apply()
                let built = GameCamera.refreshRoam(aspect: aspect)
                let c = GameCamera.arenaCenter, r = GameCamera.arenaRadius
                Look.off()
                guard let f = built else { XCTFail("\(name), \(look.name): no floor"); continue }
                print(String(format: "[photofloor] %@ under %@: z %.2f..%.2f, %d rows, hwMax %.2f, wall (%.2f,%.2f) r %.2f", name, look.name, f.minZ, f.maxZ, f.zs.count, f.hw.max() ?? 0, c.x, c.y, r))
                XCTAssertEqual(f.minZ, base.minZ, "\(name), \(look.name): back row")
                XCTAssertEqual(f.maxZ, base.maxZ, "\(name), \(look.name): front row")
                XCTAssertEqual(f.zs, base.zs, "\(name), \(look.name): rows")
                XCTAssertEqual(f.hw, base.hw, "\(name), \(look.name): half widths")
                XCTAssertEqual(f.free, base.free, "\(name), \(look.name): free spans")
                XCTAssertEqual(c, centre, "\(name), \(look.name): wall centre")
                XCTAssertEqual(r, radius, "\(name), \(look.name): wall radius")
            }
        }
    }

    /// What the old line read: under the picker's naming view the bottom of the screen meets the floor far in front of where the game's camera sees it, and the
    /// front row it gave (the old `min(max(z - roamBodyDepth, walkMaxZ), roamMaxZCap)`) lies well in front of the game floor's. `gamePose: true` reads the game's point.
    func testTheNamingViewMovedTheOldFrontRowAndTheGamePoseDoesNot() {
        let g = Globals(); defer { g.restore() }
        for (name, aspect) in Self.aspects {
            GameCamera.configureRoom(count: 1)
            Look.off()
            guard let base = GameCamera.refreshRoam(aspect: aspect) else { XCTFail("\(name): no floor"); continue }
            let size = CGSize(width: CGFloat(1000 * aspect), height: 1000)
            let bottom = CGPoint(x: size.width / 2, y: CGFloat((1 - GameCamera.roamBottomMargin) * 1000))
            guard let plain = GameCamera.floorPoint(screen: bottom, size: size), let game = GameCamera.floorPoint(screen: bottom, size: size, gamePose: true) else {
                XCTFail("\(name): the bottom of the screen misses the floor"); continue
            }
            XCTAssertEqual(plain, game, "\(name): with both overlays off the two readings are one")
            Look(name: "picker naming view", yaw: PickerCamera.nameYaw, zoom: PickerCamera.startZoom).apply()
            let movedPoint = GameCamera.floorPoint(screen: bottom, size: size), keptPoint = GameCamera.floorPoint(screen: bottom, size: size, gamePose: true)
            Look.off()
            guard let moved = movedPoint, let kept = keptPoint else { XCTFail("\(name): the bottom of the screen misses the floor under the naming view"); continue }
            let oldFront = min(max(moved.y - GameCamera.roamBodyDepth, GameCamera.walkMaxZ), GameCamera.roamMaxZCap)
            print(String(format: "[photofloor] %@, bottom of the screen: game z %.2f, naming view z %.2f (x %.2f); old front %.2f, game floor's front row %.2f", name, game.y, moved.y, moved.x, oldFront, base.maxZ))
            XCTAssertEqual(kept, game, "\(name): the game pose's reading does not move with the picker's camera")
            XCTAssertGreaterThan(moved.y - game.y, 0.5, "\(name): the plain reading moves with the picker's camera (what the old floor was built from)")
            XCTAssertGreaterThan(oldFront, base.maxZ + 2.0, "\(name): the old front row lies well in front of the game floor's")
        }
    }

    /// `camera(gamePose: true)` is the plain camera while both overlays are off, and stays where it is when they move the plain one.
    func testTheGamePoseCameraIgnoresTheOverlays() {
        let g = Globals(); defer { g.restore() }
        for (name, aspect) in Self.aspects {
            GameCamera.configureRoom(count: 1)
            Look.off()
            let plain = GameCamera.camera(aspect: aspect), game = GameCamera.camera(aspect: aspect, gamePose: true)
            XCTAssertEqual(plain.pos, game.pos, "\(name): eye, overlays off")
            XCTAssertEqual(plain.fwd, game.fwd, "\(name): direction, overlays off")
            for look in looks {
                look.apply()
                let moved = GameCamera.camera(aspect: aspect), kept = GameCamera.camera(aspect: aspect, gamePose: true)
                Look.off()
                XCTAssertEqual(kept.pos, game.pos, "\(name), \(look.name): the game pose's eye")
                XCTAssertEqual(kept.fwd, game.fwd, "\(name), \(look.name): the game pose's direction")
                if look.moves { XCTAssertGreaterThan(simd_distance(moved.pos, game.pos), 0.05, "\(name), \(look.name): the overlay moves the plain camera") }
            }
        }
    }
}
