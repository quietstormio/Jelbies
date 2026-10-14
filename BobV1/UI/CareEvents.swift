import Foundation
import Observation

enum CareEvent: Equatable {
    case feed(UUID), water(UUID), bathe(UUID), play(UUID), pet(UUID), tapped(UUID)

    var blobID: UUID {
        switch self {
        case .feed(let i), .water(let i), .bathe(let i), .play(let i), .pet(let i), .tapped(let i): return i
        }
    }
}

/// Bus between the SwiftUI HUD and the 3D stage. The HUD sends care events; the stage may either
/// set `onEvent` (called synchronously) or observe `lastEvent` / `sequence`. The stage calls
/// `showStatus(id)` (e.g. on tap) to pop the status card, and sets `activeID` as selection changes.
@Observable
nonisolated final class CareEvents {
    /// Most recent event (observe together with `sequence`, which changes even for repeated events).
    private(set) var lastEvent: CareEvent?
    private(set) var sequence = 0
    /// Currently selected Blob (HomeView keeps this in sync with its chips; stage may set it too).
    var selectedID: UUID?
    /// Blob whose status card is showing, nil = hidden.
    var statusID: UUID?
    @ObservationIgnored var onEvent: ((CareEvent) -> Void)?

    init() {}

    func send(_ e: CareEvent) {
        lastEvent = e
        sequence += 1
        onEvent?(e)
    }

    func showStatus(_ id: UUID) { statusID = id }
    func hideStatus() { statusID = nil }
}
