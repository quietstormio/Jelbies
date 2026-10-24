//
//  RoomDef.swift
//  The rooms the Jelbies can live in. Every room shares the same box, rug, camera and front floor (see RoomLayout); a room only changes what stands in
//  the BACK BAND (furniture colliders, art), the palette, the window layout and the floor / wall / rug styles. Room 0 is the original living room.
//

import simd
import Foundation

nonisolated enum RoomID: String, Codable, CaseIterable, Sendable { case home, loft, cabin, cafe, park }

nonisolated struct RoomWindows: Equatable, Sendable {
    var xs: [Float]; var halfW: Float; var y0: Float; var y1: Float
    /// true = RoomGeometry draws the frame / mullions / sill (home); false = the Blender art carries them.
    var proceduralFrames: Bool
}
nonisolated enum FloorStyle: Int, Sendable { case chevron = 0, longPlank = 1, roughPlank = 2, tile = 3 }
nonisolated enum WallStyle: Int, Sendable { case plain = 0, brick = 1, logs = 2 }
nonisolated enum RugStyle: Int, Sendable { case rings = 0, stripes = 1, braided = 2, inlay = 3 }

nonisolated struct RoomDef: Equatable, Sendable {
    var id: RoomID
    var title: String
    var blurb: String
    var theme: RoomTheme
    /// The main seat at the back centre (the Antics peek spots use its half x).
    var couch: RoomLayout.RoundedBox
    /// Any further box colliders (may be empty).
    var boxes: [RoomLayout.RoundedBox]
    var cylinders: [RoomLayout.Cylinder]
    /// The piece under the room lamp (sleep keeps clear of it; = `RoomLayout.table`).
    var lampTable: RoomLayout.Cylinder
    /// Lamp pool centre (the renderer overrides `daylight.lampPos.xyz` with it; w stays).
    var lamp: SIMD3<Float>
    var windows: RoomWindows
    var floor: FloorStyle, wall: WallStyle, rug: RugStyle
    /// nil = the procedural furniture (home); else the bundled `room_<art>.bin`.
    var art: String?
    var allBoxes: [RoomLayout.RoundedBox] { [couch] + boxes }
}

nonisolated enum RoomCatalog {
    static let home = RoomDef(
        id: .home, title: "Living room", blurb: "The cosy room where it all began: sofa, plant and a lamp.",
        theme: RoomTheme(),
        couch: .init(centre: SIMD3(0, 0.5, -4.2), halfExtents: SIMD3(1.8, 0.5, 0.65), radius: 0.2), boxes: [],
        cylinders: [.init(centre: SIMD2(3.7, -4.0), radius: 0.5, height: 0.65), .init(centre: SIMD2(-4.2, -4.2), radius: 0.4, height: 0.5)],
        lampTable: .init(centre: SIMD2(3.7, -4.0), radius: 0.5, height: 0.65), lamp: SIMD3(3.7, 1.0, -4.0),
        windows: RoomWindows(xs: [-3, 0, 3], halfW: 0.85, y0: 1.5, y1: 4.3, proceduralFrames: true),
        floor: .chevron, wall: .plain, rug: .rings, art: nil)

    static let loft = RoomDef(
        id: .loft, title: "Sunny Loft", blurb: "Big steel windows, a brick wall and a low, slouchy sofa.",
        theme: RoomTheme(tint: SIMD3(0.84, 0.81, 0.77), chromaScale: 0.5),
        couch: .init(centre: SIMD3(0, 0.45, -4.25), halfExtents: SIMD3(1.9, 0.45, 0.6), radius: 0.22), boxes: [],
        cylinders: [.init(centre: SIMD2(3.8, -4.1), radius: 0.45, height: 0.6), .init(centre: SIMD2(-4.1, -4.1), radius: 0.45, height: 0.6)],
        lampTable: .init(centre: SIMD2(3.8, -4.1), radius: 0.45, height: 0.6), lamp: SIMD3(3.8, 1.05, -4.1),
        windows: RoomWindows(xs: [-2.4, 2.4], halfW: 1.5, y0: 1.2, y1: 4.6, proceduralFrames: false),
        floor: .longPlank, wall: .brick, rug: .stripes, art: "loft")

    static let cabin = RoomDef(
        id: .cabin, title: "Cosy Cabin", blurb: "Log walls, a little iron stove and a knitted settee.",
        theme: RoomTheme(tint: SIMD3(0.74, 0.55, 0.40), lightnessShift: -0.04),
        couch: .init(centre: SIMD3(0, 0.5, -4.2), halfExtents: SIMD3(1.75, 0.5, 0.65), radius: 0.18), boxes: [],
        cylinders: [.init(centre: SIMD2(3.8, -4.1), radius: 0.4, height: 0.55), .init(centre: SIMD2(-4.0, -4.0), radius: 0.55, height: 1.1)],
        lampTable: .init(centre: SIMD2(3.8, -4.1), radius: 0.4, height: 0.55), lamp: SIMD3(3.8, 0.95, -4.1),
        windows: RoomWindows(xs: [-2.6, 2.6], halfW: 0.75, y0: 1.7, y1: 3.5, proceduralFrames: false),
        floor: .roughPlank, wall: .logs, rug: .braided, art: "cabin")

    /// The livable, buyable rooms. The café (CafeRoom.swift) and the park (Park/ParkRoom.swift) are visiting rooms and are NOT in this list.
    static let all: [RoomDef] = [home, loft, cabin]
    static func def(_ id: RoomID) -> RoomDef { id == .cafe ? cafe : id == .park ? park : (all.first { $0.id == id } ?? home) }
}
