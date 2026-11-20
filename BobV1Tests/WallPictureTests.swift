//
//  WallPictureTests.swift
//  The framed photo on the wall (Room/WallPicture*.swift): storage, the zone clamp of each room, old saves, no drawing outside the three home rooms, the art, the baked copy,
//  and the developer launch argument's gate.
//

import XCTest
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Metal
@testable import BobV1

@MainActor
final class WallPictureTests: XCTestCase {
    nonisolated(unsafe) static var keep: [AnyObject] = []
    private func sample(_ frame: WallFrame = .wood, _ shape: WallShape = .landscape, x: Float = 0, y: Float = 5.5, w: Float = 2) -> WallPicture {
        WallPicture(file: "pic-test.jpg", frame: frame, shape: shape, x: x, y: y, width: w, crop: WallCrop(cx: 0.4, cy: 0.6, zoom: 2), source: "Jelmiko-1.jpg")
    }
    private func suite(_ name: String) -> UserDefaults { let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name); return d }

    // MARK: storage

    func testRoundTripThroughTheSavedBook() throws {
        let d = suite("WallPic.roundtrip")
        let a = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        XCTAssertNil(a.wallPicture)
        a.hangWallPicture(sample(.gold, .portrait, x: -1.5, y: 6, w: 1.4))
        let b = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        XCTAssertEqual(b.wallPicture, sample(.gold, .portrait, x: -1.5, y: 6, w: 1.4))
        b.takeDownWallPicture()
        let c = StoreBook(wallet: DropsWallet(persists: false), persists: true, defaults: d, key: "book")
        XCTAssertNil(c.wallPicture)
        XCTAssertNil(c.saved.wallPictures, "taken down = nothing kept")
    }

    func testOldSaveLoadsAndNothingIsWrittenWhileUnused() throws {
        // a save written before the wall picture existed: no such key
        let old = #"{"counts":{"ball":1},"pages":[],"wearables":["hat"],"worn":{},"starterGiven":true,"newItems":0,"placed":[]}"#
        let s = try JSONDecoder().decode(StoreBook.Saved.self, from: Data(old.utf8))
        XCTAssertNil(s.wallPictures)
        XCTAssertEqual(s.counts["ball"], 1); XCTAssertEqual(s.wearables, ["hat"])
        let out = try JSONEncoder().encode(s)
        XCTAssertFalse(String(decoding: out, as: UTF8.self).contains("wallPictures"), "an unused feature writes nothing")
        // an unreadable value of the new key does not lose the rest
        let odd = #"{"counts":{"ball":2},"wallPictures":"junk"}"#
        let t = try JSONDecoder().decode(StoreBook.Saved.self, from: Data(odd.utf8))
        XCTAssertNil(t.wallPictures); XCTAssertEqual(t.counts["ball"], 2)
    }

    func testNewGameRemovesTheWallFolderAndTheSavedPicture() throws {
        try FileManager.default.createDirectory(at: WallPictureFiles.folder, withIntermediateDirectories: true)
        try Data([1]).write(to: WallPictureFiles.url("pic-x.jpg"))
        WallPictureFiles.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: WallPictureFiles.folder.path))
    }

    // MARK: zones and clamp

    func testZonesExistOnlyInTheThreeHomeRooms() {
        for r in RoomID.allCases {
            let home = [RoomID.home, .loft, .cabin].contains(r)
            XCTAssertEqual(WallZone.allows(r), home, "\(r)")
            XCTAssertEqual(WallZone.clamp(sample(), in: r) != nil, home, "nothing is drawn in \(r)")
        }
        XCTAssertEqual(WallZone.rect(.home), WallZone.Rect(minX: -4.6, maxX: 4.6, minY: 4.5, maxY: 7.0))
        XCTAssertEqual(WallZone.rect(.loft), WallZone.Rect(minX: -4.6, maxX: 4.6, minY: 4.75, maxY: 7.0))
        XCTAssertEqual(WallZone.rect(.cabin), WallZone.Rect(minX: -3.9, maxX: 4.6, minY: 3.75, maxY: 7.0))
        XCTAssertEqual(WallZone.spots(.home).map(\.rect.minX), [-4.6, -2.0, 1.0])
    }

    func testClampKeepsTheWholeFramedPictureInsideOneOfTheRoomsSpots() {
        for room in [RoomID.home, .loft, .cabin] {
            for f in WallFrame.allCases { for s in WallShape.allCases {
                for (x, y, w) in [(Float(0), Float(5.5), Float(2)), (-50, 40, 1), (50, -40, 30), (0, 0, 0.1), (3, 7, 5), (-1.5, 3, 3), (1.5, 2.5, 0.9)] as [(Float, Float, Float)] {
                    let q = try! XCTUnwrap(WallZone.clamp(sample(f, s, x: x, y: y, w: w), in: room))
                    let eps: Float = 1e-4
                    let inside = WallZone.spots(room).contains { sp in
                        let z = sp.rect
                        return q.x - q.outerWidth / 2 >= z.minX - eps && q.x + q.outerWidth / 2 <= z.maxX + eps
                            && q.y - q.outerHeight / 2 >= z.minY - eps && q.y + q.outerHeight / 2 <= z.maxY + eps
                    }
                    XCTAssertTrue(inside, "\(room) \(f) \(s) (\(x), \(y), \(w)) -> (\(q.x), \(q.y), \(q.width))")
                    XCTAssertGreaterThan(q.width, 0.3)
                }
            } }
        }
        // a picture that already fits does not move
        let p = sample(.wood, .landscape, x: 1, y: 5.8, w: 2)
        XCTAssertEqual(WallZone.clamp(p, in: .home), p)
    }

    func testTheOptionSpotsAreOnScreenInBothOrientations() {
        // the phone on its side shows the back wall up to about y = 5.0; a spot marked inBoth must lie below that
        for room in [RoomID.home, .loft, .cabin] {
            let s = WallZone.spots(room)
            XCTAssertFalse(s[0].inBoth, "the band above the windows is the portrait spot")
            XCTAssertGreaterThanOrEqual(s.filter(\.inBoth).count, 1, "\(room) has a spot that shows in both")
            for sp in s where sp.inBoth { XCTAssertLessThanOrEqual(sp.rect.maxY, 5.0 + 1e-4, "\(room) \(sp.name)") }
        }
        XCTAssertEqual(WallZone.spots(.home).filter(\.inBoth).count, 2, "home: the two gaps between the windows")
        // a portrait picture sent to a gap hangs in it, upright and whole
        let q = try! XCTUnwrap(WallZone.clamp(sample(.wood, .portrait, x: -1.5, y: 3, w: 3), in: .home))
        XCTAssertEqual(q.x, -1.5, accuracy: 0.2); XCTAssertLessThan(q.y, 4.2); XCTAssertGreaterThan(q.width, 0.6, "the gap is narrow: about 0.7 wide for an upright picture")
    }

    func testTheLoftsOwnArtIsHiddenOnlyWhileAPictureHangsInItsPlace() throws {
        let gap = try XCTUnwrap(WallZone.clamp(sample(.white, .portrait, x: 0, y: 3, w: 1), in: .loft))
        XCTAssertTrue(WallZone.hidesLoftArt(gap, in: .loft))
        let band = try XCTUnwrap(WallZone.clamp(sample(.white, .landscape, x: 0, y: 6, w: 2), in: .loft))
        XCTAssertFalse(WallZone.hidesLoftArt(band, in: .loft))
        XCTAssertFalse(WallZone.hidesLoftArt(gap, in: .home)); XCTAssertFalse(WallZone.hidesLoftArt(nil, in: .loft))
        // the art piece exists under that name in the bundled loft, and the room without it has fewer triangles
        let full = RoomGeometry.build(theme: RoomTheme(), def: RoomCatalog.loft)
        let less = RoomGeometry.build(theme: RoomTheme(), def: RoomCatalog.loft, hideArt: ["wallart"])
        XCTAssertEqual(full.indices.count - less.indices.count, 432 * 3)
    }

    func testDefaultPlacementIsCentredAboveTheWindowsAndReadable() {
        for room in [RoomID.home, .loft, .cabin] {
            let p = WallZone.defaultPlacement(room: room, frame: .wood, shape: .landscape, file: "f.jpg")!
            XCTAssertEqual(p.x, 0, accuracy: 1e-4)
            XCTAssertGreaterThan(p.width, 2.0, "\(room): big enough to read at the portrait zoom")
            XCTAssertEqual(WallZone.clamp(p, in: room), p)
        }
        let h = WallZone.defaultPlacement(room: .home, frame: .wood, shape: .landscape, file: "f.jpg")!
        XCTAssertEqual(h.width, 2.69, accuracy: 0.05)
    }

    // MARK: the frame art

    func testEveryFrameLoadsForEveryShapeAndMatchesItsMeasures() throws {
        for f in WallFrame.allCases { for s in WallShape.allCases {
            let p = WallPicture(file: "x", frame: f, shape: s, x: 0, y: 5, width: 1)
            let art = try XCTUnwrap(WallPictureGeometry.art(p), "frame_\(f.rawValue)_\(s.rawValue) must be bundled")
            XCTAssertGreaterThan(art.triangles, 100)
            let b = art.bounds
            let openingW = s.aspect, edge = f.edge
            XCTAssertEqual(b.hi.y, 0.5 + edge, accuracy: 0.01, "\(f) \(s) top")
            XCTAssertEqual(b.hi.x, openingW / 2 + edge, accuracy: 0.01, "\(f) \(s) side")
            XCTAssertEqual(b.lo.x, -b.hi.x, accuracy: 0.01)
            XCTAssertEqual(b.lo.z, 0, accuracy: 1e-4, "the frame's back is on the wall")
            XCTAssertEqual(b.hi.z, f.depth, accuracy: 0.01)
            // corners are not stretched: the bounds scale uniformly (the same art at twice the height is exactly twice as big)
            let m = WallPictureGeometry.build(WallPicture(file: "x", frame: f, shape: s, x: 0, y: 5, width: 2 * s.aspect), art: art)
            let ys = m.frame.vertices.map { $0.pos.y }
            XCTAssertEqual((ys.max()! - ys.min()!), 2 * (b.hi.y - b.lo.y), accuracy: 0.01)
        } }
    }

    func testMeshesAreInFrontOfTheWallInTheRightOrder() throws {
        let p = sample(.gold, .portrait, x: 0, y: 5.5, w: 1.5)
        let m = WallPictureGeometry.build(p, art: WallPictureGeometry.art(p))
        let wall = RoomLayout.minZ
        XCTAssertFalse(m.frame.indices.isEmpty); XCTAssertEqual(m.photo.indices.count, 6); XCTAssertFalse(m.shadow.indices.isEmpty)
        let zF = m.frame.vertices.map { $0.pos.z }.min()!, zP = m.photo.vertices[0].pos.z, zS = m.shadow.vertices[0].pos.z
        XCTAssertGreaterThan(zS, wall); XCTAssertGreaterThan(zF, zS); XCTAssertGreaterThan(zP, zF)
        XCTAssertLessThan(zP - wall, 0.05, "a hair in front of the wall")
        XCTAssertEqual(m.photo.vertices[0].pos.w, RoomMaterial.photo.rawValue)
        // the uv corners cover 0...1
        let uv = m.photo.vertices.map { SIMD2($0.color.x, $0.color.y) }
        XCTAssertEqual(Set(uv.map { "\($0.x),\($0.y)" }), ["0.0,0.0", "1.0,0.0", "1.0,1.0", "0.0,1.0"])
    }

    // MARK: the baked copy

    private func makeImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testBakedCopyIsCutToTheShapeAndCappedAt1024() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "wallpic-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        // a full-screen capture (1320 x 2868), landscape window zoomed 2x on the lower middle
        let big = makeImage(1320, 2868)
        let name = try XCTUnwrap(WallPictureFiles.bake(source: big, shape: .landscape, crop: WallCrop(cx: 0.5, cy: 0.75, zoom: 2), in: dir))
        let src = CGImageSourceCreateWithURL(dir.appending(path: name) as CFURL, nil)!
        let out = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(Double(out.width) / Double(out.height), 4.0 / 3.0, accuracy: 0.01)
        XCTAssertLessThanOrEqual(max(out.width, out.height), 1024)
        // never scaled up
        let small = makeImage(300, 400)
        let n2 = try XCTUnwrap(WallPictureFiles.bake(source: small, shape: .portrait, crop: WallCrop(), in: dir))
        let o2 = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(dir.appending(path: n2) as CFURL, nil)!, 0, nil)!
        XCTAssertEqual(o2.width, 300); XCTAssertEqual(o2.height, 400)
    }

    func testCropWindowStaysInsideThePhoto() {
        let size = CGSize(width: 1320, height: 2868)
        for c in [WallCrop(cx: -3, cy: -3, zoom: 1), WallCrop(cx: 9, cy: 9, zoom: 4), WallCrop(cx: 0.5, cy: 0.5, zoom: 0.2)] {
            let r = c.rect(imageSize: size, aspect: 1)
            XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertGreaterThanOrEqual(r.minY, 0)
            XCTAssertLessThanOrEqual(r.maxX, size.width + 0.01); XCTAssertLessThanOrEqual(r.maxY, size.height + 0.01)
            XCTAssertEqual(r.width / r.height, 1, accuracy: 0.001)
        }
    }

    // MARK: the developer argument

    func testDeveloperArgumentHangsAPictureOnlyWhenAsked() throws {
        XCTAssertTrue(DevArgs.enabled, "the test build is a dev build")
        let dir = FileManager.default.temporaryDirectory.appending(path: "wallpic-dev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir); WallPictureFiles.removeAll() }
        let jpg = dir.appending(path: "photo.jpg")
        let dest = CGImageDestinationCreateWithURL(jpg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, makeImage(400, 800), nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
        WallPictureFiles.removeAll()          // (the simulator's app container may hold the folder from an earlier run)
        let none = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        XCTAssertNil(WallPictureDev.apply(defaults: suite("WallPic.dev.none"), store: none), "no argument: nothing is hung")
        XCTAssertNil(none.wallPicture); XCTAssertFalse(FileManager.default.fileExists(atPath: WallPictureFiles.folder.path))
        let d = suite("WallPic.dev.on")
        d.set("pastel,square,1.5,5.8,1.6", forKey: "WallPicture"); d.set(jpg.path, forKey: "WallPictureFile")
        let store = StoreBook(wallet: DropsWallet(persists: false), persists: false)
        let p = try XCTUnwrap(WallPictureDev.apply(defaults: d, store: store))
        XCTAssertEqual(store.wallPicture, p)
        XCTAssertEqual(p.frame, .pastel); XCTAssertEqual(p.shape, .square)
        XCTAssertEqual(p.x, 1.5); XCTAssertEqual(p.y, 5.8); XCTAssertEqual(p.width, 1.6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: WallPictureFiles.url(p.file).path))
    }

    func testDeveloperArgumentIsBehindTheDevArgsGate() throws {
        let src = try String(contentsOfFile: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "BobV1/GameCare+WallPicture.swift").path, encoding: .utf8)
        let body = try XCTUnwrap(src.components(separatedBy: "enum WallPictureDev").last)
        XCTAssertTrue(body.contains("guard DevArgs.enabled"), "the launch argument must be gated like every other developer argument")
    }

    // MARK: no bare frame, the photo texture

    private func writeJPEG(_ w: Int, _ h: Int, to url: URL) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, makeImage(w, h), nil); XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testFrameShadowAndPhotoAreDrawnOnlyOnceThePhotoIsThere() async throws {
        let dev = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let lib = try XCTUnwrap(dev.makeDefaultLibrary(bundle: Bundle(for: RoomRenderer.self)))
        let room = try XCTUnwrap(RoomRenderer(device: dev, library: lib, colorFormat: .rgba8Unorm_srgb, depthFormat: .depth32Float, sampleCount: 4))
        let p = sample(.gold, .landscape, x: 0, y: 5.7, w: 2)
        let meshes = WallPictureGeometry.build(p, art: WallPictureGeometry.art(p))
        XCTAssertFalse(room.drawsWallPicture)
        room.setWallPicture(meshes, texture: nil)
        XCTAssertTrue(room.hasWallPicture); XCTAssertFalse(room.drawsWallPicture, "a frame whose photo is not here yet is not drawn: never a bare frame")
        let url = FileManager.default.temporaryDirectory.appending(path: "wallpic-tex-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        writeJPEG(512, 384, to: url)
        let loaded = await RoomRenderer.loadWallPhoto(device: dev, url: url)
        let t = try XCTUnwrap(loaded)
        XCTAssertTrue([MTLPixelFormat.rgba8Unorm_srgb, .bgra8Unorm_srgb].contains(t.pixelFormat), "colour is sRGB")
        XCTAssertGreaterThan(t.mipmapLevelCount, 1, "mipmapped")
        let missing = await RoomRenderer.loadWallPhoto(device: dev, url: url.appendingPathExtension("gone"))
        XCTAssertNil(missing, "a missing file gives no texture (the frame is then not drawn)")
        room.setWallPhotoTexture(t)
        XCTAssertTrue(room.drawsWallPicture)
        room.setWallPicture(nil, texture: nil)
        XCTAssertFalse(room.hasWallPicture); XCTAssertFalse(room.drawsWallPicture)
    }

    // MARK: the editor's steps (no game needed)

    func testFirstHangStartsInTheRightSpotForTheWayThePhoneIsHeld() throws {
        let url = URL(fileURLWithPath: "/tmp/x.jpg"), size = CGSize(width: 1320, height: 2868)
        for room in [RoomID.home, .loft, .cabin] {
            let up = try XCTUnwrap(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [.wood], room: room, sideways: false))
            let band = try XCTUnwrap(WallZone.spots(room).first)
            XCTAssertEqual(up.draft.shape, .landscape)
            XCTAssertEqual(WallZone.spot(for: up.draft, in: room), band, "\(room): upright = the band above the windows (the circled spot)")
            let side = try XCTUnwrap(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [.wood], room: room, sideways: true))
            let both = try XCTUnwrap(WallZone.spots(room).first { $0.inBoth })
            let r = both.rect, d = side.draft, eps: Float = 1e-3
            XCTAssertTrue(d.x - d.outerWidth / 2 >= r.minX - eps && d.x + d.outerWidth / 2 <= r.maxX + eps && d.y - d.outerHeight / 2 >= r.minY - eps && d.y + d.outerHeight / 2 <= r.maxY + eps,
                          "\(room): sideways = the whole picture inside the spot that is on screen both ways")
            XCTAssertTrue(both.shapes.contains(side.draft.shape))
            XCTAssertEqual(WallZone.clamp(side.draft, in: room), side.draft, "it already fits its spot")
        }
        XCTAssertEqual(try XCTUnwrap(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [.gold], room: .home, sideways: true)).draft.shape, .portrait, "the home gaps take upright pictures")
        XCTAssertNil(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [], room: .home, sideways: false), "no frame owned: no editor")
        XCTAssertNil(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [.wood], room: .cafe, sideways: false), "no zone in the café")
    }

    func testEditingMovesSizesReshapesAndKeepsInsideTheSpots() throws {
        let url = URL(fileURLWithPath: "/tmp/x.jpg"), size = CGSize(width: 1320, height: 2868)
        let s = try XCTUnwrap(WallEditSession.make(photo: url, imageSize: size, existing: nil, owned: [.wood, .gold], room: .home, sideways: false))
        s.move(to: SIMD2(-1.5, 3.0))                 // dragged down to the left gap with a wide picture: the gap does not take it, so it stays in the band
        XCTAssertEqual(WallZone.spot(for: s.draft, in: .home), WallZone.spots(.home)[0])
        s.setShape(.portrait, room: .home)           // upright: now the gap takes it
        s.move(to: SIMD2(-1.5, 3.0)); s.settle(.home)
        XCTAssertEqual(WallZone.spot(for: s.draft, in: .home), WallZone.spots(.home)[1])
        XCTAssertLessThan(s.draft.width, 1.0); XCTAssertEqual(s.draft.shape, .portrait)
        s.setWidth(50, room: .home)
        XCTAssertLessThanOrEqual(s.draft.width, WallZone.maxWidth(in: WallZone.spots(.home)[1].rect, frame: .wood, shape: .portrait) + 1e-4, "never bigger than its spot")
        s.setWidth(0.01, room: .home)
        XCTAssertGreaterThanOrEqual(s.draft.width, 0.7 - 1e-4)
        XCTAssertTrue(s.setFrame(.gold, room: .home, owned: [.wood, .gold])); XCTAssertEqual(s.draft.frame, .gold)
        XCTAssertFalse(s.setFrame(.pastel, room: .home, owned: [.wood, .gold]), "an unowned frame cannot be selected"); XCTAssertEqual(s.draft.frame, .gold)
        // the photo inside the frame: pan and zoom stay inside the photo
        s.setZoom(3); XCTAssertEqual(s.draft.crop.zoom, 3)
        s.pan(shareX: -5, shareY: 5)
        let r = s.draft.crop.rect(imageSize: size, aspect: s.draft.shape.aspect)
        XCTAssertGreaterThanOrEqual(r.minX, 0); XCTAssertLessThanOrEqual(r.maxX, size.width + 0.01); XCTAssertGreaterThanOrEqual(r.minY, 0); XCTAssertLessThanOrEqual(r.maxY, size.height + 0.01)
        s.setZoom(99); XCTAssertEqual(s.draft.crop.zoom, 6); s.setZoom(0); XCTAssertEqual(s.draft.crop.zoom, 1)
        let w = s.uvWindow
        XCTAssertTrue(w.x >= 0 && w.y >= 0 && w.z <= 1.0001 && w.w <= 1.0001 && w.z > w.x && w.w > w.y)
    }

    func testDoneCutsTheCopyAndCancelLeavesTheSavedPictureAlone() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "wallpic-done-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appending(path: "album.jpg"); writeJPEG(600, 1200, to: photo)
        let s = try XCTUnwrap(WallEditSession.make(photo: photo, imageSize: CGSize(width: 600, height: 1200), existing: nil, owned: [.pastel], room: .loft, sideways: false))
        let p = try XCTUnwrap(s.finalPicture(room: .loft, dir: dir))
        XCTAssertFalse(p.file.isEmpty); XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: p.file).path))
        XCTAssertEqual(p.source, "album.jpg"); XCTAssertEqual(WallZone.clamp(p, in: .loft), p)
        // the saved picture is the book's, only Done changes it
        let book = StoreBook(wallet: DropsWallet(persists: false), persists: false); Self.keep.append(book)
        XCTAssertNil(book.wallPicture)                       // Cancel = nothing saved
        book.hangWallPicture(p); XCTAssertEqual(book.wallPicture, p)
        // editing the picture that hangs, album photo gone: the copy stays, the shape cannot change, no new copy is cut
        let again = try XCTUnwrap(WallEditSession.make(photo: nil, imageSize: nil, existing: p, owned: [.pastel], room: .loft, sideways: false))
        XCTAssertFalse(again.canCrop); XCTAssertFalse(again.canReshape)
        again.setShape(.portrait, room: .loft); XCTAssertEqual(again.draft.shape, p.shape, "the game's own copy has the old shape")
        again.move(to: SIMD2(1, 6)); again.settle(.loft)
        let q = try XCTUnwrap(again.finalPicture(room: .loft, dir: dir))
        XCTAssertEqual(q.file, p.file, "no new copy is cut without the album photo")
    }

    // MARK: Shop and Bag

    func testPictureFramesAreFourCoinPricedGoodsInTheRoomsTab() throws {
        let frames = StoreCatalog.items(.wallFrame)
        XCTAssertEqual(frames.map(\.id), ["frame-wood", "frame-white", "frame-pastel", "frame-gold"])
        XCTAssertEqual(frames.map(\.price), [45, 45, 70, 120], "the two plainest at the lowest step, Pastel one up, Gold at the top")
        XCTAssertTrue(frames.allSatisfy { $0.price > 0 && $0.unique && $0.wallFrame != nil })
        XCTAssertEqual(frames.compactMap(\.wallFrame), WallFrame.allCases)
        XCTAssertEqual(ShopTab.rooms.items.filter { $0.kind == .wallFrame }.count, 4, "their own group in the Rooms tab")
        XCTAssertFalse(ShopTab.shown.contains(.furniture)); XCTAssertEqual(ShopTab.shown.count, Set(ShopTab.shown).count, "no new tab")
        let wallet = DropsWallet(persists: false); wallet.add(100, silent: true)
        let book = StoreBook(wallet: wallet, persists: false); Self.keep.append(book)
        XCTAssertTrue(book.ownedWallFrames.isEmpty)
        XCTAssertEqual(book.buy("frame-gold"), .notEnough)
        XCTAssertEqual(book.buy("frame-wood"), .bought); XCTAssertEqual(wallet.count, 55)
        XCTAssertEqual(book.buy("frame-wood"), .alreadyOwned)
        XCTAssertEqual(book.ownedWallFrames, [.wood]); XCTAssertTrue(book.ownsFrame(.wood)); XCTAssertFalse(book.ownsFrame(.gold))
        XCTAssertEqual(book.sellState(try XCTUnwrap(StoreCatalog.item("frame-wood"))), .no, "a frame is kept")
    }

    // MARK: the camera

    func testTheNormalCameraIsUntouchedWhenTheEditorIsClosed() {
        GameCamera.configureRoom(count: 1)
        defer { GameCamera.wallEditBlend = 0; GameCamera.configureRoom(count: 1) }
        for aspect in [Float(0.46), 0.56, 0.75, 1.33, 2.17] {
            GameCamera.wallEditBlend = 0
            let c = GameCamera.camera(aspect: aspect)
            let expected = M4.lookAt(eye: GameCamera.eye, at: GameCamera.target, up: SIMD3(0, 1, 0))
            XCTAssertTrue(simd_equal(c.view, expected), "blend 0: the camera is exactly the room pose (aspect \(aspect))")
            XCTAssertEqual(c.pos, GameCamera.eye)
            // a ray / screen point round trip on the wall works at this aspect
            let size = CGSize(width: 1000, height: CGFloat(1000 / aspect))
            let sp = GameCamera.screenPoint(wall: SIMD2(1.5, 5.5), size: size)
            let back = sp.flatMap { GameCamera.wallPoint(screen: $0, size: size) }
            XCTAssertEqual(back?.x ?? 99, 1.5, accuracy: 0.01); XCTAssertEqual(back?.y ?? 99, 5.5, accuracy: 0.01)
        }
        // the editor's blend rises the view on a phone on its side only
        GameCamera.wallEditBlend = 1
        let base = { () -> Float in GameCamera.wallEditBlend = 0; return GameCamera.camera(aspect: 2.17).pos.y }()
        GameCamera.wallEditBlend = 1
        XCTAssertEqual(GameCamera.camera(aspect: 2.17).pos.y - base, GameCamera.wallEditLift, accuracy: 1e-3)
        GameCamera.wallEditBlend = 0
        let basePortrait = GameCamera.camera(aspect: 0.46).pos
        GameCamera.wallEditBlend = 1
        XCTAssertEqual(GameCamera.camera(aspect: 0.46).pos, basePortrait, "the upright view already shows the band: no lift")
    }

    func testWhatIsOnScreenOnAPhoneOnItsSideAndTheSliverRule() throws {
        GameCamera.configureRoom(count: 3)
        defer { GameCamera.wallEditBlend = 0; GameCamera.configureRoom(count: 1) }
        let top = try XCTUnwrap(GameCamera.wallVisibleTop(aspect: 2.17)), topP = try XCTUnwrap(GameCamera.wallVisibleTop(aspect: 0.46))
        XCTAssertTrue((4.9...5.3).contains(top), "a phone on its side shows the wall up to about y 5.0 (measured \(top))")
        XCTAssertGreaterThan(topP, 7.5, "upright shows the whole band")
        let home = try XCTUnwrap(WallZone.defaultPlacement(room: .home, frame: .wood, shape: .landscape, file: "f"))
        XCTAssertLessThan(WallZone.visibleShare(home, visibleTop: top), WallZone.minVisibleShare, "the circled spot is mostly off the top: not drawn sideways")
        XCTAssertEqual(WallZone.visibleShare(home, visibleTop: topP), 1, accuracy: 1e-4)
        for room in [RoomID.home, .loft, .cabin] {          // what a first hang with the phone on its side puts on screen: all of it
            let shape = WallZone.defaultShape(room: room, sideways: true)
            let p = try XCTUnwrap(WallZone.defaultPlacement(room: room, frame: .wood, shape: shape, file: "f", sideways: true))
            XCTAssertGreaterThan(WallZone.visibleShare(p, visibleTop: top), 0.95, "\(room) sideways default")
            XCTAssertLessThan(p.y + p.outerHeight / 2, top - 0.1, "\(room): a little clear of the screen's top edge (top \(top))")
        }
    }
}
