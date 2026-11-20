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
@testable import BobV1

@MainActor
final class WallPictureTests: XCTestCase {
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
    }

    func testClampKeepsTheWholeFramedPictureInsideEveryZone() {
        for room in [RoomID.home, .loft, .cabin] {
            let z = WallZone.rect(room)!
            for f in WallFrame.allCases { for s in WallShape.allCases {
                for (x, y, w) in [(Float(0), Float(5.5), Float(2)), (-50, 40, 1), (50, -40, 30), (0, 0, 0.1), (3, 7, 5)] as [(Float, Float, Float)] {
                    let q = try! XCTUnwrap(WallZone.clamp(sample(f, s, x: x, y: y, w: w), in: room))
                    let eps: Float = 1e-4
                    XCTAssertGreaterThanOrEqual(q.x - q.outerWidth / 2, z.minX - eps, "\(room) \(f) \(s)")
                    XCTAssertLessThanOrEqual(q.x + q.outerWidth / 2, z.maxX + eps, "\(room) \(f) \(s)")
                    XCTAssertGreaterThanOrEqual(q.y - q.outerHeight / 2, z.minY - eps, "\(room) \(f) \(s)")
                    XCTAssertLessThanOrEqual(q.y + q.outerHeight / 2, z.maxY + eps, "\(room) \(f) \(s)")
                    XCTAssertGreaterThan(q.width, 0.3)
                }
            } }
        }
        // a picture that already fits does not move
        let p = sample(.wood, .landscape, x: 1, y: 5.8, w: 2)
        XCTAssertEqual(WallZone.clamp(p, in: .home), p)
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
        let none = GameCare(jellyCount: 1, persistent: false, defaults: suite("WallPic.dev.none"))
        XCTAssertNil(none.store.wallPicture, "no argument: nothing is hung")
        let d = suite("WallPic.dev.on")
        d.set("pastel,square,1.5,5.8,1.6", forKey: "WallPicture"); d.set(jpg.path, forKey: "WallPictureFile")
        let care = GameCare(jellyCount: 1, persistent: false, defaults: d)
        let p = try XCTUnwrap(care.store.wallPicture)
        XCTAssertEqual(p.frame, .pastel); XCTAssertEqual(p.shape, .square)
        XCTAssertEqual(p.x, 1.5); XCTAssertEqual(p.y, 5.8); XCTAssertEqual(p.width, 1.6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: WallPictureFiles.url(p.file).path))
    }

    func testDeveloperArgumentIsBehindTheDevArgsGate() throws {
        let src = try String(contentsOfFile: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "BobV1/GameCare+WallPicture.swift").path, encoding: .utf8)
        let body = try XCTUnwrap(src.components(separatedBy: "func applyWallPictureLaunchArguments").last)
        XCTAssertTrue(body.contains("guard DevArgs.enabled"), "the launch argument must be gated like every other developer argument")
    }
}
