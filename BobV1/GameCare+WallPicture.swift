//
//  GameCare+WallPicture.swift
//  Feeds the room renderer the framed photo on the back wall (Room/WallPicture.swift): rebuilt only when the saved picture, the room or the "visiting" state changes;
//  the photo is decoded off the main thread and joins the cached room when it arrives. Nothing is drawn in the café, park, beach, groomer, camp or a competition.
//  Developer launch arguments (DevArgs gate, never in an App Store build): -WallPicture <frame>,<shape>[,<x>,<y>,<width>] with -WallPictureFile <photo path>
//  and optionally -WallPictureCrop <cx>,<cy>,<zoom>, e.g. `-WallPicture gold,landscape -WallPictureFile /tmp/sample.jpg`.
//

import Foundation
import Metal
import UIKit

/// What the renderer was last given for the wall picture.
@MainActor
final class WallPictureDrawn {
    struct Key: Equatable {
        var picture: WallPicture?; var room: RoomID; var hidden: Bool
        /// The window of the photo shown (the editor slides it), the file shown, and the screen's shape and the editor's camera state (the landscape rule reads them).
        var uv: SIMD4<Float>; var path: String; var aspect: Int; var editing: Bool; var cameraRaised: Bool
    }
    var key: Key?
    /// The decoded photos (a few, by path): the same file is not decoded again for a room change or a move.
    var textures: [String: MTLTexture] = [:]
    var loading: Set<String> = [], failed: Set<String> = []
    weak var room: RoomRenderer?
    nonisolated deinit {}
}

extension GameCare {
    /// Dev only (`-WallLandscapeRule 0`): keeps drawing a picture that is mostly off the top of a phone on its side, for the before / after capture.
    private var landscapeRuleOn: Bool { !(DevArgs.enabled && UserDefaults.standard.object(forKey: "WallLandscapeRule") != nil && UserDefaults.standard.integer(forKey: "WallLandscapeRule") == 0) }

    func refreshWallPicture(renderer: MelonRenderer?) {
        guard let room = renderer?.room else { return }
        let hidden = cafe.hidesDecor || park.hidesDecor || volley.hidesDecor || groom.inScene
        let ed = wallEdit
        let pic = ed?.draft ?? store.wallPicture
        let path = ed.map { $0.textureURL.path } ?? pic.map { WallPictureFiles.url($0.file).path } ?? ""
        let key = WallPictureDrawn.Key(picture: pic, room: RoomLayout.current.id, hidden: hidden, uv: ed?.uvWindow ?? SIMD4(0, 0, 1, 1), path: path,
                                       aspect: Int(GameCamera.aspect * 100), editing: ed != nil, cameraRaised: GameCamera.wallEditBlend > 0)
        guard key != wallDrawn.key else { return }
        wallDrawn.key = key
        wallDrawn.room = room
        guard !hidden, let current = key.picture, let p = WallZone.clamp(current, in: key.room) else {
            if room.hasWallPicture { room.setWallPicture(nil, texture: nil) }
            room.hidesLoftArt = false
            return
        }
        // a picture that is (almost) entirely above the top of the screen is not drawn outside the editor: a sliver of its bottom edge reads as a bug
        if ed == nil, !key.cameraRaised, landscapeRuleOn, let top = GameCamera.wallVisibleTop(aspect: GameCamera.aspect),
           WallZone.visibleShare(p, visibleTop: top) < WallZone.minVisibleShare {
            if room.hasWallPicture { room.setWallPicture(nil, texture: nil) }
            room.hidesLoftArt = WallZone.hidesLoftArt(p, in: key.room)
            return
        }
        room.hidesLoftArt = WallZone.hidesLoftArt(p, in: key.room)
        guard let tex = wallDrawn.textures[path] else {
            // the photo is not here yet: nothing new is shown (frame, photo and shadow come together, never a bare frame); what hangs now stays until it arrives
            loadWallTexture(path, room)
            return
        }
        room.setWallPicture(WallPictureGeometry.build(p, art: WallPictureGeometry.art(p), uv: key.uv), texture: tex)
    }

    private func loadWallTexture(_ path: String, _ room: RoomRenderer) {
        guard !wallDrawn.loading.contains(path), !wallDrawn.failed.contains(path) else { return }
        wallDrawn.loading.insert(path)
        room.loadWallPhoto(URL(fileURLWithPath: path)) { [weak self] t in
            nonisolated(unsafe) let texture = t
            Task { @MainActor in
                guard let self else { return }
                self.wallDrawn.loading.remove(path)
                if let texture {
                    if self.wallDrawn.textures.count >= 3 { self.wallDrawn.textures = self.wallDrawn.textures.filter { $0.key == self.wallDrawn.key?.path } }
                    self.wallDrawn.textures[path] = texture
                } else { self.wallDrawn.failed.insert(path) }
                self.wallDrawn.key = nil          // draw again now that the photo is here
            }
        }
    }

    /// `-WallPicture frame,shape[,x,y,width]` + `-WallPictureFile path` [+ `-WallPictureCrop cx,cy,zoom`]: hangs a sample picture (dev builds only).
    func applyWallPictureLaunchArguments(defaults d: UserDefaults = .standard) { WallDemo.prepare(store: store, defaults: d); WallPictureDev.apply(defaults: d, store: store) }
}

enum WallPictureDev {
    @MainActor @discardableResult
    static func apply(defaults d: UserDefaults, store: StoreBook) -> WallPicture? {
        guard DevArgs.enabled, let spec = d.string(forKey: "WallPicture") else { return nil }
        let f = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count >= 2, let frame = WallFrame(rawValue: f[0]), let shape = WallShape(rawValue: f[1]),
              let path = d.string(forKey: "WallPictureFile"), let img = WallPictureFiles.image(at: URL(fileURLWithPath: path)) else { return nil }
        let c = (d.string(forKey: "WallPictureCrop") ?? "").split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        let crop = c.count == 3 ? WallCrop(cx: c[0], cy: c[1], zoom: c[2]) : WallCrop()
        guard let file = WallPictureFiles.bake(source: img, shape: shape, crop: crop) else { return nil }
        let n = f.dropFirst(2).map { Float($0) }
        var p = WallZone.defaultPlacement(room: .home, frame: frame, shape: shape, file: file, crop: crop, source: URL(fileURLWithPath: path).lastPathComponent)
            ?? WallPicture(file: file, frame: frame, shape: shape, x: 0, y: 5.5, width: 2, crop: crop)
        if n.count >= 3, let x = n[0], let y = n[1], let w = n[2] { p.x = x; p.y = y; p.width = w }
        return store.hangWallPicture(p)
    }
}
