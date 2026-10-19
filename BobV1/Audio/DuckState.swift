//
//  DuckState.swift
//  The mic's hold on the speaker: while Bob listens, music, ambience and effects fall to silence (the speaker must not leak into dictation),
//  and after he stops they come back over `restore` seconds following a short settle. Pure: the engine feeds dt and reads `gain`.
//

import Foundation

nonisolated struct DuckState: Equatable, Sendable {
    var fallTime = 0.15, settle = 0.35, restoreTime = 0.9, floor: Float = 0
    private(set) var listening = false
    private(set) var gain: Float = 1
    private var sinceClose: Double = 100

    var isDucked: Bool { gain < 0.999 }

    mutating func micOpened() { listening = true }
    mutating func micClosed() { listening = false; sinceClose = 0 }

    @discardableResult
    mutating func update(dt: Double) -> Float {
        if listening {
            gain = max(floor, gain - Float(dt / fallTime))
        } else {
            sinceClose += dt
            if sinceClose > settle { gain = min(1, gain + Float(dt / restoreTime)) }
        }
        return gain
    }
}
