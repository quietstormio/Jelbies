//
//  StoreBook+WallPicture.swift
//  The framed photo on the wall, saved with the rest of the store (StoreBook.Saved.wallPictures). One picture for now.
//

import Foundation

extension StoreBook {
    var wallPictures: [WallPicture] { saved.wallPictures ?? [] }
    var wallPicture: WallPicture? { wallPictures.first }
    /// The picture frames the player has bought (the Shop's Rooms tab).
    func ownsFrame(_ f: WallFrame) -> Bool { count("frame-\(f.rawValue)") > 0 }
    var ownedWallFrames: [WallFrame] { WallFrame.allCases.filter { ownsFrame($0) } }

    /// Hangs `p` (replacing the picture on the wall; its old file is deleted). Returns the picture as saved.
    @discardableResult
    func hangWallPicture(_ p: WallPicture) -> WallPicture {
        let old = wallPicture
        saved.wallPictures = [p]
        save()
        if let old, old.file != p.file { WallPictureFiles.remove(old.file) }
        return p
    }

    /// Moves / resizes / re-frames the picture on the wall without changing its photo.
    func updateWallPicture(_ change: (inout WallPicture) -> Void) {
        guard var p = wallPicture else { return }
        change(&p)
        saved.wallPictures = [p]
        save()
    }

    /// Takes the picture down: the saved entry and its copy of the photo go.
    func takeDownWallPicture() {
        guard let old = wallPicture else { return }
        saved.wallPictures = nil
        save()
        WallPictureFiles.remove(old.file)
    }
}
