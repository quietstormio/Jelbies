//
//  WallPicture.swift
//  A framed photo on the back wall of the room the Jelmiko live in (home, loft, cabin). The model, the allowed zone of each room and the clamp that keeps a
//  picture inside it. The photo itself is the game's OWN copy (Documents/Wall, WallPictureFiles.swift), so deleting the album photo never blanks the wall.
//
//  Wall units: x along the back wall (0 = the middle of the room), y up from the floor, the wall is the plane z = RoomLayout.minZ. The frames are Blender props
//  (tools/make_wall_frames, bundled as wallframe_frame_<id>_<shape>.bin, opening 1.0 high), scaled uniformly by the picture's height, so a corner never stretches.
//

import Foundation
import simd
import CoreGraphics

nonisolated enum WallFrame: String, Codable, CaseIterable, Sendable {
    case wood, white, pastel, gold
    var title: String { switch self { case .wood: return "Natural wood"; case .white: return "White"; case .pastel: return "Pastel"; case .gold: return "Gold" } }
    /// How far the moulding (and its ornaments) reaches beyond the picture's edge, in picture heights (read off the Blender export; WallPictureTests checks it against the bundled art).
    var edge: Float { switch self { case .wood: return 0.094; case .white: return 0.100; case .pastel: return 0.095; case .gold: return 0.189 } }
    /// How far the frame stands out from the wall, in picture heights.
    var depth: Float { switch self { case .wood: return 0.052; case .white: return 0.036; case .pastel: return 0.070; case .gold: return 0.148 } }
}

nonisolated enum WallShape: String, Codable, CaseIterable, Sendable {
    case portrait, square, landscape
    /// Picture width / height.
    var aspect: Float { switch self { case .portrait: return 0.75; case .square: return 1; case .landscape: return 4.0 / 3.0 } }
}

/// How the game's copy was cut from the album photo: the window's centre (0...1 of the photo, y from the top) and a zoom (1 = the biggest window of the shape's
/// proportions that fits in the photo; 2 = half as wide and high).
nonisolated struct WallCrop: Codable, Equatable, Sendable {
    var cx: Float = 0.5, cy: Float = 0.5, zoom: Float = 1
    /// The window in a photo of `size` pixels, kept inside the photo.
    func rect(imageSize size: CGSize, aspect: Float) -> CGRect {
        let a = CGFloat(aspect), z = CGFloat(max(zoom, 1))
        var w = size.width, h = w / a
        if h > size.height { h = size.height; w = h * a }
        w /= z; h /= z
        let x = min(max(CGFloat(cx) * size.width - w / 2, 0), size.width - w)
        let y = min(max(CGFloat(cy) * size.height - h / 2, 0), size.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

nonisolated struct WallPicture: Codable, Equatable, Sendable {
    var id: Int = 1
    /// The game's own copy, a file name inside Documents/Wall (at most 1024 px on the long edge, already cut to the shape).
    var file: String
    var frame: WallFrame
    var shape: WallShape
    /// Centre of the PICTURE (the opening) on the wall, in wall units.
    var x: Float
    var y: Float
    /// Width of the picture (the opening); the height follows from the shape. The frame stands outside it.
    var width: Float
    var crop = WallCrop()
    /// The album photo it was cut from (a file name in Documents/Photos), for changing the crop later; nil when that photo is gone.
    var source: String?

    var height: Float { width / shape.aspect }
    var outerWidth: Float { width + 2 * frame.edge * height }
    var outerHeight: Float { height * (1 + 2 * frame.edge) }
    /// The name of the bundled frame art.
    var artID: String { "frame_\(frame.rawValue)_\(shape.rawValue)" }
}

/// Where a picture may hang in each room: the part of the back wall above the windows (and clear of the stove pipe) that the portrait camera shows below the message bar.
/// A phone on its side sees less of the wall (it shows up to about y = 5.2): the picture then hangs partly or wholly above what is on screen. That is accepted.
nonisolated enum WallZone {
    struct Rect: Equatable, Sendable { var minX: Float, maxX: Float, minY: Float, maxY: Float
        var width: Float { maxX - minX }; var height: Float { maxY - minY } }
    static let margin: Float = 0.05
    /// Smallest picture the player can make (width of the picture, wall units).
    static let minWidth: Float = 0.8

    static func rect(_ room: RoomID) -> Rect? {
        switch room {
        case .home: return Rect(minX: -4.6, maxX: 4.6, minY: 4.5, maxY: 7.0)
        case .loft: return Rect(minX: -4.6, maxX: 4.6, minY: 4.75, maxY: 7.0)
        case .cabin: return Rect(minX: -3.9, maxX: 4.6, minY: 3.75, maxY: 7.0)
        default: return nil
        }
    }
    static func allows(_ room: RoomID) -> Bool { rect(room) != nil }

    /// The biggest picture width that fits the zone in `room` with its frame (nil when the room has no zone).
    static func maxWidth(_ room: RoomID, frame: WallFrame, shape: WallShape) -> Float? {
        guard let r = rect(room) else { return nil }
        let k = frame.edge, a = shape.aspect
        // outer width = w (1 + 2k / a) ; outer height = (w / a) (1 + 2k)
        let byW = (r.width - 2 * margin) / (1 + 2 * k / a), byH = (r.height - 2 * margin) * a / (1 + 2 * k)
        return min(byW, byH)
    }

    /// The picture as it hangs in `room`: shrunk when it is too big for the zone, then moved inside it. Nil in a room that has no zone (nothing is drawn there).
    static func clamp(_ p: WallPicture, in room: RoomID) -> WallPicture? {
        guard let r = rect(room), let cap = maxWidth(room, frame: p.frame, shape: p.shape) else { return nil }
        var q = p
        q.width = min(max(p.width, min(minWidth, cap)), cap)
        let hw = q.outerWidth / 2 + margin, hh = q.outerHeight / 2 + margin
        q.x = min(max(p.x, r.minX + hw), r.maxX - hw)
        q.y = min(max(p.y, r.minY + hh), r.maxY - hh)
        return q
    }

    /// Where a picture first hangs: centred above the middle of the window row, as big as the band allows up to `defaultWidthCap`, high in the band.
    /// (Home, landscape, wood frame: a picture 2.7 wide and 2.0 high, 3.1 x 2.4 with its frame, about a third of the portrait screen's width; the owner's circle was roughly 60%.)
    static let defaultWidthCap: Float = 2.8
    static func defaultPlacement(room: RoomID, frame: WallFrame, shape: WallShape, file: String, crop: WallCrop = WallCrop(), source: String? = nil) -> WallPicture? {
        guard let r = rect(room), let cap = maxWidth(room, frame: frame, shape: shape) else { return nil }
        let w = min(cap, defaultWidthCap)
        let p = WallPicture(file: file, frame: frame, shape: shape, x: 0, y: (r.minY + r.maxY) / 2, width: w, crop: crop, source: source)
        return clamp(p, in: room)
    }
}
