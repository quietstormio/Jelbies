//
//  CafeTrip.swift
//  The café outing as a pure state machine (ShowFlow / RoomSwitch style): a white fade out, the swap into the café while it is opaque, a few held steps,
//  the fade in, the menu, the meal, the cheer, "Head home" and the same fade back. It owns no bodies: GameCare+Cafe.swift does the swaps in `onSwap`.
//

import Foundation
import Observation

@MainActor
@Observable
final class CafeTrip {
    enum Phase { case off, goOut, arriveHold, arriveIn, menu, eating, cheer, lounge, done, leaveOut, leaveHold, leaveIn }
    enum Dest { case cafe, home }

    private(set) var phase: Phase = .off { didSet { if phase != oldValue { print("[cafe] phase \(phase)") } } }
    /// 0...1: how white the veil is.
    private(set) var wipe: Float = 0
    private(set) var order: CafeOrder?
    /// Jelbies (roster ids) whose treat is down and eaten: the order list ticks them off.
    var served: Set<Int> = []
    /// What the order cost and whether it was the stamp card's free one (the list's footer).
    var charged = 0
    var wasFree = false
    /// Today's special (set by GameCare when the menu opens).
    var special: CafeTreatID?
    /// The friendly line for a blocked entry (the toast); cleared after `toastSeconds`.
    var refusal: String?
    /// The menu card's inline line when an order was refused (the capture aid sets it too).
    var cardRefusal: String?
    private(set) var serial = 0
    @ObservationIgnored var holdFrames = 0
    @ObservationIgnored var cheerT: Float = 0
    /// Set by GameCare while a baby-latte café zoomies burst is still running: the cheer waits for it.
    @ObservationIgnored var holdCheer = false
    @ObservationIgnored var toastT: Float = 0
    @ObservationIgnored var loungeT: Float = 0
    /// The stamp card (persisted under CafeStamps.v1; not under XCTest).
    let stamps: CafeStampBook
    init(stamps: CafeStampBook? = nil) { self.stamps = stamps ?? CafeStampBook() }
    /// Called once with the white opaque: the world swap.
    @ObservationIgnored var onSwap: (Dest) -> Void = { _ in }

    nonisolated deinit {}

    var active: Bool { phase != .off }
    /// The café is the world (music, chrome, the decor hidden).
    var inScene: Bool {
        switch phase { case .arriveHold, .arriveIn, .menu, .eating, .cheer, .lounge, .done, .leaveOut: return true; default: return false }          // (not leaveHold: the home swap sees the café already gone)
    }
    var hidesDecor: Bool { inScene }
    var menuOpen: Bool { phase == .menu }
    /// Go home is on screen from the moment the café fades in until the end (leaving mid-meal is safe: GameCare+Cafe cleans up under the white).
    var canGoHome: Bool { switch phase { case .arriveIn, .menu, .eating, .cheer, .lounge, .done: return true; default: return false } }
    /// The order list stays up from the menu to the end.
    var listOpen: Bool { switch phase { case .menu, .eating, .cheer, .lounge, .done: return true; default: return false } }
    /// They are at the table, relaxed (after the meal).
    var atTable: Bool { phase == .lounge || phase == .done || phase == .cheer }

    func begin() {
        guard phase == .off else { return }
        phase = .goOut; wipe = 0; holdFrames = 0; order = nil; cardRefusal = nil; serial += 1; served = []; charged = 0; wasFree = false
    }
    func goHome() {
        guard canGoHome else { return }
        phase = .leaveOut
    }
    func ordered(_ o: CafeOrder) {
        guard phase == .menu else { return }
        order = o; phase = .eating
    }
    func servingEnded() {
        guard phase == .eating else { return }
        phase = .cheer; cheerT = 0; holdCheer = false
    }
    func set(_ p: Phase) { phase = p }
    func finish() { served = []; phase = .off; wipe = 0; holdFrames = 0; order = nil; cheerT = 0; loungeT = 0 }

    /// Once per fixed step. `blocked`: something started under the fade (checked while fading out to the café).
    func step(dt: Float, blocked: Bool = false) {
        if refusal != nil { toastT += dt; if toastT > CafeTuning.toastSeconds { refusal = nil } }
        switch phase {
        case .off, .menu, .eating, .done: break
        case .goOut:
            if blocked { finish(); return }
            wipe = min(wipe + dt / CafeTuning.fadeOut, 1)
            if wipe >= 1 { phase = .arriveHold; holdFrames = 0; onSwap(.cafe) }
        case .arriveHold:
            holdFrames += 1
            if holdFrames >= CafeTuning.holdSteps { phase = .arriveIn }
        case .arriveIn:
            wipe = max(wipe - dt / CafeTuning.fadeIn, 0)
            if wipe <= 0 { phase = .menu }
        case .cheer:
            cheerT += dt
            if cheerT >= CafeTuning.cheerSeconds, !holdCheer { phase = .lounge; loungeT = 0 }
        case .lounge:
            loungeT += dt
            if loungeT >= CafeTuning.loungeSeconds { phase = .done }
        case .leaveOut:
            wipe = min(wipe + dt / CafeTuning.fadeOut, 1)
            if wipe >= 1 { phase = .leaveHold; holdFrames = 0; onSwap(.home) }
        case .leaveHold:
            holdFrames += 1
            if holdFrames >= CafeTuning.holdSteps { phase = .leaveIn }
        case .leaveIn:
            wipe = max(wipe - dt / CafeTuning.fadeIn, 0)
            if wipe <= 0 { finish() }
        }
    }

    func showRefusal(_ s: String) { refusal = s; toastT = 0 }
}
