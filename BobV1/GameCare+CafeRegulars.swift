//
//  GameCare+CafeRegulars.swift
//  The café's guests (cafe-regulars-r1): other Jelmiko at another table, like a real coffee shop. Each visit is rolled (`CafeGuestPlan`): about two visits in three a PAIR of guests takes a second table
//  (already there mid-conversation when the player arrives, or walking in one after the other during the meal), a lone guest in a few, nobody in about one in three. A pair stands at the two ENDS of
//  one table facing each other and talks in place (GameCare+CafeRegularTalk.swift). Who: the player's Park friends first (best friendship first), then the day's visitors (never a special species).
//  Their bodies are the park's visitor bodies (the stage's `parkActors`, made by `parkBook.spawn`). At most `CafeTuning.maxBodies` Jelmiko are on screen (the player's + at most two guests), they
//  keep `regularMargin` from every Jelmiko, never stand in the way of the player's table, and they leave with the café. Autonomy is off; no contact or social code.
//

import Foundation
import simd

/// What the café's second table shows this visit.
nonisolated enum CafeGuestPlan: Equatable, Sendable {
    case nobody, solo, pairHere, pairWalkIn
    /// The shares of a visit with room for two guests: nobody about 3 in 10, one guest alone 1 in 12, a pair about 3 in 5 (half of them already there when the player arrives).
    static let nobodyShare = 0.30, soloShare = 0.08, pairHereShare = 0.31
    var guestCount: Int { switch self { case .nobody: return 0; case .solo: return 1; case .pairHere, .pairWalkIn: return 2 } }
    /// `slots` = how many guests fit (`CafeTuning.regularCount`): 0 = nobody, 1 = nobody or one guest, 2 = the full roll.
    static func roll(slots: Int, using rng: inout some RandomNumberGenerator) -> CafeGuestPlan {
        guard slots >= 1 else { return .nobody }
        let r = Double.random(in: 0..<1, using: &rng)
        if r < nobodyShare { return .nobody }
        if slots == 1 || r < nobodyShare + soloShare { return .solo }
        return r < nobodyShare + soloShare + pairHereShare ? .pairHere : .pairWalkIn
    }
    /// Capture aid (dev arguments only): `-CafeGuestAtP x,z` / `-CafeGuestAtL x,z` put the pair's table (portrait / landscape) at that floor spot instead of the candidates.
    static func forcedSpot(landscape: Bool) -> SIMD2<Float>? {
        guard DevArgs.enabled, let s = UserDefaults.standard.string(forKey: landscape ? "CafeGuestAtL" : "CafeGuestAtP") else { return nil }
        let v = s.split(separator: ",").compactMap { t in Float(t.hasPrefix("m") ? "-" + t.dropFirst() : String(t)) }          // ("m2.3,m3.0" = -2.3,-3.0: a launch value cannot start with a minus)
        return v.count == 2 ? SIMD2(v[0], v[1]) : nil
    }
    /// Capture aid (dev arguments only): `-CafeGuests none|solo|pair|pairwalk`.
    static var forced: CafeGuestPlan? {
        guard DevArgs.enabled, let s = UserDefaults.standard.string(forKey: "CafeGuests") else { return nil }
        switch s { case "none": return .nobody; case "solo": return .solo; case "pair": return .pairHere; case "pairwalk": return .pairWalkIn; default: return nil }
    }
}

/// The visit's guest state (kept in `CafeBook.guests`).
final class CafeGuests {
    var plan: CafeGuestPlan = .nobody
    var table: DiningSet?
    var origin: SIMD2<Float> = .zero
    /// The two stands of the pair's table (the nearer the door first), the yaw each faces, which of the table's places each stands at, and each guest's (by actor id) facing and way-point.
    var stands: [SIMD2<Float>] = [], yaws: [Float] = [], placeOf: [Int] = []
    var yaw: [Int: Float] = [:], waypoint: [Int: SIMD2<Float>] = [:]
    var chat = CafeChatState()
    var back = false
    var isPair: Bool { plan == .pairHere || plan == .pairWalkIn }
    func reset() { plan = .nobody; table = nil; origin = .zero; stands = []; yaws = []; placeOf = []; yaw = [:]; waypoint = [:]; back = false; chat = CafeChatState() }
    nonisolated deinit {}
}


extension GameCare {
    /// How far the pair's two stands are from their table's centre (the player's three use 1.25...1.3).
    static var pairSideX: Float {
        if DevArgs.enabled, UserDefaults.standard.double(forKey: "CafeGuestSide") > 0 { return Float(UserDefaults.standard.double(forKey: "CafeGuestSide")) }          // (capture aid: -CafeGuestSide 0.9)
        return 0.85
    }
    /// The pair keeps this far from the player's bodies (the single guests keep `regularMargin`).
    static let pairMargin: Float = 1.7
    /// A regular keeps at least this far from every Jelbie (centre to centre) when he picks where to stand.
    static let regularMargin: Float = 1.8
    /// Where regulars come in: the door side of the café, just outside the floor.
    static func regularDoor(landscape: Bool) -> SIMD2<Float> { landscape ? SIMD2(4.4, 1.0) : SIMD2(3.7, 1.8) }
    /// Their little tables (floor x, z of the table centre), away from the player's.
    static func regularTables(landscape: Bool) -> [SIMD2<Float>] { landscape ? [SIMD2(2.8, -1.9)] : [SIMD2(2.9, -2.4)] }          // (a lone guest's small table: at the back right, by the counter, like the pair's)
    /// The pair's table (floor x, z of the table centre; the ends stand 1.3 either side of it). Tried in order, the first that is clear of the player's table and bodies.
    static func regularPairTables(landscape: Bool) -> [SIMD2<Float>] { landscape ? [SIMD2(2.8, -2.6)] : [SIMD2(2.7, -3.3)] }          // (the back right, by the counter: background patrons, off the player's rug, clear of the order sheet)

    /// Who the regulars are: the player's Park friends first (best friendship first), then the day's visitors; `count` of them.
    func cafeRegularCast(count: Int) -> [ParkVisitor] {
        let characters = jellies.map(\.character)
        var cast = parkBook.visitors
            .filter { $0.mergedInto == nil && $0.species == nil && $0.bestLevel(among: characters) > .stranger }          // (the special-species visitors are park-only)
            .sorted { $0.bestLevel(among: characters) != $1.bestLevel(among: characters) ? $0.bestLevel(among: characters) > $1.bestLevel(among: characters) : $0.id < $1.id }
        cast = Array(cast.prefix(count))
        if cast.count < count {
            let more = parkBook.chooseCast(count: count, characters: characters, now: Date().timeIntervalSince1970).filter { v in v.species == nil && !cast.contains { $0.id == v.id } }
            cast += more.prefix(count - cast.count)
        }
        return cast
    }

    /// Voice of a regular: the species' own (the signature rule: wings = Lavender, daisy = Moss, spines = Pip, else Bob).
    static func regularVoiceCharacter(_ v: ParkVisitor) -> Int {
        switch v.signature { case .spines: return 1; case .daisy: return 2; case .wings: return 3; default: return 0 }
    }


    /// Dev log of the guests (simulator builds only).
    static func guestLog(_ s: String) {
        #if targetEnvironment(simulator)
        NSLog("[cafe] guests: %@", s)
        #endif
    }

    /// Once per step during the café.
    func tickCafeRegulars(_ actors: [JellyActor], dt: Float) {
        let book = cafeBook, g = book.guests
        // 1. roll the visit (nobody / one guest / a pair that is already there / a pair that walks in), make their bodies (once the guest body at home, if any, is gone), far off the floor until it is their turn
        if book.regularsPending {
            guard guestBook.actor == nil, parkBook.spawn != nil, !actors.isEmpty, actors.allSatisfy({ $0.brain != nil }) else { return }
            book.regularsPending = false
            g.reset()
            var rng = SystemRandomNumberGenerator()
            let slots = CafeTuning.regularCount(owned: actors.count, want: CafeTuning.maxRegulars)
            var plan = CafeGuestPlan.forced ?? CafeGuestPlan.roll(slots: slots, using: &rng)
            if plan.guestCount > slots { plan = slots >= 1 ? .solo : .nobody }
            var cast = plan.guestCount > 0 ? cafeRegularCast(count: plan.guestCount) : []
            if cast.count < plan.guestCount { plan = cast.isEmpty ? .nobody : .solo; cast = Array(cast.prefix(plan.guestCount)) }
            g.plan = plan
            #if targetEnvironment(simulator)
            NSLog("[cafe] guests plan=%@ owned=%d cast=%@", String(describing: plan), actors.count, cast.map { "\($0.id)" }.joined(separator: ","))
            #endif
            guard !cast.isEmpty else { return }
            let bodies = parkBook.spawn?(cast, cast.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) }) ?? []
            guard bodies.count == cast.count else { g.plan = .nobody; return }
            parkBook.actors = bodies; parkBook.cast = cast.map(\.id)
            book.regulars = bodies; book.regularVisitors = cast
            for a in bodies {
                a.sim.arenaRadius = .infinity
                guard let b = a.brain else { continue }
                b.autonomy = false; b.idleBlocked = true
                book.regularState[a.id] = 0
                book.regularWait[a.id] = -1
            }
            if plan == .pairHere { cafeSeatPairAtOnce(actors) }
            return
        }
        guard !book.regulars.isEmpty else { return }
        let landscape = GameCamera.aspect >= 1
        // 2. each guest's turn comes a few seconds apart once the meal is on
        if cafe.phase == .eating || cafe.phase == .cheer || cafe.phase == .lounge || cafe.phase == .done {
            for (k, a) in book.regulars.enumerated() where book.regularWait[a.id] == -1 { book.regularWait[a.id] = 4 + Float(k) * 6 }
        }
        let floors = actors.map(\.floor)
        let pair = g.plan == .pairHere || g.plan == .pairWalkIn
        for (k, (a, v)) in zip(book.regulars, book.regularVisitors).enumerated() {
            guard let b = a.brain else { continue }
            visitorLook(a, v, dt: dt)
            b.autonomy = false; b.idleBlocked = true
            let state = book.regularState[a.id] ?? 0
            if state == 0 {
                guard var w = book.regularWait[a.id], w >= 0 else { continue }
                w -= dt
                if w > 0 { book.regularWait[a.id] = w; continue }
                // in through the door, to a table that is clear of the player's and of every Jelmiko
                var stand: SIMD2<Float>, table: DiningSet
                if pair {
                    guard cafeOpenPairTable(floors: floors, landscape: landscape), let t = g.table, g.stands.indices.contains(k) else { book.regularWait[a.id] = 3; Self.guestLog("no clear pair table for guest \(k)"); continue }          // nothing clear yet: try again in a moment
                    stand = g.stands[k]; table = t
                    g.yaw[a.id] = g.yaws[k]
                    g.waypoint[a.id] = g.back ? SIMD2(3.8, stand.y + 0.9) : SIMD2(stand.x, max(g.origin.y + 1.1, Self.regularDoor(landscape: landscape).y - 0.2))          // (a back table: up the right edge of the room, behind the player's rug, then to the stand; a front table: along the front)
                } else {
                    var spot: SIMD2<Float>?
                    for t in Self.regularTables(landscape: landscape) {
                        let s = t + SIMD2(0, -0.735 + GameCare.eatCloser)
                        let free = simd_distance(t, book.origin) > 2.2 && floors.allSatisfy { simd_distance($0, s) >= Self.regularMargin }
                            && !book.extraTables.contains { simd_distance($0.origin, t) < 2.0 }
                        if free { spot = t; break }
                    }
                    guard let t = spot else { book.regularWait[a.id] = 3; Self.guestLog("no clear single table for guest \(k)"); continue }
                    let tb = DiningSet()
                    tb.registersCollider = false
                    tb.tableSkin = { n in FoodMeshes.mesh(id: "cafetable_\(n)") }
                    tb.spawn(serving: CafePlate.emptyTable, n: 1, bobAt: SIMD2(99, 99), forcedOrigin: t)
                    book.extraTables.append(tb); book.extraFrames.append(nil)
                    stand = t + SIMD2(0, -0.735 + GameCare.eatCloser); table = tb
                    g.yaw[a.id] = -0.5; g.waypoint[a.id] = SIMD2(3.8, stand.y + 0.9)          // (a lone guest faces the room three-quarters, comes in up the right edge)
                }
                if !pair { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }          // (a pair is placed by hand, not bound to the player's floor arena)
                rehome(a, at: Self.regularDoor(landscape: landscape))
                book.regularHome[a.id] = stand; book.regularTable[a.id] = table
                book.regularState[a.id] = 1; book.regularWait[a.id] = nil
                b.restTimer = 0.2
                b.requestNow(.goTo(g.waypoint[a.id] ?? stand))          // (a pair's table: round the front of it, never through it)
                b.face(.happy, hold: 2)
                AudioHub.shared.chirp(character: Self.regularVoiceCharacter(v), .happy, quiet: true)
                continue
            }
            let home = book.regularHome[a.id] ?? .zero
            let idleNow = b.commandedIdle == nil && b.idleState.kind == nil && { if case .none = b.script { return true } else { return false } }() && (b.activity == .idle || b.activity == .lookingAround || b.activity == .steppingInPlace)
            if state == 1 {          // walking in: at his table he turns (a pair: to each other, a single guest: to the room) and a cup is set down with the clink
                if let w = g.waypoint[a.id] {
                    if idleNow, simd_distance(Self.floorPos(b, a.sim), w) < 0.6 { g.waypoint[a.id] = nil; b.requestNow(.goTo(home)) }
                    else if idleNow { b.requestNow(.goTo(w)) }
                    continue
                }
                if idleNow, simd_distance(Self.floorPos(b, a.sim), home) < 0.5 {
                    book.regularState[a.id] = 2
                    b.startTurn(to: g.yaw[a.id] ?? b.faceCameraYaw(), sim: a.sim)
                    cafeSetGuestCups(k: k, a: a)
                    book.regularIdle[a.id] = Float.random(in: 2...4)
                } else if idleNow {
                    b.requestNow(.goTo(home))
                }
                continue
            }
            // settled at the table. A pair that is complete talks in place (below); a lone guest looks around the room, sips, calm idles and goes back to his spot if nudged
            if pair, book.regulars.count == 2, book.regularState.values.filter({ $0 == 2 }).count == 2 { continue }
            guard var t = book.regularIdle[a.id], idleNow else { continue }
            t -= dt
            if t > 0 { book.regularIdle[a.id] = t; continue }
            book.regularIdle[a.id] = Float.random(in: 3...6)
            let facing = g.yaw[a.id] ?? b.faceCameraYaw()
            if simd_distance(Self.floorPos(b, a.sim), home) > 0.4 { b.requestNow(.goTo(home)); book.regularIdle[a.id] = 2.5; continue }
            if abs(Self.wrapAngle(b.yaw - facing)) > 0.6 { b.startTurn(to: facing, sim: a.sim); book.regularIdle[a.id] = 1.2; continue }
            b.commandedIdle = [IdleKind.look, .look, .giggle, .stretch].randomElement()
            if Float.random(in: 0..<1) < 0.35 { AudioHub.shared.chirp(character: Self.regularVoiceCharacter(v), Bool.random() ? .happy : .babble, quiet: true) }          // (a quiet chirp now and then)
            b.face(.happy, hold: 1.5)
            if Float.random(in: 0..<1) < 0.4 { b.blushBump(hold: 2, peak: 0.4) }
        }
        // 3. the pair, once both are at the table: their conversation in place
        if pair, book.regulars.count == 2, book.regulars.allSatisfy({ book.regularState[$0.id] == 2 }) {
            let seats = book.regulars.enumerated().compactMap { k, a -> CafeChatSeat? in
                guard let b = a.brain else { return nil }
                return CafeChatSeat(id: a.id, brain: b, sim: a.sim, skinner: a.skinner, stand: book.regularHome[a.id] ?? .zero, yaw: g.yaw[a.id] ?? 0)
            }
            let voices = Dictionary(uniqueKeysWithValues: zip(book.regulars.map(\.id), book.regularVisitors.map { Self.regularVoiceCharacter($0) }))
            tickCafeChat(seats, state: g.chat, dt: dt) { s, v in AudioHub.shared.chirp(character: voices[s.id] ?? 0, v, quiet: true) }          // (the same conversation as the player's table, a quiet murmur)
        }
        for t in book.extraTables { t.update(dt: dt) }
    }

    /// The guest pair's table (the ENDS table, the one the player's three have): out at once, empty, away from the player's table, the stands at its two ends facing each other. False while nothing is clear.
    @discardableResult
    func cafeOpenPairTable(floors: [SIMD2<Float>], landscape: Bool, quiet: Bool = false) -> Bool {
        let book = cafeBook, g = book.guests
        if g.table != nil { return true }
        for t in (CafeGuestPlan.forcedSpot(landscape: landscape).map { [$0] } ?? Self.regularPairTables(landscape: landscape)) {
            guard simd_distance(t, book.origin) > 2.2 else { continue }
            let table = DiningSet()
            table.registersCollider = false
            table.tableSkin = { n in FoodMeshes.mesh(id: n == 3 ? "cafetable_ends" : "cafetable_\(n)") }
            let saved = (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood, DiningLayout.endsYaw)
            DiningLayout.ends = true; DiningLayout.sideX = Self.pairSideX; DiningLayout.reachFood = false; DiningLayout.endsYaw = DiningLayout.cafeEndsYaw
            AudioHub.hushTableSetup = quiet
            table.spawn(serving: CafePlate.emptyTable, n: 3, bobAt: SIMD2(99, 99), forcedOrigin: t)
            AudioHub.hushTableSetup = false
            if quiet { table.update(dt: 3); table.puffs.reset() }          // (already there: fully out, no puff)
            (DiningLayout.ends, DiningLayout.sideX, DiningLayout.reachFood, DiningLayout.endsYaw) = saved
            var ends = [1, 2].map { i -> (stand: SIMD2<Float>, yaw: Float) in
                let p = table.layout.places[i]
                return (t + p.rel + SIMD2(0, GameCare.eatCloser), p.yaw)
            }
            guard floors.allSatisfy({ f in ends.allSatisfy { simd_distance(f, $0.stand) >= Self.pairMargin } }) else {
                Self.guestLog("pair table at \(t) blocked: nearest body \(floors.flatMap { f in ends.map { simd_distance(f, $0.stand) } }.min() ?? 0) of floors \(floors)")
                table.reset(); continue
            }
            let door = Self.regularDoor(landscape: landscape)
            let back = t.y < book.origin.y - 0.5
            ends.sort { back ? simd_distance($0.stand, door) > simd_distance($1.stand, door) : simd_distance($0.stand, door) < simd_distance($1.stand, door) }          // (a table in front: the first in takes the end nearer the door; a table at the back: the FAR end, so the second never walks past the first)
            g.back = back
            g.table = table; g.origin = t
            g.stands = ends.map(\.stand); g.yaws = ends.map(\.yaw)
            g.placeOf = ends.map { e in e.yaw > 0 ? 1 : 2 }
            book.extraTables.append(table); book.extraFrames.append(nil)
            return true
        }
        return false
    }

    /// A pair that is already there when the player arrives: the table out, both at its ends facing each other, the cups down.
    private func cafeSeatPairAtOnce(_ actors: [JellyActor]) {
        let book = cafeBook, g = book.guests
        guard cafeOpenPairTable(floors: Array(book.stands.values), landscape: GameCamera.aspect >= 1, quiet: true), book.regulars.count == 2 else { g.plan = .pairWalkIn; Self.guestLog("pair not seated at once, walks in"); return }
        for (k, a) in book.regulars.enumerated() {
            g.yaw[a.id] = g.yaws[k]
            book.regularHome[a.id] = g.stands[k]; book.regularTable[a.id] = g.table
            book.regularState[a.id] = 2; book.regularWait[a.id] = nil
            rehome(a, at: g.stands[k])
            a.brain?.startTurn(to: g.yaws[k], sim: a.sim)
            book.regularIdle[a.id] = Float.random(in: 2...4)
        }
        AudioHub.hushTableSetup = true
        cafeSetGuestCups(k: 1, a: book.regulars[1])
        AudioHub.hushTableSetup = false
        g.table?.puffs.reset()
    }

    /// A cup with its straw at each OCCUPIED place of the pair's table only (`CafePlate.cups` sets one at every place).
    static func guestCups(_ byPlace: [Int: CafeTreatID]) -> Consumable {
        let key = byPlace.sorted { $0.key < $1.key }.map { "\($0.key)\($0.value.rawValue)" }.joined(separator: "-")
        return Consumable(id: "cafe-guestcups-\(key)", name: "Café cups", kind: .food, eatStyle: .finger, symbol: "cup.and.saucer.fill", palette: Consumables.cafeCocoa.palette, benefits: [:],
                          serving: { b, _, _, L in
                              for i in 0..<L.n { guard let t = byPlace[i] else { continue }; CafeFoodModels.strawCup(b, L, place: i, treat: CafeMenu.treat(t).category == .drink ? t : .cocoa, sipping: false) }
                          })
    }

    /// The cup(s) on a guest's table: a pair's table shows the cups of whoever has sat down; a lone guest's small table one.
    private func cafeSetGuestCups(k: Int, a: JellyActor) {
        let book = cafeBook, g = book.guests
        let drinks: [CafeTreatID] = [.cocoa, .latte, .juice]
        if g.plan == .pairHere || g.plan == .pairWalkIn {
            var picks: [Int: CafeTreatID] = [:]
            for (j, r) in book.regulars.enumerated() where book.regularState[r.id] == 2 || r === a { if g.placeOf.indices.contains(j) { picks[g.placeOf[j]] = drinks[(j + r.id) % drinks.count] } }
            g.table?.restock(serving: Self.guestCups(picks))
        } else {
            book.regularTable[a.id]?.restock(serving: CafePlate.cups([0: drinks[(k + a.id) % drinks.count]]))
        }
    }

    /// The regulars leave (the café's swap home, under the white): looks put away, bodies hidden, their tables gone.
    func cafeRegularsLeave() {
        let book = cafeBook
        cafeCrowdLeave()
        book.regularsPending = false
        for t in book.extraTables { t.reset() }
        book.extraTables = []; book.extraFrames = []; book.regularTable = [:]; book.forceDiningPush = true
        book.guests.reset()
        guard !book.regulars.isEmpty else { return }
        for a in book.regulars { a.brain?.reserved = false; a.brain?.mealFaceYaw = nil; visitorPutAway(a) }
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
