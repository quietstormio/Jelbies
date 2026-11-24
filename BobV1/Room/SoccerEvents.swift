//
//  SoccerEvents.swift
//  The soccer round's one emit point. The physics (DecorField+Soccer.swift) and the Jellies' kicks (BlobBrain+Soccer.swift, BlobSocial+Pass.swift)
//  report here; whoever wants to react (the liveliness / reaction bus, sounds, the HUD) sets `sink`. Nothing here renders or plays anything itself.
//  `recent` keeps the last few events for the tests and for a late subscriber.
//

import Foundation
import simd

nonisolated enum SoccerEvent: Equatable, Sendable {
    /// A Jelly (steer id) kicked the ball (a plain kick, a dribble nudge, a pass or a shot).
    case kick(jelly: Int, speed: Float, shot: Bool)
    /// He stomped and the ball was not where his toe landed (or the toe only grazed it).
    case fumble(jelly: Int)
    /// The ball crossed a goal's mouth going in: `scorer` is the last kicker (-1 when it rolled in on its own).
    case goal(scorer: Int, goal: Int)
    /// The ball passed just outside a post, or rattled a post, without going in.
    case nearMiss(jelly: Int, goal: Int)
    /// A rolling ball went by a Jelly who was not the kicker (within about a body's width).
    case rolledPast(jelly: Int, kicker: Int)
}

@MainActor
enum SoccerEvents {
    /// Set by the stage / the reaction layer: every event goes here first.
    static var sink: ((SoccerEvent) -> Void)?
    /// The last few events, newest last (tests; a late subscriber may read them).
    private(set) static var recent: [SoccerEvent] = []
    static let keep = 32
    /// Events emitted since launch (the room's soccer director reads the new ones).
    private(set) static var serial = 0
    static func since(_ n: Int) -> [SoccerEvent] { Array(recent.suffix(min(max(serial - n, 0), recent.count))) }

    static func emit(_ e: SoccerEvent) {
        if EmoteSpot.logOn { NSLog("[soccer] ev=%@", String(describing: e)) }          // (move-mix round 3: the soccer moments, counted from the real-app console)
        recent.append(e); serial += 1
        if recent.count > keep { recent.removeFirst(recent.count - keep) }
        sink?(e)
    }
    static func clear() { recent = [] }
    static func count(where f: (SoccerEvent) -> Bool) -> Int { recent.filter(f).count }
}
