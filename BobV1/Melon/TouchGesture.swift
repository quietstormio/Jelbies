//
//  TouchGesture.swift
//  The gesture decides the action in focus mode (no tabs); all of it is live at once:
//    one finger sliding on him                      PET
//    one quick tap                                  a ZONE TAP (head pat, cheek boop, belly poke)
//    two fingers that both start on him, together   CHEEKS (pinch)
//    press, hold ~0.25 s, then drag up              PICK UP
//    a fast flick when letting go of a pick up      THROW
//  The decision is made from movement and hold time in the first ~150-250 ms and is never switched mid-gesture.
//  Pure value type (times in seconds, points in screen points) so it is unit tested without a view.
//

import Foundation
import CoreGraphics

nonisolated struct TouchGesture: Sendable {
    enum Kind: Equatable, Sendable { case none, undecided, hold, pet, pickUp, cheeks }
    enum Release: Equatable, Sendable { case none, tap, throwIt(CGVector) }

    static let slop: CGFloat = 10             // points of movement that count as "moved"
    static let holdTime = 0.25                // seconds of staying put before it is a hold
    static let tapTime = 0.30                 // a tap is shorter than this
    static let pinchWindow = 0.20             // the second finger must land this soon after the first
    static let throwSpeed: CGFloat = 900      // points per second at release

    private(set) var kind: Kind = .none
    private(set) var t0 = 0.0
    private(set) var p0 = CGPoint.zero
    private(set) var last = CGPoint.zero
    private var samples: [(t: Double, p: CGPoint)] = []

    var isActive: Bool { kind != .none }
    /// The action is decided (it never changes again until the finger lifts).
    var decided: Bool { kind == .pet || kind == .pickUp || kind == .cheeks }

    mutating func down(t: Double, p: CGPoint) {
        kind = .undecided; t0 = t; p0 = p; last = p; samples = [(t, p)]
    }

    /// The second finger lands. Cheeks only if it landed soon after the first while the first had not moved on (both started on him: the caller
    /// only calls this for a finger that is on the body).
    mutating func secondDown(t: Double) -> Bool {
        guard kind == .undecided, t - t0 <= Self.pinchWindow else { return false }
        kind = .cheeks
        return true
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    mutating func move(t: Double, p: CGPoint) {
        last = p
        samples.append((t, p)); if samples.count > 10 { samples.removeFirst() }
        guard kind == .undecided || kind == .hold else { return }
        let moved = dist(p, p0)
        guard moved > Self.slop else { return }
        if kind == .undecided && t - t0 < Self.holdTime { kind = .pet; return }
        // after a hold: dragging up picks him up, anything else is a stroke
        let dx = p.x - p0.x, dy = p0.y - p.y           // dy > 0 = up the screen
        kind = (dy > Self.slop && dy >= abs(dx) * 0.7) ? .pickUp : .pet
    }

    /// Time passing with the finger still: ~0.25 s makes it a hold.
    mutating func tick(t: Double) {
        if kind == .undecided, t - t0 >= Self.holdTime { kind = .hold }
    }

    mutating func up(t: Double) -> Release {
        defer { kind = .none; samples = [] }
        switch kind {
        case .undecided: return t - t0 < Self.tapTime ? .tap : .none
        case .hold: return .tap
        case .pickUp:
            guard let a = samples.last(where: { t - $0.t > 0.05 }) ?? samples.first, let b = samples.last, b.t - a.t > 0.01 else { return .none }
            let v = CGVector(dx: (b.p.x - a.p.x) / (b.t - a.t), dy: (b.p.y - a.p.y) / (b.t - a.t))   // screen, y down
            return hypot(v.dx, v.dy) > Self.throwSpeed ? .throwIt(v) : .none
        default: return .none
        }
    }

    mutating func cancel() { kind = .none; samples = [] }
}
