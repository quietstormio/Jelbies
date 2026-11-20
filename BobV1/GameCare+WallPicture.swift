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
    struct Key: Equatable { var picture: WallPicture?; var room: RoomID; var hidden: Bool }
    var key: Key?
    var texture: MTLTexture?
    var textureFile: String?
    var loading: String?
    weak var room: RoomRenderer?
    nonisolated deinit {}
}

extension GameCare {
    func refreshWallPicture(renderer: MelonRenderer?) {
        guard let room = renderer?.room else { return }
        let hidden = cafe.hidesDecor || park.hidesDecor || volley.hidesDecor || groom.inScene
        let key = WallPictureDrawn.Key(picture: store.wallPicture, room: RoomLayout.current.id, hidden: hidden)
        guard key != wallDrawn.key else { return }
        wallDrawn.key = key
        wallDrawn.room = room
        guard !hidden, let saved = key.picture, let p = WallZone.clamp(saved, in: key.room) else {
            if room.hasWallPicture { room.setWallPicture(nil, texture: nil) }
            room.hidesLoftArt = false
            return
        }
        room.hidesLoftArt = WallZone.hidesLoftArt(p, in: key.room)
        let tex = wallDrawn.textureFile == p.file ? wallDrawn.texture : nil
        room.setWallPicture(WallPictureGeometry.build(p, art: WallPictureGeometry.art(p)), texture: tex)
        guard tex == nil, wallDrawn.loading != p.file else { return }
        wallDrawn.loading = p.file
        let file = p.file
        room.loadWallPhoto(WallPictureFiles.url(file)) { [weak self] t in
            nonisolated(unsafe) let texture = t
            Task { @MainActor in
                guard let self, self.wallDrawn.loading == file else { return }
                self.wallDrawn.loading = nil
                self.wallDrawn.texture = texture; self.wallDrawn.textureFile = file
                if self.store.wallPicture?.file == file { self.wallDrawn.room?.setWallPhotoTexture(texture) }
            }
        }
    }

    /// `-WallPicture frame,shape[,x,y,width]` + `-WallPictureFile path` [+ `-WallPictureCrop cx,cy,zoom`]: hangs a sample picture (dev builds only).
    func applyWallPictureLaunchArguments(defaults d: UserDefaults = .standard) { WallPictureDev.apply(defaults: d, store: store) }
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
