//
//  CampSceneryTests.swift
//  camp-yard-r1 step Y2: the Camp yard's scenery, fence layout and camera. The park's own mesh is pinned by ParkMeshGoldenTests (taken before any Camp change).
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class CampSceneryTests: XCTestCase {
    let aspects: [Float] = [0.46, 0.695, 1.44, 2.17]          // phone portrait, iPad portrait, iPad landscape, phone landscape

    override func tearDown() {
        GameCamera.endPark(count: 3); _ = GameCamera.camera(aspect: 440.0 / 956.0)
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
    }

    // MARK: the art and the mesh

    func testCampArtLoaded() {
        XCTAssertTrue(CampScenery.artLoaded, "the four park_camp_*.bin pieces must be in the bundle")
        XCTAssertGreaterThan(ParkScenery.build(theme: RoomCatalog.park.theme).vertices.count, 20000, "the foliage must be in the bundle too")
    }

    func testFenceAndTentAreTheTailOfTheCampMesh() {
        let alone = RoomMeshBuilder(); CampScenery.stamp(alone)
        let l = CampScenery.layout()
        XCTAssertEqual(alone.mesh.vertices.count, l.posts.count * 123 + l.gatePosts.count * 196 + l.rails.count * 172 + 570, "vertex counts of the post, gate post, rail and tent pieces")
        let camp = ParkScenery.build(theme: RoomCatalog.camp.theme, camp: true).vertices
        XCTAssertGreaterThan(camp.count, alone.mesh.vertices.count)
        let tail = camp.suffix(alone.mesh.vertices.count)
        XCTAssertTrue(zip(tail, alone.mesh.vertices).allSatisfy { $0.pos == $1.pos }, "the fence and the tent are stamped last")
    }

    func testPathInsideTheFenceAndTheEntranceAreGone() {
        func gravelRows(_ m: RoomMesh) -> Int { m.vertices.filter { abs($0.pos.y - 0.012) < 1e-6 && $0.pos.z > -3.6 && $0.pos.z < 5.5 && abs($0.pos.x - ParkScenery.pathX($0.pos.z)) < 0.62 + 1e-3 }.count }
        let park = ParkScenery.build(theme: RoomCatalog.park.theme), camp = ParkScenery.build(theme: RoomCatalog.camp.theme, camp: true)
        XCTAssertGreaterThan(gravelRows(park), 100, "the park has its path")
        XCTAssertEqual(gravelRows(camp), 0, "the yard's path is kept only from the gate down (z >= 5.9)")
        XCTAssertTrue(camp.vertices.contains { abs($0.pos.y - 0.012) < 1e-6 && $0.pos.z > 5.9 }, "the bit below the gate stays")
        XCTAssertLessThan(camp.vertices.count, park.vertices.count + 9000, "no hedge runs / piers: fewer vertices than the park plus the fence")
    }

    // MARK: the fence layout

    func testFenceLayout() {
        let l = CampScenery.layout()
        XCTAssertEqual(l.posts.count, 26); XCTAssertEqual(l.gatePosts.count, 2); XCTAssertEqual(l.rails.count, 27)
        // the gate: two posts at x 0.63 +- 0.95 on the front line
        let gx = l.gatePosts.map(\.x).sorted()
        XCTAssertEqual(gx[0], 0.63 - 0.95, accuracy: 1e-4); XCTAssertEqual(gx[1], 0.63 + 0.95, accuracy: 1e-4)
        XCTAssertTrue(l.gatePosts.allSatisfy { abs($0.y - 5.9) < 1e-4 })
        // every rail is a bay between two posts no further apart than the rail allows; the only opening is the gate
        let all = l.posts + l.gatePosts
        for r in l.rails {
            XCTAssertLessThanOrEqual(simd_distance(r.from, r.to), CampScenery.maxSpacing + 1e-3)
            XCTAssertTrue(all.contains { simd_distance($0, r.from) < 0.01 } && all.contains { simd_distance($0, r.to) < 0.01 })
            XCTAssertGreaterThan(CampScenery.railScale(from: r.from, to: r.to), 0.8); XCTAssertLessThanOrEqual(CampScenery.railScale(from: r.from, to: r.to), 1.0 + 1e-4)
        }
        // every post has a rail on each side (the two gate posts one), so the ring has no other gap
        for p in all {
            let n = l.rails.filter { simd_distance($0.from, p) < 0.01 || simd_distance($0.to, p) < 0.01 }.count
            XCTAssertEqual(n, l.gatePosts.contains { simd_distance($0, p) < 0.01 } ? 1 : 2, "post at \(p)")
        }
        // the gate gap is the one hole: nothing crosses it
        XCTAssertFalse(l.rails.contains { r in abs(r.from.y - 5.9) < 1e-3 && abs(r.to.y - 5.9) < 1e-3 && (r.from.x + r.to.x) / 2 > -0.32 && (r.from.x + r.to.x) / 2 < 1.58 })
        // all posts on the rectangle, and clear of the roam rect by 0.9 (a body is never on the fence)
        for p in all {
            XCTAssertTrue(abs(abs(p.x) - 4.2) < 1e-4 || abs(p.y - (-5.1)) < 1e-4 || abs(p.y - 5.9) < 1e-4, "\(p) is on the ring")
            let dx = max(0, abs(p.x) - 3.2), dz = max(p.y - 4.5, -3.6 - p.y, 0)
            XCTAssertGreaterThanOrEqual(hypotf(dx, dz), 0.9 - 1e-4, "post at \(p) vs the roam rect")
        }
        // the tent stands behind the back fence, clear of every post
        XCTAssertLessThan(CampScenery.tent.z, CampScenery.backZ)
        let tz = (CampScenery.tent.z - 0.575, CampScenery.tent.z + 0.591)          // the tent's z extent (the art: -0.575 ... +0.591)
        XCTAssertTrue(all.allSatisfy { abs($0.x - CampScenery.tent.x) > 0.813 + 0.1 || $0.y - 0.1 > tz.1 || $0.y + 0.1 < tz.0 }, "no post inside the tent")
    }

    // MARK: the camera and the floor

    private func project(_ p: SIMD3<Float>, _ cam: CameraState) -> SIMD2<Float> {
        let q = cam.viewProj * SIMD4<Float>(p, 1)
        return SIMD2(q.x / q.w * 0.5 + 0.5, 1 - (q.y / q.w * 0.5 + 0.5))          // (fractions of the screen, y from the top)
    }

    func testWholeFenceOnScreenAtEveryAspect() {
        RoomLayout.apply(RoomCatalog.camp); GameCamera.configureCamp()
        let l = CampScenery.layout()
        for a in aspects {
            GameCamera.refreshRoam(aspect: a)
            let cam = GameCamera.camera(aspect: a, gamePose: true)
            for p in l.posts + l.gatePosts {
                for y: Float in [0, 0.65] {
                    let s = project(SIMD3(p.x, y, p.y), cam)
                    XCTAssertTrue(s.x > 0.015 && s.x < 0.985 && s.y > 0.02 && s.y < 0.995, "aspect \(a): post \(p) y \(y) at \(s)")
                }
            }
            if a < 1 {          // portrait: the Home pill (iPad's is a different size; landscape is judged on the real screens): the front fence's feet stay above it
                let pill = HUDLayout.parkHomeRect(aspect: a)
                for p in l.posts where p.y > 5.8 {
                    let s = project(SIMD3(p.x, 0, p.y), cam)
                    if s.x > Float(pill.minX) && s.x < Float(pill.maxX) { XCTAssertLessThanOrEqual(s.y, Float(pill.minY) + 0.01, "aspect \(a): post \(p) is under the Home pill (\(s.y) vs \(pill.minY))") }
                }
            }
            // six bodies are not tiny: a 1.6-wide body in the middle of the floor is at least 38 points wide at the reference screen of each aspect
            let w = abs(project(SIMD3(0.8, 0.8, 1), cam).x - project(SIMD3(-0.8, 0.8, 1), cam).x)
            let ref: [Float: Float] = [0.46: 402, 0.695: 820, 1.44: 1180, 2.17: 874]
            XCTAssertGreaterThan(w * ref[a]!, 38, "aspect \(a): a body is \(w * ref[a]!) points wide")
            print("[campcam] aspect \(a): front corners \(project(SIMD3(-4.2, 0, 5.9), cam)) \(project(SIMD3(4.2, 0, 5.9), cam)) back corners \(project(SIMD3(-4.2, 0, -5.1), cam)) \(project(SIMD3(4.2, 0, -5.1), cam)) body width \(w * ref[a]!) pt")
        }
    }

    func testRoamFloorStaysInsideTheFence() {
        RoomLayout.apply(RoomCatalog.camp); GameCamera.configureCamp()
        XCTAssertEqual(GameCamera.roamRect.max.x, 3.2); XCTAssertEqual(GameCamera.roamRectWide.min.x, -3.2); XCTAssertEqual(GameCamera.parkRoamMaxZ, 4.5)
        for a in aspects {
            let f = try! XCTUnwrap(GameCamera.refreshRoam(aspect: a))
            XCTAssertGreaterThan(f.zs.count, 4, "aspect \(a)")
            for (z, h) in zip(f.zs, f.hw) { XCTAssertLessThan(h + 0.8, 4.2 - 0.1, "aspect \(a) row z \(z): half width \(h)") }
            XCTAssertGreaterThan(f.minZ - 0.8, -5.1 + 0.1, "aspect \(a): back row \(f.minZ)")
            XCTAssertLessThanOrEqual(f.minZ, -3.0 + 1e-3); XCTAssertGreaterThanOrEqual(f.minZ, -3.8 - 1e-3)
            XCTAssertLessThan(f.maxZ + 0.8, 5.9 - 0.1, "aspect \(a): front row \(f.maxZ)")
        }
    }

    func testParkFloorIsTheSameAfterACampVisit() {
        func parkFloors() -> [[Float]] {
            RoomLayout.apply(RoomCatalog.park); GameCamera.configurePark()
            return aspects.map { a in let f = GameCamera.refreshRoam(aspect: a)!; return [f.minZ, f.maxZ] + f.hw + f.zs }
        }
        GameCamera.endPark(count: 3); let fresh = parkFloors()
        RoomLayout.apply(RoomCatalog.camp); GameCamera.configureCamp(); for a in aspects { _ = GameCamera.refreshRoam(aspect: a) }
        GameCamera.endPark(count: 3)
        XCTAssertNil(GameCamera.campCap, "endPark clears the Camp caps")
        XCTAssertEqual(parkFloors(), fresh, "camp, home, park gives the park floor of a fresh launch")
        XCTAssertEqual(GameCamera.roamRect.max.x, 3.5)
    }

    // MARK: the room id

    func testCampRoomIsNeverOwnedNorSaved() {
        XCTAssertEqual(RoomCatalog.def(.camp).id, .camp)
        XCTAssertFalse(RoomCatalog.all.contains { $0.id == .camp }, "a visiting room, not in the livable list")
        let d = UserDefaults(suiteName: "CampScenery.\(UUID().uuidString)")!
        let store = StoreBook(wallet: DropsWallet(persists: false), persists: false, defaults: d)
        XCTAssertFalse(store.ownsRoom(.camp)); XCTAssertFalse(store.ownedRooms.contains(.camp))
        XCTAssertNil(StoreTuning.roomPrices[.camp])
    }
}
