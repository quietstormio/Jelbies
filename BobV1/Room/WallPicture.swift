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

/// Where a picture may hang in each room: a LIST of rectangles of the back wall. The first is the band above the windows (clear of the stove pipe) that the portrait camera shows
/// below the message bar. A phone on its side sees less of the wall (up to about y = 5.0): a picture in the band then hangs partly or wholly above what is on screen; that is
/// accepted and nothing moves it when the phone turns. The others are free spots that are on screen in BOTH orientations (`inBoth`): the gaps between the home windows, the wall between
/// the cabin's two windows, and in the loft the wall between the windows where the room's own wall art hangs (the art is hidden while a picture hangs there).
nonisolated enum WallZone {
    struct Rect: Equatable, Sendable { var minX: Float, maxX: Float, minY: Float, maxY: Float
        var width: Float { maxX - minX }; var height: Float { maxY - minY }
        func distance(x: Float, y: Float) -> Float { hypot(max(minX - x, 0, x - maxX), max(minY - y, 0, y - maxY)) }
        func intersects(_ o: Rect) -> Bool { minX < o.maxX && maxX > o.minX && minY < o.maxY && maxY > o.minY } }
    struct Spot: Equatable, Sendable {
        var name: String; var rect: Rect; var inBoth: Bool
        /// The shapes this spot takes: the narrow home gaps only an upright picture (a wide one would be a postage stamp there).
        var shapes: Set<WallShape> = Set(WallShape.allCases)
    }
    static let margin: Float = 0.05
    /// Smallest picture the player can make (width of the picture, wall units).
    static let minWidth: Float = 0.8

    static func spots(_ room: RoomID) -> [Spot] {
        switch room {
        case .home: return [Spot(name: "above the windows", rect: Rect(minX: -4.6, maxX: 4.6, minY: 4.5, maxY: 7.0), inBoth: false),
                            Spot(name: "between the windows, left", rect: Rect(minX: -2.0, maxX: -1.0, minY: 1.9, maxY: 4.1), inBoth: true, shapes: [.portrait]),
                            Spot(name: "between the windows, right", rect: Rect(minX: 1.0, maxX: 2.0, minY: 1.9, maxY: 4.1), inBoth: true, shapes: [.portrait])]
        case .loft: return [Spot(name: "above the windows", rect: Rect(minX: -4.6, maxX: 4.6, minY: 4.75, maxY: 7.0), inBoth: false),
                            Spot(name: "between the windows", rect: loftGap, inBoth: true, shapes: [.portrait, .square])]
        case .cabin: return [Spot(name: "above the windows", rect: Rect(minX: -3.9, maxX: 4.6, minY: 3.75, maxY: 7.0), inBoth: false),
                             Spot(name: "between the windows", rect: Rect(minX: -1.75, maxX: 1.75, minY: 1.9, maxY: 4.9), inBoth: true)]
        default: return []
        }
    }
    /// The loft's wall between its two big windows (the room's own "wallart" part hangs there).
    static let loftGap = Rect(minX: -0.78, maxX: 0.78, minY: 1.9, maxY: 4.4)
    /// The band above the windows (the first spot), nil in a room with no zone.
    static func rect(_ room: RoomID) -> Rect? { spots(room).first?.rect }
    static func allows(_ room: RoomID) -> Bool { !spots(room).isEmpty }

    /// The biggest picture width that fits `r` with its frame.
    static func maxWidth(in r: Rect, frame: WallFrame, shape: WallShape) -> Float {
        let k = frame.edge, a = shape.aspect
        // outer width = w (1 + 2k / a) ; outer height = (w / a) (1 + 2k)
        let byW = (r.width - 2 * margin) / (1 + 2 * k / a), byH = (r.height - 2 * margin) * a / (1 + 2 * k)
        return min(byW, byH)
    }
    static func maxWidth(_ room: RoomID, frame: WallFrame, shape: WallShape) -> Float? {
        rect(room).map { maxWidth(in: $0, frame: frame, shape: shape) }
    }

    /// The spot a picture belongs to: the one its centre is in, else the nearest.
    static func spot(for p: WallPicture, in room: RoomID) -> Spot? {
        spots(room).filter { $0.shapes.contains(p.shape) }.min { $0.rect.distance(x: p.x, y: p.y) < $1.rect.distance(x: p.x, y: p.y) }
    }

    /// The picture as it hangs in `room`: moved to its spot, shrunk when it is too big for it, then moved inside it. Nil in a room that has no zone (nothing is drawn there).
    static func clamp(_ p: WallPicture, in room: RoomID) -> WallPicture? {
        guard let sp = spot(for: p, in: room) else { return nil }
        let r = sp.rect, cap = maxWidth(in: r, frame: p.frame, shape: p.shape)
        var q = p
        q.width = min(max(p.width, min(minWidth, cap)), cap)
        let hw = q.outerWidth / 2 + margin, hh = q.outerHeight / 2 + margin
        q.x = min(max(p.x, r.minX + hw), r.maxX - hw)
        q.y = min(max(p.y, r.minY + hh), r.maxY - hh)
        return q
    }

    /// The loft's own wall art is hidden while the (clamped) picture hangs in the gap between the windows.
    static func hidesLoftArt(_ clamped: WallPicture?, in room: RoomID) -> Bool {
        guard room == .loft, let c = clamped else { return false }
        return abs(c.x) < loftGap.maxX && c.y < loftGap.maxY + 0.01 && c.y > loftGap.minY
    }

    /// Where a picture first hangs. Upright phone: centred above the middle of the window row (the band, the spot the owner circled), as big as the band allows up to `defaultWidthCap`.
    /// (Home, landscape, wood frame: a picture 2.7 wide and 2.0 high, 3.1 x 2.4 with its frame, about a third of the portrait screen's width; the owner's circle was roughly 60%.)
    /// Phone on its side: the room's first spot that is on screen in both orientations (home: the gap left of the middle window, an upright picture; loft: between the windows;
    /// cabin: between its two windows), at the biggest size it takes.
    static let defaultWidthCap: Float = 2.8
    static func defaultPlacement(room: RoomID, frame: WallFrame, shape: WallShape, file: String, crop: WallCrop = WallCrop(), source: String? = nil, sideways: Bool = false) -> WallPicture? {
        let all = spots(room)
        guard let band = all.first else { return nil }
        let sp = (sideways ? all.first { $0.inBoth && $0.shapes.contains(shape) } : nil) ?? band
        let r = sp.rect
        let w = min(maxWidth(in: r, frame: frame, shape: shape), defaultWidthCap)
        let p = WallPicture(file: file, frame: frame, shape: shape, x: sp == band ? 0 : (r.minX + r.maxX) / 2, y: (r.minY + r.maxY) / 2, width: w, crop: crop, source: source)
        return clamp(p, in: room)
    }
    /// The shape a picture takes when it first hangs: sideways in a room whose both-ways spot only takes upright pictures, upright; else landscape (a family in a row).
    static func defaultShape(room: RoomID, sideways: Bool) -> WallShape {
        guard sideways, let sp = spots(room).first(where: \.inBoth) else { return .landscape }
        return sp.shapes.contains(.landscape) ? .landscape : .portrait
    }

    // MARK: the editor's spot hint

    /// What the editor says while the picture hangs in a spot that a phone on its side does not show (`inBoth` false, e.g. above the windows).
    static let uprightOnlyHint = "Up here it only shows when the phone is upright. Between the windows it shows both ways."
    /// True while `picture` (as the room's spots hold it) is in a spot that is not on screen both ways; false in an `inBoth` spot and in a room with no spots.
    static func showsUprightOnlyHint(_ picture: WallPicture, in room: RoomID) -> Bool {
        guard let p = clamp(picture, in: room), let sp = spot(for: p, in: room) else { return false }
        // a picture that lies wholly inside an inBoth spot is in it, even where the band overlaps that spot (the cabin)
        if spots(room).contains(where: { $0.inBoth && $0.shapes.contains(p.shape) && contains($0.rect, p) }) { return false }
        return !sp.inBoth
    }
    private static func contains(_ r: Rect, _ p: WallPicture) -> Bool {
        let e: Float = 1e-3
        return p.x - p.outerWidth / 2 >= r.minX - e && p.x + p.outerWidth / 2 <= r.maxX + e && p.y - p.outerHeight / 2 >= r.minY - e && p.y + p.outerHeight / 2 <= r.maxY + e
    }

    // MARK: what is on screen

    /// A picture shows nothing when less than this share of its framed height is on screen (a sliver of a bottom edge at the top of a phone on its side reads as a bug).
    static let minVisibleShare: Float = 0.35          // (measured: the home band's default shows 20% sideways, the cabin's between-windows spot 100%)
    /// The share (0...1) of the framed picture's height that lies below `visibleTop`, the wall height at the top edge of the screen.
    static func visibleShare(_ p: WallPicture, visibleTop: Float) -> Float {
        let bottom = p.y - p.outerHeight / 2
        return min(max((visibleTop - bottom) / p.outerHeight, 0), 1)
    }
}
