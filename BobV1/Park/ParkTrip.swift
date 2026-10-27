//
//  ParkTrip.swift
//  The park outing as a pure state machine (CafeTrip style): the picker (who comes along), a white fade out, the swap into the park while it is opaque, a few held
//  steps, the fade in, the play, "Go home" and the same fade back. It owns no bodies: GameCare+Park.swift does the swaps in `onSwap`.
//

import Foundation
import Observation

@MainActor
@Observable
final class ParkTrip {
    enum Phase { case off, pick, goOut, arriveHold, arriveIn, playing, leaveOut, leaveHold, leaveIn }
    enum Dest { case park, home }

    private(set) var phase: Phase = .off { didSet { if phase != oldValue { print("[park] phase \(phase)") } } }
    /// 0...1: how white the veil is.
    private(set) var wipe: Float = 0
    /// The slots (roster order) that come along, 1...3.
    var picked: [Int] = []
    /// The friendly line for a blocked entry or a happening (a level up, a gift); cleared after `toastSeconds`.
    var toast: String?
    /// The gift reveal on screen (a friend's present: who and what), for `ParkTuning.giftCardSeconds`; a tap closes it early.
    var gift: (friend: String, itemID: String)?
    @ObservationIgnored var giftT: Float = 0
    /// SF Symbols shown before the toast text (a gift: the present, then the item), nil for plain toasts.
    var toastSymbols: [String] = []
    /// The visitor whose card is open (pool id).
    var card: Int?
    private(set) var serial = 0
    @ObservationIgnored var holdFrames = 0
    @ObservationIgnored var toastT: Float = 0
    /// Called once with the white opaque: the world swap.
    @ObservationIgnored var onSwap: (Dest) -> Void = { _ in }

    nonisolated deinit {}

    var active: Bool { phase != .off }
    var picking: Bool { phase == .pick }
    /// The park is the world (music, chrome, the decor hidden, the other Jelbies away).
    var inScene: Bool {
        switch phase { case .arriveHold, .arriveIn, .playing, .leaveOut: return true; default: return false }          // (not leaveHold: the home swap sees the park already gone)
    }
    var hidesDecor: Bool { inScene }
    var canGoHome: Bool { phase == .playing }

    func openPicker(all: [Int]) {
        guard phase == .off else { return }
        picked = all; phase = .pick; card = nil
    }
    func cancelPicker() { if phase == .pick { phase = .off } }
    func begin() {
        guard phase == .pick, !picked.isEmpty else { return }
        phase = .goOut; wipe = 0; holdFrames = 0; serial += 1
    }
    /// The picker closes while the Jelbies run out of the room, then the trip begins with the same company (GameCare+Outing.swift).
    func resume(picked p: [Int]) { guard phase == .off, !p.isEmpty else { return }; picked = p; phase = .pick; begin() }
    func goHome() {
        guard canGoHome else { return }
        card = nil; phase = .leaveOut
    }
    func finish() { gift = nil; phase = .off; wipe = 0; holdFrames = 0; card = nil }

    /// Once per fixed step. `blocked`: something started under the fade (checked while fading out to the park).
    func step(dt: Float, blocked: Bool = false) {
        if gift != nil { giftT += dt; if giftT > ParkTuning.giftCardSeconds { gift = nil } }
        if toast != nil { toastT += dt; if toastT > ParkTuning.toastSeconds { toast = nil; toastSymbols = [] } }
        switch phase {
        case .off, .pick, .playing: break
        case .goOut:
            if blocked { finish(); return }
            wipe = min(wipe + dt / ParkTuning.fadeOut, 1)
            if wipe >= 1 { phase = .arriveHold; holdFrames = 0; onSwap(.park) }
        case .arriveHold:
            holdFrames += 1
            if holdFrames >= ParkTuning.holdSteps { phase = .arriveIn }
        case .arriveIn:
            wipe = max(wipe - dt / ParkTuning.fadeIn, 0)
            if wipe <= 0 { phase = .playing }
        case .leaveOut:
            wipe = min(wipe + dt / ParkTuning.fadeOut, 1)
            if wipe >= 1 { phase = .leaveHold; holdFrames = 0; onSwap(.home) }
        case .leaveHold:
            holdFrames += 1
            if holdFrames >= ParkTuning.holdSteps { phase = .leaveIn }
        case .leaveIn:
            wipe = max(wipe - dt / ParkTuning.fadeIn, 0)
            if wipe <= 0 { finish() }
        }
    }

    func showGift(friend: String, itemID: String) { gift = (friend, itemID); giftT = 0 }
    func say(_ s: String, symbols: [String] = []) { toast = s; toastSymbols = symbols; toastT = 0 }
}
