//
//  RoomDefTests.swift
//  Per-room definitions (Room/RoomDef.swift): the home room must stay exactly as it was, every room keeps the front floor free.
//

import XCTest
import Metal
import simd
@testable import BobV1

@MainActor
final class RoomDefTests: XCTestCase {
    override func tearDown() { RoomLayout.apply(RoomCatalog.home); GameCamera.configureRoom(count: 1) }

    static func fnv(_ mesh: RoomMesh) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func feed(_ p: UnsafeRawBufferPointer) { for b in p { h ^= UInt64(b); h = h &* 0x100000001b3 } }
        mesh.vertices.withUnsafeBytes(feed)
        mesh.indices.withUnsafeBytes(feed)
        return h
    }

    func testHomeGeometryHash() {
        let m = RoomGeometry.build(theme: RoomTheme())
        // measured on the untouched round-1022 code (before the per-room refactor)
        XCTAssertEqual(m.vertices.count, 23544)
        XCTAssertEqual(m.indices.count, 121314)
        XCTAssertEqual(Self.fnv(m), 10948828446133751937, "home geometry must stay bit-identical")
    }

    func testHomeDefMatchesOldConstants() {
        let h = RoomCatalog.home
        XCTAssertEqual(h.couch, RoomLayout.RoundedBox(centre: SIMD3(0, 0.5, -4.2), halfExtents: SIMD3(1.8, 0.5, 0.65), radius: 0.2))
        XCTAssertEqual(h.cylinders, [.init(centre: SIMD2(3.7, -4.0), radius: 0.5, height: 0.65), .init(centre: SIMD2(-4.2, -4.2), radius: 0.4, height: 0.5)])
        XCTAssertEqual(h.lampTable, h.cylinders[0])
        XCTAssertEqual(h.lamp, SIMD3(3.7, 1.0, -4.0))
        XCTAssertEqual(h.windows, RoomWindows(xs: [-3, 0, 3], halfW: 0.85, y0: 1.5, y1: 4.3, proceduralFrames: true))
        XCTAssertEqual([h.floor.rawValue, h.wall.rawValue, h.rug.rawValue], [0, 0, 0])
        XCTAssertNil(h.art)
        XCTAssertEqual(h.theme, RoomTheme())
        XCTAssertEqual(RoomLayout.current.id, .home)
        XCTAssertEqual(DayLight.day.lampPos.x, 3.7); XCTAssertEqual(DayLight.day.lampPos.z, -4.0)
        XCTAssertEqual(RoomTheme().swatches, RoomTheme(tint: RoomTheme.defaultTint, chromaScale: 1, lightnessShift: 0).swatches)
    }

    func testEveryRoomKeepsTheFrontFloor() {
        let spots = JellyRoster.spawnSpots(count: 3) + [GameCamera.callSpot, GameCamera.foodBowlSpot, GameCamera.waterBowlSpot]
        for d in RoomCatalog.all {
            RoomLayout.apply(d)
            for b in d.allBoxes {
                XCTAssertLessThanOrEqual(b.centre.z + b.halfExtents.z, -3.3, "\(d.id) box front edge")
                XCTAssertGreaterThanOrEqual(b.centre.x - b.halfExtents.x, RoomLayout.minX); XCTAssertLessThanOrEqual(b.centre.x + b.halfExtents.x, RoomLayout.maxX)
                XCTAssertGreaterThanOrEqual(b.centre.z - b.halfExtents.z, RoomLayout.minZ)
            }
            for c in d.cylinders {
                XCTAssertLessThanOrEqual(c.centre.y + c.radius, -3.3, "\(d.id) cylinder front edge")
                XCTAssertGreaterThanOrEqual(c.centre.x - c.radius, RoomLayout.minX); XCTAssertLessThanOrEqual(c.centre.x + c.radius, RoomLayout.maxX)
                XCTAssertGreaterThanOrEqual(c.centre.y - c.radius, RoomLayout.minZ)
                XCTAssertGreaterThan(simd_length(c.centre - RoomLayout.rugCentre) - c.radius - RoomLayout.rugRadius, -0.0, "\(d.id) cylinder off the rug")
            }
            // the rug is clear of the furniture
            for k in 0..<72 {
                let a = Float(k) / 72 * 2 * .pi, p = RoomLayout.rugCentre + SIMD2(cosf(a), sinf(a)) * RoomLayout.rugRadius
                XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(p), 0.3, "\(d.id) rug vs sofa")
                for c in d.cylinders { XCTAssertGreaterThan(simd_distance(p, c.centre) - c.radius, 0.3, "\(d.id) rug vs cylinder") }
            }
            for p in spots {
                XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(p), 0.9, "\(d.id) spot \(p)")
                for c in d.cylinders { XCTAssertGreaterThan(simd_distance(p, c.centre) - c.radius, 0.9, "\(d.id) spot \(p)") }
            }
            for sgn in [Float(-1), 1] {            // the Antics peek spots
                let p = SIMD2(sgn * (d.couch.halfExtents.x + 0.95), RoomLayout.minZ + 2.7)
                XCTAssertGreaterThan(RoomLayout.sofaDistanceXZ(p), 0.7, "\(d.id) peek spot")
                for c in d.cylinders { XCTAssertGreaterThan(simd_distance(p, c.centre) - c.radius, 0.3, "\(d.id) peek vs cylinder") }
            }
            // a body pushed into the furniture comes out
            let R: Float = 0.8
            for start in [SIMD3<Float>(0, 0.6, -3.5), SIMD3<Float>(-9, 0.6, 0)] + d.cylinders.map({ SIMD3<Float>($0.centre.x, 0.3, $0.centre.y) }) {
                let q = RoomLayout.resolve(position: start, radius: R)
                XCTAssertGreaterThanOrEqual(RoomLayout.sofaDistanceXZ(SIMD2(q.x, q.z)), R - 1e-2, "\(d.id)")
                for c in d.cylinders { XCTAssertGreaterThanOrEqual(simd_length(SIMD2(q.x, q.z) - c.centre), c.radius + R - 1e-2, "\(d.id)") }
            }
        }
    }

    func testRoamFloorPerRoom() throws {
        GameCamera.configureRoom(count: 3, option: .A, wide: 2)
        for a in [Float(603.0 / 1311.0), Float(1311.0 / 603.0)] {
            RoomLayout.apply(RoomCatalog.home)
            let homeArea = try XCTUnwrap(GameCamera.refreshRoam(aspect: a)).area
            for d in RoomCatalog.all {
                RoomLayout.apply(d)
                let f = try XCTUnwrap(GameCamera.refreshRoam(aspect: a), "\(d.id)")
                XCTAssertGreaterThanOrEqual(f.area, 0.85 * homeArea, "\(d.id) roam area at aspect \(a)")
                for (i, z) in f.zs.enumerated() {
                    for r in f.free[i] {
                        for x in [r.lowerBound, (r.lowerBound + r.upperBound) / 2, r.upperBound] {
                            let p = SIMD2(x, z)
                            XCTAssertGreaterThanOrEqual(RoomLayout.sofaDistanceXZ(p), 0.78 - 0.05, "\(d.id) free span vs sofa")
                            for c in d.cylinders { XCTAssertGreaterThanOrEqual(simd_distance(p, c.centre) - c.radius, 0.78 - 0.05, "\(d.id) free span vs cylinder") }
                        }
                    }
                }
                for k in 0..<200 {
                    let u = Float(k)
                    func fr(_ v: Float) -> Float { v - floorf(v) }
                    let p = f.sampleArea(fr(u * 0.618), fr(u * 0.414 + 0.1), 0)
                    XCTAssertTrue(f.contains(p), "\(d.id) sample \(p)")
                }
            }
        }
    }

    func testWindowsFollowTheRoom() {
        for d in RoomCatalog.all {
            RoomLayout.apply(d)
            XCTAssertEqual(RoomGeometry.windowXs, d.windows.xs)
            for x in d.windows.xs { XCTAssertTrue(DayWindow.contains(x: x, y: (d.windows.y0 + d.windows.y1) / 2), "\(d.id) window at \(x)") }
            if d.id != .home { XCTAssertFalse(DayWindow.contains(x: 0, y: (d.windows.y0 + d.windows.y1) / 2), "\(d.id) has no window at x 0") }
        }
    }

    func testPalettesAvoidJellyHues() {
        let avoid: [Float] = [250, 100, 145, 300, 350]          // blue, yellow, green, purple, pink
        for d in [RoomCatalog.loft, RoomCatalog.cabin] {
            for (i, s) in d.theme.swatches.enumerated() {
                let lab = OKLab.fromLinear(s)
                let c = hypotf(lab.y, lab.z)
                guard c > 0.03 else { continue }
                var h = atan2f(lab.z, lab.y) * 180 / .pi; if h < 0 { h += 360 }
                for a in avoid {
                    let dh = min(abs(h - a), 360 - abs(h - a))
                    XCTAssertGreaterThanOrEqual(dh, 25, "\(d.id) swatch \(i): hue \(h) too close to \(a)")
                }
            }
        }
        XCTAssertEqual(RoomCatalog.home.theme.swatches, RoomTheme().swatches)
    }

    func testRoomArtLoads() throws {
        for d in [RoomCatalog.loft, RoomCatalog.cabin] {
            let art = try XCTUnwrap(RoomArt.art(try XCTUnwrap(d.art)), "\(d.id) art missing")
            XCTAssertLessThanOrEqual(art.triangles, 15000)
            let b = art.bounds
            XCTAssertGreaterThanOrEqual(b.lo.x, RoomLayout.minX - 0.01); XCTAssertLessThanOrEqual(b.hi.x, RoomLayout.maxX + 0.01)
            XCTAssertGreaterThanOrEqual(b.lo.y, -0.01); XCTAssertLessThanOrEqual(b.hi.y, RoomLayout.wallHeight + 0.01)
            XCTAssertGreaterThanOrEqual(b.lo.z, RoomLayout.minZ - 0.01); XCTAssertLessThanOrEqual(b.hi.z, RoomLayout.minZ + 2.0)
            // every low vertex stands inside a collider grown by 0.15, or hugs the back / side wall
            var stray = 0
            for part in art.parts { for p in part.positions where p.y < 1.2 {
                let xz = SIMD2(p.x, p.z)
                let nearWall = p.z < RoomLayout.minZ + 0.6 || p.x < RoomLayout.minX + 0.6 || p.x > RoomLayout.maxX - 0.6
                let inBox = d.allBoxes.contains { RoomLayout.boxDistance(xz, $0) < 0.15 }
                let inCyl = d.cylinders.contains { simd_distance(xz, $0.centre) < $0.radius + 0.15 }
                if !(nearWall || inBox || inCyl) { stray += 1 }
            } }
            XCTAssertEqual(stray, 0, "\(d.id): low art outside every collider")
            // the geometry builds with the art in it
            let m = RoomGeometry.build(theme: d.theme, def: d)
            XCTAssertGreaterThan(m.indices.count, RoomGeometry.build(theme: RoomTheme(), def: RoomCatalog.home).indices.count / 2)
        }
    }

    func testRendererRebuildsOnApply() throws {
        let dev = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let lib = try XCTUnwrap(dev.makeDefaultLibrary(bundle: Bundle(for: RoomRenderer.self)))
        let room = try XCTUnwrap(RoomRenderer(device: dev, library: lib, colorFormat: .rgba8Unorm_srgb, depthFormat: .depth32Float, sampleCount: 4))
        room.ensureBuilt()
        let n0 = room.indexCount, v0 = room.staticVersion
        RoomLayout.apply(RoomCatalog.loft)
        room.ensureBuilt()
        XCTAssertNotEqual(room.indexCount, n0)
        XCTAssertGreaterThan(room.staticVersion, v0)
        XCTAssertEqual(room.theme, RoomCatalog.loft.theme)
        let v1 = room.staticVersion
        room.ensureBuilt()
        XCTAssertEqual(room.staticVersion, v1, "no rebuild without a room change")
        RoomLayout.apply(RoomCatalog.home)
        room.ensureBuilt()
        XCTAssertEqual(room.indexCount, n0)
    }

    func testUniformsAppendOnly() {
        // the Metal struct ends with style / win after lampPos: 17 matrices+vectors before, 2 float4 appended
        XCTAssertEqual(MemoryLayout<RoomUniforms>.stride % 16, 0)
        XCTAssertEqual(MemoryLayout<RoomUniforms>.offset(of: \RoomUniforms.win), MemoryLayout<RoomUniforms>.stride - 16)
        XCTAssertEqual(MemoryLayout<RoomUniforms>.offset(of: \RoomUniforms.style), MemoryLayout<RoomUniforms>.stride - 32)
    }
}
