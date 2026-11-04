//
//  GameCare+CafeRegulars.swift
//  The café's regulars: one or two real Park friends (the player's friends first, else the day's visitors) stand at the bistro table and the counter, do calm idles and
//  chirp in their own voices now and then. Their bodies are the park's visitor bodies (the stage's `parkActors`, made by `parkBook.spawn`, exactly like the guest at home
//  and the beach's opponents): at most two extra bodies. They stand, never sit, keep well away from the Jelbies' table, use only existing idles, and leave with the café.
//  No contact or social code: autonomy and idle blocking are off, so nothing here can touch another body.
//

import Foundation
import simd

extension GameCare {
    /// Where the regulars stand: in front of the bistro table (back left) and the counter (back right).
    static let regularSpots: [SIMD2<Float>] = [SIMD2(-3.2, -3.3), SIMD2(3.3, -3.3)]
    /// A regular keeps at least this far from every Jelbie (centre to centre).
    static let regularMargin: Float = 1.8

    /// Who the regulars are: the player's Park friends first (best friendship first), then the day's visitors; `count` of them.
    func cafeRegularCast(count: Int) -> [ParkVisitor] {
        let characters = jellies.map(\.character)
        var cast = parkBook.visitors
            .filter { $0.bestLevel(among: characters) > .stranger }
            .sorted { $0.bestLevel(among: characters) != $1.bestLevel(among: characters) ? $0.bestLevel(among: characters) > $1.bestLevel(among: characters) : $0.id < $1.id }
        cast = Array(cast.prefix(count))
        if cast.count < count {
            let more = parkBook.chooseCast(count: count, characters: characters, now: Date().timeIntervalSince1970).filter { v in !cast.contains { $0.id == v.id } }
            cast += more.prefix(count - cast.count)
        }
        return cast
    }

    /// Voice of a regular: the species' own (the signature rule: wings = Lavender, daisy = Moss, spines = Pip, else Bob).
    static func regularVoiceCharacter(_ v: ParkVisitor) -> Int {
        switch v.signature { case .spines: return 1; case .daisy: return 2; case .wings: return 3; default: return 0 }
    }

    /// Once per step during the café: the regulars arrive (once the guest body, if any, is gone), are ticked and leave with the café.
    func tickCafeRegulars(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        if book.regularsPending {
            guard guestBook.actor == nil, parkBook.spawn != nil, !actors.isEmpty, actors.allSatisfy({ $0.brain != nil }) else { return }
            book.regularsPending = false
            let want = Int.random(in: 1...2)
            let cast = cafeRegularCast(count: want)
            guard !cast.isEmpty else { return }
            var spots = Self.regularSpots
            if cast.count == 1 && Bool.random() { spots.reverse() }
            let bodies = parkBook.spawn?(cast, Array(spots.prefix(cast.count))) ?? []
            guard bodies.count == cast.count else { return }
            parkBook.actors = bodies; parkBook.cast = cast.map(\.id)
            book.regulars = bodies; book.regularVisitors = cast
            let floors = actors.map(\.floor)
            for (k, a) in bodies.enumerated() {
                var spot = spots[k]
                if floors.contains(where: { simd_distance($0, spot) < Self.regularMargin }) { spot = spots[(k + 1) % spots.count] }
                rehome(a, at: spot)
                guard let b = a.brain else { continue }
                b.autonomy = false; b.idleBlocked = true; b.restTimer = 1
                b.startTurn(to: b.faceCameraYaw(), sim: a.sim)
                b.face(.happy, hold: 1.5)
                book.regularIdle[a.id] = Float.random(in: 2...5)
                book.regularHome[a.id] = spot
            }
            return
        }
        for (a, v) in zip(book.regulars, book.regularVisitors) {
            guard let b = a.brain else { continue }
            visitorLook(a, v, dt: dt)
            b.autonomy = false; b.idleBlocked = true
            guard var t = book.regularIdle[a.id] else { continue }
            guard b.commandedIdle == nil, b.idleState.kind == nil, case .none = b.script, b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace else { continue }
            t -= dt
            if t > 0 { book.regularIdle[a.id] = t; continue }
            book.regularIdle[a.id] = Float.random(in: 4...8)
            if let home = book.regularHome[a.id], simd_distance(Self.floorPos(b, a.sim), home) > 0.4 { b.requestNow(.goTo(home)); book.regularIdle[a.id] = 2.5; continue }
            if abs(Self.wrapAngle(b.yaw - b.faceCameraYaw())) > 0.6 { b.startTurn(to: b.faceCameraYaw(), sim: a.sim); book.regularIdle[a.id] = 1.2; continue }
            b.commandedIdle = [IdleKind.chirp, .giggle, .stretch, .bounce].randomElement()
            b.face(.happy, hold: 1.5)
            if Float.random(in: 0..<1) < 0.4 { b.blushBump(hold: 2, peak: 0.4) }
        }
    }

    /// The regulars leave (the café's swap home, under the white): looks put away, bodies hidden.
    func cafeRegularsLeave() {
        let book = cafeBook
        book.regularsPending = false
        guard !book.regulars.isEmpty else { return }
        for a in book.regulars { visitorPutAway(a) }
        parkBook.clear?()
        parkBook.actors = []; parkBook.cast = []
        book.regulars = []; book.regularVisitors = []; book.regularIdle = [:]; book.regularHome = [:]
    }

    static func wrapAngle(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }
}
