//
//  TouchGesture.swift
//  The gesture decides the action in focus mode (no tabs); all of it is live at once:
//    one finger sliding on him                      PET
//    one quick tap                                  a ZONE TAP (head pat, cheek boop, belly poke)
//    two fingers that both start on him, together   CHEEKS (pinch)
//    double-tap, then hold ~0.15 s or drag, on him   PICK UP (second down within 0.30 s / 40 pt of a tap-up on him; see PickUpArm)
//    a single press-hold                            PET (a still finger is petting; it never picks him up)
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
    static let pickHold = 0.15                // an armed (double-tap) press held this long, or dragged, picks him up

    private(set) var kind: Kind = .none
    private(set) var t0 = 0.0
    private(set) var p0 = CGPoint.zero
    private(set) var last = CGPoint.zero
    private(set) var armed = false           // this press is the second touch of a double tap on him
    private var samples: [(t: Double, p: CGPoint)] = []

    var isActive: Bool { kind != .none }
    /// The action is decided (it never changes again until the finger lifts).
    var decided: Bool { kind == .pet || kind == .pickUp || kind == .cheeks }

    mutating func down(t: Double, p: CGPoint, armed: Bool = false) {
        self.armed = armed
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
        kind = armed ? .pickUp : .pet                    // double-tap-and-drag lifts him; any other slide is a stroke
    }

    /// Time passing with the finger still: an armed press held 0.15 s picks him up; otherwise ~0.25 s makes it a hold (petting).
    mutating func tick(t: Double) {
        guard kind == .undecided else { return }
        if armed { if t - t0 >= Self.pickHold { kind = .pickUp } }
        else if t - t0 >= Self.holdTime { kind = .hold }
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

/// Pure double-tap detector for the pick-up: a finished tap ON him arms it; the next down within 0.30 s and 40 pt of that tap-up is the
/// second touch of a double tap (the host passes `armed: true` to `TouchGesture.down`). Every down consumes the pending tap.
nonisolated struct PickUpArm: Sendable {
    static let window = 0.30
    static let radius: CGFloat = 40
    private var lastUp: (time: Double, point: CGPoint)?

    mutating func tapUp(time: Double, point: CGPoint) { lastUp = (time, point) }

    /// A finger went down on him: true when it completes a double tap.
    mutating func touchDown(time: Double, point: CGPoint) -> Bool {
        defer { lastUp = nil }
        guard let up = lastUp else { return false }
        let dt = time - up.time
        return dt >= 0 && dt <= Self.window + 1e-9 && hypot(point.x - up.point.x, point.y - up.point.y) <= Self.radius
    }

    mutating func reset() { lastUp = nil }
}
