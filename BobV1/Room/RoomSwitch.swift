//
//  RoomSwitch.swift
//  The fade between rooms (the same white veil as the bath): out, swap the world while it is opaque, hold a few steps so the geometry rebuild
//  and the room cache settle, then in. GameCare+Rooms.swift drives it.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoomSwitch {
    enum Phase { case off, out, hold, into }
    private(set) var phase: Phase = .off
    /// 0...1: how white the veil is (RoomSwitchVeil reads it).
    private(set) var wipe: Float = 0
    /// The room we are moving to.
    private(set) var dest: RoomID?
    @ObservationIgnored var holdFrames = 0

    var active: Bool { phase != .off }

    func begin(to id: RoomID) { dest = id; phase = .out; wipe = 0; holdFrames = 0 }
    func setWipe(_ w: Float) { wipe = min(max(w, 0), 1) }
    func set(_ p: Phase) { phase = p }
    func finish() { phase = .off; wipe = 0; dest = nil; holdFrames = 0 }
}

nonisolated enum RoomSwitchTuning {
    /// The same feel as the bath's fade.
    static let fadeOut: Float = 0.4, fadeIn: Float = 0.5
    /// Steps spent fully white after the swap.
    static let holdSteps = 3
}

/// Why a move is refused (the picker shows a short line for it).
nonisolated enum RoomSwitchBlock: String, Sendable {
    case notOwned, same, busy, trip, bath, focus, meal, arranging, sleeping

    var message: String {
        switch self {
        case .notOwned: return "Buy this room in the Shop first"
        case .same: return "They live here now"
        case .busy: return "One moment, moving already"
        case .trip: return "Wait until they are back from the trip"
        case .bath: return "Finish the Clean first"
        case .focus: return "Let go of the close-up first"
        case .meal: return "Finish the meal first"
        case .arranging: return "Finish arranging first"
        case .sleeping: return "Shh, they're sleeping"
        }
    }
}
