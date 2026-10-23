//
//  RoomArt.swift
//  The Blender-made furniture of the bought rooms, loaded from the bundled room_<art>.bin files (tools/convert_room_art.py builds them from the OBJ
//  exports; same binary format as the decor, see DecorMeshes). Room-world game coordinates: floor y = 0, back wall z = -5, origin = room origin.
//

import Foundation

nonisolated enum RoomArt {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DecorMeshes.Art] = [:]
    nonisolated(unsafe) private static var missing: Set<String> = []

    static func art(_ name: String) -> DecorMeshes.Art? {
        lock.lock(); defer { lock.unlock() }
        if let a = cache[name] { return a }
        if let a = DecorMeshes.load(name, prefix: "room_") { cache[name] = a; return a }
        if missing.insert(name).inserted { print("RoomArt: room_\(name).bin is missing; the room falls back to the living room furniture") }
        return nil
    }

    /// Appends every part of the room's art; false when the resource is missing (the caller then builds the procedural furniture, so a room is never empty).
    @discardableResult
    static func emit(_ name: String, into b: RoomMeshBuilder) -> Bool {
        guard let a = art(name) else { return false }
        for part in a.parts { DecorMeshes.emit(part, into: b, offset: .zero) }
        return true
    }
}
