//
//  GameCare+WallEdit.swift
//  The wall picture editor: a kind of arrange mode (it sets `arranging`, so the HUD is away, the Jelmiko's touch is off and a room move waits) on the live room. The player drags the
//  picture, sizes it, picks upright / square / wide, slides the photo inside the frame, picks a frame they own and Done saves. The camera rises while it is open on a phone on its side
//  (GameCamera+Wall.swift) and eases back when it closes. The Jelmiko keep living behind it. It never opens over a meal, bath, trip, competition, play mode or the close-up.
//

import Foundation
import ImageIO
import UIKit
import simd

/// One open editor: the picture as the player has it now (`draft`), what it was (`original`, nil on a first hang), and the album photo its crop is cut from.
@MainActor
@Observable
final class WallEditSession {
    var draft: WallPicture
    let original: WallPicture?
    /// The album photo the crop window is cut from (nil: the album photo is gone, so only the game's own copy is left and the crop cannot change).
    var sourceURL: URL?
    var imageSize: CGSize
    /// true: a drag slides the photo inside the frame and a pinch zooms it; false: a drag moves the picture and a pinch sizes it.
    var photoMode = false
    /// The crop or the photo changed: Done cuts a new copy.
    var cropDirty = false
    init(draft: WallPicture, original: WallPicture?, sourceURL: URL?, imageSize: CGSize) {
        self.draft = draft; self.original = original; self.sourceURL = sourceURL; self.imageSize = imageSize
    }
    nonisolated deinit {}

    // MARK: the editing steps (pure: the room and the owned frames come in as arguments, so they are tested without a game)

    /// The editor for a first hang or a new photo (`photo`), or for the picture on the wall (`photo` nil). Nil when there is no frame / photo to start from.
    static func make(photo: URL?, imageSize: CGSize?, existing: WallPicture?, owned: [WallFrame], room: RoomID, sideways: Bool) -> WallEditSession? {
        guard !owned.isEmpty, WallZone.allows(room) else { return nil }
        if let photo {
            guard let size = imageSize else { return nil }
            var draft: WallPicture
            if var e = existing {
                e.file = ""; e.crop = WallCrop(); e.source = photo.lastPathComponent
                if !owned.contains(e.frame) { e.frame = owned[0] }
                draft = e
            } else {
                let shape = WallZone.defaultShape(room: room, sideways: sideways)
                guard let d = WallZone.defaultPlacement(room: room, frame: owned[0], shape: shape, file: "", source: photo.lastPathComponent, sideways: sideways) else { return nil }
                draft = d
            }
            let s = WallEditSession(draft: draft, original: existing, sourceURL: photo, imageSize: size)
            s.cropDirty = true
            return s
        }
        guard let e = existing else { return nil }
        var url: URL?, size = CGSize.zero
        if let name = e.source, let sz = imageSize { url = PhotoAlbum.folder.appending(path: name); size = sz }
        return WallEditSession(draft: e, original: existing, sourceURL: url, imageSize: size)
    }

    func move(to wall: SIMD2<Float>) { draft.x = wall.x; draft.y = wall.y }
    /// Sets the picture's width (wall units, at most what its spot takes).
    func setWidth(_ w: Float, room: RoomID) {
        let cap = WallZone.spot(for: draft, in: room).map { WallZone.maxWidth(in: $0.rect, frame: draft.frame, shape: draft.shape) } ?? w
        draft.width = min(max(w, WallZone.minWidth), cap)
    }
    /// A new shape keeps the picture's height and centre; a spot that does not take the shape moves it to the nearest that does.
    func setShape(_ shape: WallShape, room: RoomID) {
        guard draft.shape != shape, canReshape else { return }
        let h = draft.height
        draft.shape = shape
        draft.width = h * shape.aspect
        settle(room)
        cropDirty = true
    }
    @discardableResult
    func setFrame(_ f: WallFrame, room: RoomID, owned: [WallFrame]) -> Bool {
        guard owned.contains(f) else { return false }
        draft.frame = f
        settle(room)
        return true
    }
    /// The draft as the room's spot holds it.
    func settle(_ room: RoomID) {
        if let c = WallZone.clamp(draft, in: room) { draft.x = c.x; draft.y = c.y; draft.width = c.width }
    }
    /// Slides the photo inside the frame by a finger movement given as a share of the picture's on-screen size.
    func pan(shareX: Float, shareY: Float) {
        guard canCrop else { return }
        let r = draft.crop.rect(imageSize: imageSize, aspect: draft.shape.aspect)
        draft.crop.cx = Float((r.midX - CGFloat(shareX) * r.width) / imageSize.width)
        draft.crop.cy = Float((r.midY - CGFloat(shareY) * r.height) / imageSize.height)
        cropDirty = true
    }
    func setZoom(_ z: Float) {
        guard canCrop else { return }
        draft.crop.zoom = min(max(z, 1), 6); cropDirty = true
    }
    func changePhoto(_ url: URL, size: CGSize) {
        sourceURL = url; imageSize = size
        draft.crop = WallCrop(); draft.source = url.lastPathComponent; cropDirty = true
    }
    /// What Done hangs: the draft clamped into the room, with a new copy of the photo cut when the crop or the photo changed (`dir` = where the copy goes). Nil when the photo cannot be cut.
    func finalPicture(room: RoomID, dir: URL = WallPictureFiles.folder) -> WallPicture? {
        var p = WallZone.clamp(draft, in: room) ?? draft
        if cropDirty || p.file.isEmpty {
            guard let url = sourceURL, let img = WallPictureFiles.image(at: url), let name = WallPictureFiles.bake(source: img, shape: p.shape, crop: p.crop, in: dir) else {
                return p.file.isEmpty ? nil : p
            }
            p.file = name; p.source = url.lastPathComponent
        }
        return p
    }

    var canCrop: Bool { sourceURL != nil && imageSize.width > 1 }
    /// A new shape needs the album photo to cut it from (the game's own copy has the old shape); a picture not cut yet can always change shape.
    var canReshape: Bool { canCrop || draft.file.isEmpty }
    /// The file the editor shows: the album photo while there is one (the crop window slides over it), else the game's own copy.
    var textureURL: URL { sourceURL ?? WallPictureFiles.url(draft.file) }
    /// The window of that file shown in the frame (u0, v0, u1, v1).
    var uvWindow: SIMD4<Float> {
        guard canCrop else { return SIMD4(0, 0, 1, 1) }
        let r = draft.crop.rect(imageSize: imageSize, aspect: draft.shape.aspect)
        return SIMD4(Float(r.minX / imageSize.width), Float(r.minY / imageSize.height), Float(r.maxX / imageSize.width), Float(r.maxY / imageSize.height))
    }
}

/// What the album's big viewer needs to offer the wall (nil: no wall button, as in the main menu's album).
struct WallHangContext {
    var owns: Bool
    var hang: (URL) -> Void
    var getFrame: () -> Void
}

extension GameCare {
    // MARK: can it open?

    /// Why the editor cannot open now (nil = it can): never over a meal, a bath, a trip or competition, play mode, the close-up, arranging or a room move.
    func wallEditBlocker() -> String? {
        if wallEdit != nil { return "The wall picture is open already" }
        if tripActive || raceBusy { return "Hang pictures when you are home" }
        if bath.active { return "Hang pictures after the bath" }
        if focus.isActive { return "Close the close-up first" }
        if trayOut || dining.phase != .absent || groupActive { return "Hang pictures after the meal" }
        if play.active { return "Finish playing first" }
        if arranging { return "Finish arranging first" }
        if roomSwitch.active { return "Wait for the move to finish" }
        if !WallZone.allows(roomID) { return "Pictures hang in the living room, the loft and the cabin" }
        return nil
    }

    // MARK: open / close

    /// Opens the editor. `photo` = an album photo to hang (a first hang, or a new photo for the picture on the wall); nil = edit the picture that is on the wall. Returns why not, or nil.
    @discardableResult
    func beginWallEdit(photo: URL?) -> String? {
        if let why = wallEditBlocker() { return why }
        let owned = store.ownedWallFrames
        guard !owned.isEmpty else { return "Get a frame in the Shop first" }
        let existing = store.wallPicture
        var size: CGSize?
        if let photo { size = Self.pixelSize(of: photo); if size == nil { return "That photo could not be opened" } }
        else if let name = existing?.source { size = Self.pixelSize(of: PhotoAlbum.folder.appending(path: name)) ?? .zero }
        guard let s = WallEditSession.make(photo: photo, imageSize: size, existing: existing, owned: owned, room: roomID, sideways: GameCamera.aspect > 1.2) else {
            return existing == nil && photo == nil ? "There is no picture on the wall yet" : "Pictures hang in the living room, the loft and the cabin"
        }
        if photo == nil, s.imageSize == .zero { s.sourceURL = nil }          // the album photo is gone: only the game's own copy is left
        wallEdit = s
        arranging = true; arrangingUID = nil
        AudioHub.shared.play(.placeItem)
        return nil
    }

    /// Done (`save`) or Cancel. Done cuts the game's own copy of the photo when the crop or the photo changed, then hangs the picture (clamped into the room's spots).
    func finishWallEdit(save: Bool) {
        guard let s = wallEdit else { return }
        if save {
            guard let p = s.finalPicture(room: roomID) else {
                GameMessageCenter.shared.post("That photo could not be hung", identifier: "wall-edit-failed")
                return
            }
            store.hangWallPicture(p)
            // on a phone on its side the circled spot is off the top of the screen: say where the picture is, so a missing picture does not look like a mistake
            if let top = GameCamera.wallVisibleTop(aspect: GameCamera.aspect), WallZone.visibleShare(p, visibleTop: top) < WallZone.minVisibleShare {
                GameMessageCenter.shared.post("Hung! Turn the phone upright to see it", icon: "photo.artframe", identifier: "wall-edit-upright")
            }
        }
        endWallEdit()
    }

    /// Takes the picture down (the saved entry and the game's copy of the photo go) and closes the editor.
    func takeDownWallPicture() {
        store.takeDownWallPicture()
        endWallEdit()
    }

    private func endWallEdit() {
        wallEdit = nil
        arranging = false; arrangingUID = nil
    }

    /// Once per fixed step (first in `tickDecor`): eases the camera's editor blend toward 1 while the editor is open and back to 0 after. 0 changes nothing anywhere.
    func tickWallEdit(dt: Float) {
        let target: Float = wallEdit != nil ? 1 : 0
        guard wallEditT != target else { return }
        let step = dt / 0.45
        wallEditT = target > wallEditT ? min(wallEditT + step, 1) : max(wallEditT - step, 0)
        GameCamera.wallEditBlend = wallEditT * wallEditT * (3 - 2 * wallEditT)
    }

    // MARK: editing

    func wallEditMove(to wall: SIMD2<Float>) { wallEdit?.move(to: wall) }
    func wallEditSetWidth(_ w: Float) { wallEdit?.setWidth(w, room: roomID) }
    func wallEditSetShape(_ shape: WallShape) { wallEdit?.setShape(shape, room: roomID) }
    @discardableResult
    func wallEditSetFrame(_ f: WallFrame) -> Bool { wallEdit?.setFrame(f, room: roomID, owned: store.ownedWallFrames) ?? false }
    func wallEditPan(shareX: Float, shareY: Float) { wallEdit?.pan(shareX: shareX, shareY: shareY) }
    func wallEditSetZoom(_ z: Float) { wallEdit?.setZoom(z) }
    /// Change photo: a new album photo for the picture being edited (the crop starts again).
    func wallEditChangePhoto(_ url: URL) { if let sz = Self.pixelSize(of: url) { wallEdit?.changePhoto(url, size: sz) } }

    // MARK: entry points

    /// The album's big viewer gets "Hang on wall" (or "Get a frame" with none owned). `close` closes the album it is in.
    func wallHangContext(close: @escaping () -> Void) -> WallHangContext {
        WallHangContext(owns: !store.ownedWallFrames.isEmpty,
                        hang: { [weak self] url in
                            close()
                            if PhotoMode.shared.active { PhotoMode.shared.close() }
                            self?.hangFromAlbum(url)
                        },
                        getFrame: { [weak self] in
                            close()
                            if PhotoMode.shared.active { PhotoMode.shared.close() }
                            self?.wallShopRequest = true
                        })
    }
    func hangFromAlbum(_ url: URL) {
        if wallEdit != nil { wallEditChangePhoto(url); return }
        if let why = beginWallEdit(photo: url) { GameMessageCenter.shared.post(why, identifier: "wall-edit-refused") }
    }

    static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}
