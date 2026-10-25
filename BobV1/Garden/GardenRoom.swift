//
//  GardenRoom.swift
//  The Garden as a HOME room (bought like the loft and the cabin, lived in with the same fade): a RoomDef whose colliders are the planter trough with the four
//  plots (the main seat at the back centre), the potting shed, the bird bath and two round flower beds. The scenery itself is built in GardenScenery.swift.
//  The camera, floor and roaming are the room's own, so everything (feeding, sleep, play, voice, photos, decor) works here as at home.
//

import simd
import Foundation

nonisolated enum GardenLayout {
    /// The raised planter trough at the back centre; the four plots sit along it.
    static let troughCentre = SIMD3<Float>(0, 0.15, -4.2)
    static let troughHalf = SIMD3<Float>(1.95, 0.15, 0.5)
    static let plotXs: [Float] = [-1.4, -0.47, 0.47, 1.4]
    static let soilY: Float = 0.31
    static func plotCentre(_ i: Int) -> SIMD3<Float> { SIMD3(plotXs[min(max(i, 0), plotXs.count - 1)], soilY, troughCentre.z) }
    /// The bird bath (also the room's lamp table), the two round beds, the shed, the deck.
    static let birdBath = SIMD2<Float>(-4.0, -3.1)
    static let bedA = SIMD2<Float>(-3.7, -0.5), bedB = SIMD2<Float>(3.9, 0.9)
    static let bedRadius: Float = 0.72
    static let shed = (min: SIMD2<Float>(3.3, -4.95), max: SIMD2<Float>(4.95, -3.75), height: Float(2.1))
    static let deck = (min: SIMD2<Float>(2.7, -3.5), max: SIMD2<Float>(4.95, -1.0))
    static let gateX: Float = -2.8
    static let fenceZ: Float = -5.0
}

extension RoomCatalog {
    static let garden = RoomDef(
        id: .garden, title: "Cottage Garden", blurb: "A picket-fenced backyard full of flowers, a veg patch to plant, a bird bath and a sunny deck.",
        theme: RoomTheme(tint: SIMD3(0.98, 0.84, 0.74), chromaScale: 0.8, lightnessShift: 0.03),
        couch: .init(centre: GardenLayout.troughCentre, halfExtents: GardenLayout.troughHalf, radius: 0.12),
        boxes: [.init(centre: SIMD3((GardenLayout.shed.min.x + GardenLayout.shed.max.x) / 2, 1.0, (GardenLayout.shed.min.y + GardenLayout.shed.max.y) / 2),
                      halfExtents: SIMD3((GardenLayout.shed.max.x - GardenLayout.shed.min.x) / 2, 1.0, (GardenLayout.shed.max.y - GardenLayout.shed.min.y) / 2), radius: 0.05)],
        cylinders: [.init(centre: GardenLayout.birdBath, radius: 0.42, height: 0.95),
                    .init(centre: GardenLayout.bedA, radius: GardenLayout.bedRadius, height: 0.22),
                    .init(centre: GardenLayout.bedB, radius: GardenLayout.bedRadius, height: 0.22)],
        lampTable: .init(centre: GardenLayout.birdBath, radius: 0.42, height: 0.95), lamp: SIMD3(3.6, 1.7, -2.4),
        windows: RoomWindows(xs: [], halfW: 0, y0: 0, y1: 14, proceduralFrames: false),
        floor: .chevron, wall: .plain, rug: .rings, art: nil)
}
