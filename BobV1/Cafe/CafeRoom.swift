//
//  CafeRoom.swift
//  The café as a visiting room: a RoomDef applied with `RoomLayout.apply` under the white fade, exactly like a room switch but WITHOUT `store.moveIn`,
//  so nothing is saved. It is not in `RoomCatalog.all` (it is never livable, never bought). Art: Blender `room_cafe.bin`; without it the living room furniture shows.
//

import simd
import Foundation

extension RoomCatalog {
    /// Warm oat / latte, low chroma (nothing in the jelly hues). The colliders are the booth banquette (back centre), the counter with the pastry case and
    /// the espresso machine (back right) and a bistro table with a lamp (back left); the front floor is left clear for the serving.
    static let cafe = RoomDef(
        id: .cafe, title: "Café", blurb: "Treats, a booth and a big sunny window.",
        theme: RoomTheme(tint: SIMD3(0.80, 0.69, 0.57), chromaScale: 0.55, lightnessShift: 0.02),
        couch: .init(centre: SIMD3(0, 0.45, -4.3), halfExtents: SIMD3(1.7, 0.45, 0.55), radius: 0.2),
        boxes: [.init(centre: SIMD3(3.75, 0.6, -4.45), halfExtents: SIMD3(1.05, 0.6, 0.45), radius: 0.08)],
        cylinders: [.init(centre: SIMD2(-3.9, -4.0), radius: 0.45, height: 0.75)],
        lampTable: .init(centre: SIMD2(-3.9, -4.0), radius: 0.45, height: 0.75), lamp: SIMD3(-3.9, 1.15, -4.0),
        windows: RoomWindows(xs: [-2.9], halfW: 1.25, y0: 1.3, y1: 4.2, proceduralFrames: false),
        floor: .tile, wall: .plain, rug: .inlay, art: "cafe")
}
