//
//  BathSilence.swift
//  The bath's sound hook. The bath makes no sound of its own; the class stays as the (silent) `BathSound` the flow owns, because
//  GameCare wires its `muted` flag to the voice mic. It NEVER touches the AVAudioSession.
//

import Foundation

@MainActor
protocol BathSound: AnyObject {}

@MainActor
final class BathSilence: BathSound {
    static let shared = BathSilence()
    /// True while the voice mic owns the session: stay silent.
    var muted: () -> Bool = { false }
}
