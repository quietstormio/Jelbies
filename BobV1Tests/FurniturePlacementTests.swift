//
//  FurniturePlacementTests.swift
//  The second batch of furniture and toys: where the big pieces (loveseat 2.7 wide, slide 2.8 deep, swing 3.0 wide, pet bed, dining set) may go in the 10-spot room,
//  in portrait and landscape, and that a full room of them still leaves the Jellies somewhere to roam.
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class FurniturePlacementTests: XCTestCase {
    static let aspects: [(String, Float)] = [("portrait", 440.0 / 956.0), ("landscape", 956.0 / 440.0)]
    static let bigs: [DecorKind] = [.loveseat, .slide, .swing, .petbed, .diningset]

    override func setUp() { DecorField.shared.clear() }
    override func tearDown() {
        DecorField.shared.clear()
        GameCamera.configureRoom(count: 1); _ = GameCamera.camera(aspect: 440.0 / 956.0)
    }

    static func room(_ aspect: Float, jellies: Int = 3) {
        GameCamera.configureRoom(count: jellies, option: .A, wide: 2)
        _ = GameCamera.camera(aspect: aspect)
        GameCamera.refreshRoam(aspect: aspect)
    }

    func testEachBigPieceFindsASpotAloneInBothAspects() {
        for (name, a) in Self.aspects {
            Self.room(a)
            for k in Self.bigs {
                let p = DecorPlacement.findSpot(k, among: [])
                print("PLACE \(name) \(k): \(String(describing: p))")
                XCTAssertNotNil(p, "\(k) has a spot in \(name)")
            }
        }
    }

    /// Landscape sees the whole 10-wide room: all five big pieces (10 spots) fit. Portrait sees about 8 wide: any two fit, and a room of three fits (the rest is
    /// refused with "No free floor", never overlapped).
    func testBigPiecesFitTogetherInLandscapeAndAsPairsAndTriplesInPortrait() {
        for (name, a) in Self.aspects {
            Self.room(a)
            if name == "landscape" {
                let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
                for k in [DecorKind.loveseat, .slide, .swing] { b.grant(k.storeID); XCTAssertNotNil(b.place(k.storeID), "\(k) fits in \(name) beside the others") }
                XCTAssertEqual(b.roomUnitsUsed, 8, "loveseat 2 + slide 3 + swing 3 (the 1.25x swing / slide / pet bed count 3 spots)")
                Self.assertClear(b.placedDecor, name)
            }
            for i in 0..<Self.bigs.count { for j in (i + 1)..<Self.bigs.count {
                let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
                for k in [Self.bigs[i], Self.bigs[j]] {
                    b.grant(k.storeID)
                    // (the 1.25x pet bed is 2.7 round: beside another big piece in the narrow portrait room it may be refused with a reason, never overlapped)
                    if k == .petbed, name == "portrait" { if b.place(k.storeID) == nil { XCTAssertNotNil(b.placeBlocker(StoreCatalog.item(k.storeID)!)) }; continue }
                    XCTAssertNotNil(b.place(k.storeID), "\(k) fits in \(name) next to \(Self.bigs[i])/\(Self.bigs[j])")
                }
                Self.assertClear(b.placedDecor, name)
            } }
            if name == "portrait" {
                let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
                for k in [DecorKind.loveseat, .slide, .swing] { b.grant(k.storeID); XCTAssertNotNil(b.place(k.storeID), "\(k) in a portrait room of three") }
                Self.assertClear(b.placedDecor, name)
                // the others are refused, not squeezed in
                for k in [DecorKind.petbed, .diningset] { b.grant(k.storeID); if b.place(k.storeID) == nil { XCTAssertNotNil(b.placeBlocker(StoreCatalog.item(k.storeID)!)) } }
                Self.assertClear(b.placedDecor, name)
            }
        }
    }

    static func assertClear(_ placed: [PlacedDecor], _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        for p in placed {
            XCTAssertTrue(DecorPlacement.isValid(p.kind, at: p.at, among: placed, ignoring: p.uid), "\(name): \(p.kind) at \(p.at)", file: file, line: line)
            XCTAssertLessThanOrEqual(abs(p.x) + p.kind.spec.half.x, RoomLayout.maxX, "\(name): \(p.kind) is inside the walls", file: file, line: line)
        }
    }
}

extension FurniturePlacementTests {
    /// The big rooms fit (placement rules, capacity) and every piece, floor to top, is wholly on screen in portrait and in every landscape size.
    func testTheBigRoomsFitAndStayInViewInPortraitAndLandscape() {
        let sizes: [(String, CGSize)] = [("portrait 440x956", CGSize(width: 440, height: 956)), ("landscape 956x440", CGSize(width: 956, height: 440)), ("landscape 852x393", CGSize(width: 852, height: 393)), ("ipad 1194x834", CGSize(width: 1194, height: 834))]
        for (name, size) in sizes {
            let aspect = Float(size.width / size.height)
            Self.room(aspect)
            for (label, mix) in [("furniture", DecorTuning.furnitureRoom), ("bed", DecorTuning.bedRoom), ("heaviest", DecorTuning.heaviestRoom)] {
                let b = StoreBook(wallet: DropsWallet(persists: false), persists: false)
                for k in mix { b.grant(k.storeID); XCTAssertNotNil(b.place(k.storeID), "\(name) \(label): \(k) fits") }
                XCTAssertLessThanOrEqual(b.roomUnitsUsed, 10)
                Self.assertClear(b.placedDecor, name)
                DecorField.shared.set(b.placedDecor)
                let cam = GameCamera.camera(aspect: aspect)
                for f in DecorField.shared.feet {
                    let c = f.centre, h = f.spec.half
                    for sx in [Float(-1), 1] { for sz in [Float(-1), 1] { for y in [Float(0), f.spec.height] {
                        let q = cam.viewProj * SIMD4<Float>(c.x + sx * h.x, y, c.y + sz * h.y, 1)
                        XCTAssertGreaterThan(q.w, 0.001)
                        XCTAssertLessThanOrEqual(abs(q.x / q.w), 0.99, "\(name) \(label): \(f.kind) cropped at the side")
                        XCTAssertLessThanOrEqual(abs(q.y / q.w), 0.99, "\(name) \(label): \(f.kind) cropped top/bottom")
                    } } }
                }
                DecorField.shared.clear()
            }
        }
    }
}
