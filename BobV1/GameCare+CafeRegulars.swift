//
//  GameCare+CafeRegulars.swift
//  The café's regulars: while the player's Jelbies eat and chat, one or two real Park friends (the player's friends first, else the day's visitors) WALK IN through the door side,
//  a few seconds apart, and pull up at their OWN little table (a second / third café table, the same mesh, away from the player's). The table pops in, they stand at it (never sit),
//  a cup is set down with the clink, and they sip, do calm existing idles and chirp in their own species' voice in the chat. Their bodies are the park's visitor bodies (the stage's
//  `parkActors`, made by `parkBook.spawn`, like the guest at home and the beach opponents). At most `CafeTuning.maxBodies` Jelbies are on screen (the player's + the regulars, never
//  more than two), they keep `regularMargin` from every Jelbie, and they leave with the café. No contact or social code: autonomy is off, so nothing here touches another body.
//

import Foundation
import simd

extension GameCare {
    /// A regular keeps at least this far from every Jelbie (centre to centre) when he picks where to stand.
    static let regularMargin: Float = 1.8
    /// Where regulars come in: the door side of the café, just outside the floor.
    static func regularDoor(landscape: Bool) -> SIMD2<Float> { landscape ? SIMD2(4.4, 1.0) : SIMD2(3.7, 1.8) }
    /// Their little tables (floor x, z of the table centre), away from the player's.
    static func regularTables(landscape: Bool) -> [SIMD2<Float>] { landscape ? [SIMD2(0.7, 0.9), SIMD2(2.9, -0.3)] : [SIMD2(-2.2, 0.5), SIMD2(2.2, 0.5)] }

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

    /// Once per step during the café.
    func tickCafeRegulars(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook
        // 1. make their bodies (once the guest body at home, if any, is gone), far off the floor until it is their turn
        if book.regularsPending {
            guard guestBook.actor == nil, parkBook.spawn != nil, !actors.isEmpty, actors.allSatisfy({ $0.brain != nil }) else { return }
            book.regularsPending = false
            let n = CafeTuning.regularCount(owned: actors.count, want: Int.random(in: 1...2))
            let cast = n > 0 ? cafeRegularCast(count: n) : []
            guard !cast.isEmpty else { return }
            let bodies = parkBook.spawn?(cast, cast.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) }) ?? []
            guard bodies.count == cast.count else { return }
            parkBook.actors = bodies; parkBook.cast = cast.map(\.id)
            book.regulars = bodies; book.regularVisitors = cast
            for (k, a) in bodies.enumerated() {
                a.sim.arenaRadius = .infinity
                guard let b = a.brain else { continue }
                b.autonomy = false; b.idleBlocked = true
                book.regularState[a.id] = 0
                book.regularWait[a.id] = -1
                _ = k
            }
            return
        }
        guard !book.regulars.isEmpty else { return }
        let landscape = GameCamera.aspect >= 1
        // 2. each regular's turn comes a few seconds apart once the meal is on
        if cafe.phase == .eating || cafe.phase == .cheer || cafe.phase == .lounge || cafe.phase == .done {
            for (k, a) in book.regulars.enumerated() where book.regularWait[a.id] == -1 { book.regularWait[a.id] = 4 + Float(k) * 6 }
        }
        let floors = actors.map(\.floor)
        for (k, (a, v)) in zip(book.regulars, book.regularVisitors).enumerated() {
            guard let b = a.brain else { continue }
            visitorLook(a, v, dt: dt)
            b.autonomy = false; b.idleBlocked = true
            let state = book.regularState[a.id] ?? 0
            if state == 0 {
                guard var w = book.regularWait[a.id], w >= 0 else { continue }
                w -= dt
                if w > 0 { book.regularWait[a.id] = w; continue }
                // in through the door, to a table of his own that is clear of the player's and of every Jelbie
                var spot: SIMD2<Float>?
                for t in Self.regularTables(landscape: landscape) {
                    let stand = t + SIMD2(0, -0.735 + GameCare.eatCloser)
                    let free = simd_distance(t, book.origin) > 2.2 && floors.allSatisfy { simd_distance($0, stand) >= Self.regularMargin }
                        && !book.extraTables.contains { simd_distance($0.origin, t) < 2.0 }
                    if free { spot = t; break }
                }
                guard let t = spot else { book.regularWait[a.id] = 3; continue }          // nothing clear yet: try again in a moment
                a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius
                rehome(a, at: Self.regularDoor(landscape: landscape))
                let table = DiningSet()
                table.registersCollider = false
                table.tableSkin = { n in FoodMeshes.mesh(id: "cafetable_\(n)") }
                table.spawn(serving: CafePlate.emptyTable, n: 1, bobAt: SIMD2(99, 99), forcedOrigin: t)
                book.extraTables.append(table); book.extraFrames.append(nil)
                let stand = t + SIMD2(0, -0.735 + GameCare.eatCloser)
                book.regularHome[a.id] = stand; book.regularTable[a.id] = table
                book.regularState[a.id] = 1; book.regularWait[a.id] = nil
                b.restTimer = 0.2
                b.requestNow(.goTo(stand))
                b.face(.happy, hold: 2)
                AudioHub.shared.chirp(character: Self.regularVoiceCharacter(v), .happy)
                _ = k
                continue
            }
            let home = book.regularHome[a.id] ?? .zero
            let idleNow = b.commandedIdle == nil && b.idleState.kind == nil && { if case .none = b.script { return true } else { return false } }() && (b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace)
            if state == 1 {          // walking in: at his table he turns to the room and a cup is set down with the clink
                if idleNow, simd_distance(Self.floorPos(b, a.sim), home) < 0.5 {
                    book.regularState[a.id] = 2
                    b.startTurn(to: b.faceCameraYaw(), sim: a.sim)
                    let drinks: [CafeTreatID] = [.cocoa, .latte, .juice]
                    book.regularTable[a.id]?.restock(serving: CafePlate.cups([0: drinks[(k + a.id) % drinks.count]]))
                    book.regularIdle[a.id] = Float.random(in: 2...4)
                } else if idleNow {
                    b.requestNow(.goTo(home))
                }
                continue
            }
            // seated at his table (standing): calm idles, back to his spot if nudged, facing the room
            guard var t = book.regularIdle[a.id], idleNow else { continue }
            t -= dt
            if t > 0 { book.regularIdle[a.id] = t; continue }
            book.regularIdle[a.id] = Float.random(in: 4...8)
            if simd_distance(Self.floorPos(b, a.sim), home) > 0.4 { b.requestNow(.goTo(home)); book.regularIdle[a.id] = 2.5; continue }
            if abs(Self.wrapAngle(b.yaw - b.faceCameraYaw())) > 0.6 { b.startTurn(to: b.faceCameraYaw(), sim: a.sim); book.regularIdle[a.id] = 1.2; continue }
            b.commandedIdle = [IdleKind.chirp, .giggle, .stretch, .bounce].randomElement()
            b.face(.happy, hold: 1.5)
            if Float.random(in: 0..<1) < 0.4 { b.blushBump(hold: 2, peak: 0.4) }
        }
        for t in book.extraTables { t.update(dt: dt) }
    }

    /// The regulars leave (the café's swap home, under the white): looks put away, bodies hidden, their tables gone.
    func cafeRegularsLeave() {
        let book = cafeBook
        book.regularsPending = false
        for t in book.extraTables { t.reset() }
        book.extraTables = []; book.extraFrames = []; book.regularTable = [:]; book.forceDiningPush = true
        guard !book.regulars.isEmpty else { return }
        for a in book.regulars { visitorPutAway(a) }
        parkBook.clear?()
        parkBook.actors = []; parkBook.cast = []
        book.regulars = []; book.regularVisitors = []; book.regularIdle = [:]; book.regularHome = [:]; book.regularState = [:]; book.regularWait = [:]
    }

    /// The table meshes of the café: the player's (the `dining` set) and the regulars' small ones, merged into the one frame the room draws.
    func pushDiningFrames(_ room: RoomRenderer) {
        let book = cafeBook
        let theme = room.theme
        var changed = book.forceDiningPush
        book.forceDiningPush = false
        if let f = dining.frame(theme: theme) { book.mainFrame = f; changed = true }
        for (i, t) in book.extraTables.enumerated() where i < book.extraFrames.count { if let f = t.frame(theme: theme) { book.extraFrames[i] = f; changed = true } }
        guard changed else { return }
        guard !book.extraTables.isEmpty else { if let f = book.mainFrame { room.setDining(f) }; return }
        let op = RoomMeshBuilder(), tr = RoomMeshBuilder()
        op.material = .plain; tr.material = .plain
        for f in [book.mainFrame] + book.extraFrames { guard let f else { continue }
            DiningModels.append(f.opaque, to: op, transform: matrix_identity_float4x4)
            DiningModels.append(f.translucent, to: tr, transform: matrix_identity_float4x4)
        }
        room.setDining(DiningFrame(opaque: op.mesh, translucent: tr.mesh))
    }

    static func wrapAngle(_ a: Float) -> Float {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }
}
