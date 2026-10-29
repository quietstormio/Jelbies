//
//  GameCare+Volley.swift
//  Jelly Volleyball's glue: the Jelbies of the room (and the visitors who play against them) as the four players of VolleySim, the trip to the beach and back
//  (under the white fade, like the park), the per-step feed of where the soft bodies are and the application of the sim's events to them, the ball as animating
//  decor, and the player's input. The match rules are VolleySim; the moves are BlobBrain+Volley.swift; the trip is VolleyFlow.
//

import Foundation
import QuartzCore
import UIKit
import simd

/// What GameCare keeps while the volleyball trip is on.
@MainActor
final class VolleyWork {
    var wait: (id: Int, mode: VolleyMode, age: Float)?
    var roster: [JellyActor] = []
    /// The bodies of players 0...3 (the human, his partner, the two opponents).
    var players: [JellyActor] = []
    var participants: Set<Int> = []
    var homes: [Int: SIMD2<Float>] = [:]
    var autonomy: [Int: Bool] = [:]
    var arena: [Int: Float] = [:]
    var partnerID: Int?
    var ballShown = false
    var lastScore = [0, 0]
    var pendingSeed: UInt64 = 0
    var ambT: Float = 0
    var demoT: Float = 0
    var rotated = false
    var demoStage = 0
    var slowLeft: Float = 0
    /// Recent ball centres (the trail) and sand puffs (x, z, age seconds, size).
    var trail: [SIMD3<Float>] = []
    var puffs: [(x: Float, z: Float, age: Float, size: Float)] = []
    var nudge: Float = 0
    var captureDone = false
    var gapMin = [Float](repeating: .infinity, count: 2), gapWindow = [Float](repeating: .infinity, count: 2), gapTick = 0
    var gapNote = ["", ""]
    var overlapFrames = [0, 0, 0, 0]
    var overlapTick = 0
    nonisolated deinit {}
}

extension GameCare {
    func wireVolley() {
        volley.onSwap = { [weak self] dest in self?.volleySwap(dest) }
        volley.trophies = race.trophies
        volley.wallet = bath.wallet
        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "VolleyToys"), store.placedDecor.isEmpty {          // capture aid: `-VolleyToys 1` puts a few toys in the room (to see they stay home)
            for k in [DecorKind.soccerball, .duck, .beachball, .plushbear] { store.grant(k.storeID); _ = store.place(k.storeID) }
        }
        #endif
    }

    func volleyHides(_ id: Int) -> Bool { volley.inScene && id < jellies.count && !volleyWork.participants.contains(id) }

    // MARK: asking

    /// The teammate of `id` in a match: the one chosen in the lobby (`VolleyBook.partner`, a character) while he is still in the room and is not `id`, else the first other Jelbie; nil when alone.
    func volleyPartner(for id: Int) -> JellyProfile? {
        if let c = volley.book.partner, let p = jellies.first(where: { $0.character == c && $0.id != id }) { return p }
        return jellies.first { $0.id != id }
    }

    /// The Jelbie sitting out of the team of `id` and his partner: only with three Jelbies. A lobby swap button trades a tile's Jelbie with him; with one or two there is none (no button).
    func volleyBench(for id: Int) -> JellyProfile? {
        guard jellies.count >= 3 else { return nil }
        let p = volleyPartner(for: id)
        return jellies.first { $0.id != id && $0.id != p?.id }
    }

    /// Who plays beside a lone Jelbie today (the same Park visitor all day).
    func volleyParkFriend() -> ParkVisitor { ParkPool.dailyFriend(dayKey: DayClock.shared.dayKey) }

    func volleyBlocker(jelly id: Int) -> String? {
        guard jelly(id) != nil else { return "No such Jelbie." }
        if volley.active || volleyWork.wait != nil { return "A match is already on." }
        if race.active || raceWait != nil { return "He is at the track." }
        if show.active { return "He is at the Jelly Show." }
        if cafe.active || park.active { return "He is out already." }
        if trayOut || meal != nil || wanted != nil { return "A meal is out. Let him finish first." }
        if bath.active { return "The clean-up is going on." }
        if focus.isActive || focus.phase != .roaming { return "He is in the close-up. Let him go first." }
        if raceBook.returner != nil { return "Welcome him home first." }
        if voice.mode.phase != .idle || voice.voiceGoing || voice.comingNow { return "He is listening to you." }
        if !raceBook.actors.isEmpty, !(raceBook.actors.indices.contains(id) && raceBook.actors[id].brain != nil) { return "He is not in the room." }
        return nil
    }
    func canVolley(jelly id: Int) -> Bool { volleyBlocker(jelly: id) == nil }

    #if targetEnvironment(simulator)
    nonisolated(unsafe) static var startVolleyPending = UserDefaults.standard.integer(forKey: "StartVolley") != 0
    nonisolated(unsafe) static var startVolleyFrames = 0
    #endif

    func startVolley(jelly id: Int, mode: VolleyMode, seed: UInt64? = nil) {
        guard canVolley(jelly: id) else { return }
        select.cancel(); queued.removeAll(); callRunning = false
        voice.cancel()
        let sleepers = raceBook.actors.compactMap { $0.brain }.filter { $0.isSleeping }
        let s = seed ?? UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFF
        if !sleepers.isEmpty {
            for b in sleepers { b.commandedGoodnight = false; b.sleepWake(groggy: false, fast: true) }
            volleyWork.wait = (id, mode, 0)
            volleyWork.pendingSeed = s
            for a in raceBook.actors { a.brain?.sleepLocked = true }
            return
        }
        beginVolley(jelly: id, mode: mode, seed: s)
    }

    private func beginVolley(jelly id: Int, mode: VolleyMode, seed: UInt64) {
        guard let prof = jelly(id) else { return }
        var going = [id]
        if case .match = mode, let p = volleyPartner(for: id) { going.append(p.id) }
        if outingGate(going, again: { [weak self] in self?.beginVolley(jelly: id, mode: mode, seed: seed) }) { return }          // they run out of the room first
        let w = volleyWork
        w.pendingSeed = seed
        var partner: JellyProfile?
        if case .match = mode { partner = volleyPartner(for: id) }
        w.partnerID = partner?.id
        var mine = [volley.book.stats(character: prof.character)]
        if let p = partner { mine.append(volley.book.stats(character: p.character)) }
        var sim = VolleySim(mode: mode, mine: mine, seed: seed, firstServe: 0)
        let assist = A11ySettings.shared.raceAssist
        sim.ballSpeedScale = (volley.book.slowBall || A11ySettings.shared.reduceMotion) ? 0.72 : 1
        sim.autoMove = assist == .oneButton || assist == .auto
        sim.autoJump = A11ySettings.shared.autoJump || assist == .auto          // (auto-hit assist: hits go off at Good timing)
        sim.autoSwitch = volley.book.autoSwitch || sim.autoMove          // (one-button mode always switches for you)
        sim.wideWindow = sim.autoMove || A11ySettings.shared.relaxedTiming          // (a wider Perfect window)
        GameCare.volleySlowScale = 1
        volley.assistFactor = assist == .auto ? 0.5 : 1
        volley.trophies = race.trophies
        volley.wallet = bath.wallet
        volley.partnerName = partner?.name ?? ""
        volley.teamNames = [prof.name, partner?.name ?? ""]
        volley.begin(mode: mode, playerID: id, character: prof.character, name: prof.name, sim: sim)
    }

    // MARK: input

    /// The floating joystick in court terms (`VolleyView.stick`): x toward the net (screen up), y across the court (+z, screen right), magnitude 0...1.
    func volleyStick(_ v: SIMD2<Float>) { guard volley.live else { return }; volley.sim?.setStick(v) }
    /// The Hit button went down (serves / tosses on his serve; otherwise bump, set, spike, dig or block by the situation).
    /// `touched`: when the finger landed (the event's own time), so the grade is taken at the touch and not at the next sim step.
    func volleyTap(touched: Date? = nil) {
        guard volley.live else { return }
        var lag: Float = 0
        if let touched, volley.lastStepMedia > 0 {
            let touchMedia = CACurrentMediaTime() - Date().timeIntervalSince(touched)
            lag = Float(touchMedia - volley.lastStepMedia)      // + : the touch came after the last step, so the ball has moved on since
        }
        volley.sim?.tap(lag: lag)
    }
    /// A swipe on the Hit button: where the hit is aimed (nil: auto-aim to the open spot).
    func volleyAim(_ a: SIMD2<Float>?) { guard volley.live else { return }; volley.sim?.setAim(a) }
    /// Double-tap on one of your two Jelbies.
    func volleySwitch(to i: Int) { guard volley.live else { return }; volley.sim?.switchTo(i, manual: true); volley.refreshUI() }

    // MARK: the world swaps (under the white)

    private func volleySwap(_ dest: VolleyFlow.Dest) {
        let w = volleyWork
        switch dest {
        case .beach:
            w.roster = raceBook.actors
            guard !w.roster.isEmpty else { return }
            let pid = volley.playerID
            var parts: [Int] = [pid]
            if let p = w.partnerID { parts.append(p) }
            w.participants = Set(parts)
            w.homes = [:]; w.autonomy = [:]; w.arena = [:]
            for a in w.roster {
                guard let b = a.brain else { continue }
                w.homes[a.id] = a.floor; w.autonomy[a.id] = b.autonomy; w.arena[a.id] = a.sim.arenaRadius
                b.abortAll(a.sim, a.skinner)
                b.commandedIdle = nil; b.commandedDecor = nil; b.commandedFlip = false
                b.autonomy = false
            }
            RoomLayout.apply(RoomCatalog.beach)
            GameCamera.configureBeach()
            syncDecor()
            // the visitors: the opponents (and a partner when the Jelbie plays alone)
            var bodies: [JellyActor] = [w.roster[pid]]
            var names: [String] = []
            if case .match = volley.mode {
                var rng = ParkRandom(w.pendingSeed &+ 77)
                let friend = volleyParkFriend()
                var pool = ParkPool.generate().filter { $0.id != friend.id }
                for i in stride(from: pool.count - 1, to: 0, by: -1) { pool.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
                let specs = (w.partnerID == nil ? [friend] : []) + Array(pool.prefix(2))
                let vis = parkBook.spawn?(specs, specs.indices.map { SIMD2<Float>(40 + Float($0) * 3, 0) }) ?? []
                if let p = w.partnerID { bodies.append(w.roster[p]) } else if let v = vis.first { bodies.append(v) }
                let opp = w.partnerID == nil ? Array(vis.dropFirst()) : vis
                bodies.append(contentsOf: opp.prefix(2))
                names = specs.suffix(2).map(\.name)
                if w.partnerID == nil, let s = specs.first { volley.partnerName = s.name }
            }
            volley.opponentNames = names
            w.players = bodies
            for (i, a) in bodies.enumerated() {
                let team = i / 2
                let x = volley.isDrill ? Float(volley.mode == .drill(.block) ? -1.2 : -1.5) : VolleyTuning.startX[min(i, 3)]
                let z = volley.isDrill ? Float(0) : VolleyTuning.startZ[min(i, 3)]
                a.sim.arenaRadius = .infinity
                rehome(a, at: SIMD2(x, z))
                a.brain?.volleyBegin(sim: a.sim, skinner: a.skinner, x: x, z: z, side: team == 0 ? 1 : -1)
                a.skinner.jelly.reset()
            }
            w.lastScore = [0, 0]
        case .home:
            GameCare.volleySlowScale = 1; w.slowLeft = 0
            for a in w.players { a.brain?.volleyEnd(sim: a.sim, skinner: a.skinner) }
            parkBook.clear?()
            RoomLayout.apply(RoomCatalog.def(store.currentRoom))
            GameCamera.endBeach(count: max(jellies.count, 1))
            if GameCamera.refreshRoam(aspect: GameCamera.aspect) != nil {
                for a in w.roster where (w.arena[a.id] ?? a.sim.arenaRadius).isFinite { a.sim.arenaCenter = GameCamera.arenaCenter; a.sim.arenaRadius = GameCamera.arenaRadius }
            }
            syncDecor()
            var taken: [SIMD2<Float>] = []
            for a in w.roster {
                guard let brain = a.brain else { continue }
                var spot = w.homes[a.id] ?? Self.greetSpot(a.id)
                if taken.contains(where: { simd_distance($0, spot) < 1.5 }) {
                    spot = [SIMD2<Float>(-1.6, 0.4), SIMD2(1.6, 0.4), SIMD2(0, -1.0), SIMD2(-1.8, -1.2)].first { s in !taken.contains { simd_distance($0, s) < 1.5 } } ?? spot
                }
                spot = brain.fixed(spot)
                taken.append(spot)
                rehome(a, at: spot)
                brain.autonomy = w.autonomy[a.id] ?? true
                brain.idleBlocked = false
                brain.restTimer = 2
                a.sim.arenaRadius = w.arena[a.id] ?? a.sim.arenaRadius
            }
            w.participants = []; w.players = []
        }
    }

    // MARK: per fixed step

    func tickVolley(_ actors: [JellyActor], dt: Float) {
        let w = volleyWork
        #if targetEnvironment(simulator)
        if Self.startVolleyPending, !volley.active, w.wait == nil {          // capture aid: `-StartVolley 1` match, `2` bonk drill, `3` spike drill, `4` sprints
            Self.startVolleyFrames += 1
            if Self.startVolleyFrames > 120 {
                Self.startVolleyPending = false
                let k = UserDefaults.standard.integer(forKey: "StartVolley")
                startVolley(jelly: 0, mode: k == 2 ? .drill(.bonk) : k == 3 ? .drill(.spike) : k == 4 ? .drill(.sprint) : .match(volley.book.chosen), seed: UInt64(max(UserDefaults.standard.integer(forKey: "VolleySeed"), 1)))
            }
        }
        #endif
        if var wt = w.wait {
            wt.age += dt
            let sleeping = actors.filter { $0.brain?.isSleeping ?? false }
            if wt.age > 1.5, wt.age.truncatingRemainder(dividingBy: 1) < dt { for a in sleeping { a.brain?.sleepWake(groggy: false, fast: true) } }
            if wt.age > 8 { for a in sleeping { if let b = a.brain { b.abortAll(a.sim, a.skinner); b.idleReset(a.skinner) } } }
            if sleeping.isEmpty || wt.age > 8.5 { w.wait = nil; beginVolley(jelly: wt.id, mode: wt.mode, seed: w.pendingSeed) } else { w.wait = wt }
        }
        volley.step(dt: dt)
        guard volley.active else { return }
        for a in actors { a.brain?.sleepLocked = true }
        guard volley.inScene, var s = volley.sim, !w.players.isEmpty else { return }
        // the ambience under the music
        w.ambT += dt
        if w.ambT > 1 { w.ambT = 0; AudioHub.shared.beachAmbience(volley.phase != .leaveOut) }
        if volley.phase != .playing {
            for (i, a) in w.players.enumerated() where i < s.players.count { a.brain?.volleyWant(x: s.players[i].x, z: s.players[i].z, speed: s.players[i].stats.speed) }
            return
        }
        // where the soft bodies are
        for (i, a) in w.players.enumerated() where i < s.players.count {
            guard let b = a.brain else { continue }
            let sb = a.sim, c = sb.centroid()
            var top: Float = 0
            s.setSamples(i) { arr in
                arr.removeAll(keepingCapacity: true)
                var p = 0
                while p < sb.n { let y = sb.x[3 * p + 1]; arr.append(SIMD2(sb.x[3 * p], y)); top = max(top, y); p += 4 }
            }
            s.setBody(i, x: c.x, z: c.z, lift: max(0, c.y - sb.restCentroid.y), top: top, grounded: b.volley.phase != .air)
            if b.volley.finished { s.bodyDone(i) }
            else if b.volley.phase == .ground, s.players[i].act != .stand, s.players[i].actT > 0.3 { s.bodyDone(i) }
        }
        for team in 0..<2 where w.players.count >= 4 && s.players.count >= 4 && VolleyTuning.keepApart {          // each Jelbie knows where his partner's body is (his steps, jumps and dives keep clear of it)
            let a = team * 2, b = a + 1
            w.players[a].brain?.volley.mate = SIMD2(s.players[b].x, s.players[b].z)
            w.players[b].brain?.volley.mate = SIMD2(s.players[a].x, s.players[a].z)
        }
        #if targetEnvironment(simulator)
        volleyDemo(&s)
        volleyGapAid(s)
        if UserDefaults.standard.object(forKey: "VolleyLandscape") != nil, !w.rotated {          // capture aid: `-VolleyLandscape 1` the court on its side, `0` upright again
            w.rotated = true
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.requestGeometryUpdate(.iOS(interfaceOrientations: UserDefaults.standard.bool(forKey: "VolleyLandscape") ? .landscapeRight : .portrait))
        }
        #endif
        #if targetEnvironment(simulator)
        volleyOverlapAid(s)
        #endif
        s.tick(dt: dt)
        let events = s.takeEvents()
        for (i, a) in w.players.enumerated() where i < s.players.count { a.brain?.volleyWant(x: s.players[i].wantX, z: s.players[i].wantZ, speed: s.players[i].stats.speed) }
        for e in events { applyVolley(e, &s) }
        // the slow beat of a match-point spike (real time: 0.6 s at 0.3x)
        if w.slowLeft > 0 { w.slowLeft -= dt / max(GameCare.volleySlowScale, 0.1); if w.slowLeft <= 0 { GameCare.volleySlowScale = 1 } }
        volley.bodyPos = w.players.enumerated().compactMap { i, a in i < s.players.count ? SIMD3(s.players[i].x, s.players[i].top, s.players[i].z) : nil }
        volley.sim = s
        volley.lastStepMedia = CACurrentMediaTime()
        // juice state: the trail of a fast ball, ageing sand puffs, the camera's drift toward the action
        let reduce = A11ySettings.shared.reduceMotion
        if hypot(s.ball.vel.x, s.ball.vel.y) > 5.5, s.phase == .rally, !reduce { w.trail.append(SIMD3(s.ball.pos.x, s.ball.pos.y, s.ball.z)); if w.trail.count > 6 { w.trail.removeFirst() } }
        else if !w.trail.isEmpty { w.trail.removeFirst() }
        for k in w.puffs.indices { w.puffs[k].age += dt }
        w.puffs.removeAll { $0.age > 0.6 }
        let want: Float = reduce ? 0 : max(-0.2, min(0.2, s.ball.z * 0.12))          // (the screen's right is +z now)
        w.nudge += (want - w.nudge) * min(1, dt * 1.5)
        GameCamera.beachNudge = w.nudge
        if s.phase == .over { volley.settle() }
        volley.refreshUI()
    }

    private func applyVolley(_ e: VolleyEvent, _ s: inout VolleySim) {
        let w = volleyWork
        func body(_ i: Int) -> JellyActor? { w.players.indices.contains(i) ? w.players[i] : nil }
        let now = CACurrentMediaTime()
        #if targetEnvironment(simulator)
        if UserDefaults.standard.object(forKey: "VolleyLog") != nil { print("VOLLEYEV \(e)") }
        #endif
        switch e {
        case .jump(let i, let dx, let dz, let apex, let block): if let a = body(i) { a.brain?.volleyJump(sim: a.sim, dx: dx, dz: dz, apex: apex, block: block) }
        case .spike(let i): body(i)?.brain?.volleySpike()
        case .dive(let i, let dir):
            if let a = body(i) { a.brain?.volleyDive(sim: a.sim, dir: dir) }
            if s.players.indices.contains(i) { w.puffs.append((s.players[i].x + dir * 0.5, s.players[i].z, 0, 1.0)) }
        case .serveToss: AudioHub.shared.play(.whistle, volume: 0.35, rate: 1.3)
        case .contact(let i, let kind, let quality, let point, let normal, let speed):
            guard let a = body(i) else { return }
            a.brain?.volleyImpact(sim: a.sim, kind: kind, quality: quality, ball: point + normal * VolleyTuning.ballR * 0.65, normal: normal, speed: speed)
            let big = kind == .spike || kind == .block
            AudioHub.shared.play(big ? .volleySpike : .volleyBonk, jelly: a.id, x: point.x, volume: min(1.1, 0.6 + speed * 0.08))
            if i == s.controlled { touchPlay?.haptics.transient(now: now, intensity: big ? 0.9 : quality == .perfect ? 0.8 : 0.6, sharpness: big ? 0.7 : 0.4) }
        case .perfectTap(let i):
            if i == s.controlled {
                AudioHub.shared.play(.select, volume: 0.55, rate: 2.0)
                touchPlay?.haptics.transient(now: now, intensity: 0.9, sharpness: 0.9)
            }
        case .switched(let to, let auto):
            AudioHub.shared.play(.select, volume: 0.5, rate: 1.4)
            touchPlay?.haptics.transient(now: now, intensity: 0.45, sharpness: 0.6)
            let name = volley.teamNames.indices.contains(to) && !volley.teamNames[to].isEmpty ? volley.teamNames[to] : "your teammate"
            A11yEvents.say("Control switched to \(name)", .normal)
            _ = auto
        case .call(let i):
            AudioHub.shared.play(.select, volume: 0.35, rate: 1.9)
            volley.callUntil[i] = now + 1.1
        case .feedback(let text, let tone):
            if tone == 1 || tone == 3 { A11yEvents.say(text, .low) }
        case .combo:
            AudioHub.shared.play(.sparkle, volume: 0.9)
            AudioHub.shared.play(.cheerSmall, volume: 0.6)
            touchPlay?.haptics.transient(now: now, intensity: 1.0, sharpness: 0.8)
        case .slowMo:
            if !A11ySettings.shared.reduceMotion { GameCare.volleySlowScale = 0.3; w.slowLeft = 0.6 }
        case .touchCount(let team, let count):
            if team == 0 { A11yEvents.say("Touch \(count) of 3", .low) }
        case .fault: AudioHub.shared.play(.whistle, volume: 0.5)
        case .bounce(let x):
            AudioHub.shared.play(.volleyLand, x: x, volume: 0.6)
            w.puffs.append((x, s.ball.z, 0, 0.7))
        case .net: AudioHub.shared.play(.wobble, volume: 0.5)
        case .point(let team, let out):
            AudioHub.shared.play(.volleyPoint)
            AudioHub.shared.play(.whistle, volume: 0.5)
            A11yEvents.say(String(format: "%@%@. %d to %d", team == 0 ? "Point for you" : "Point for them", out ? ", out" : "", s.score[0], s.score[1]), .high)
        case .cheer(let team):
            for (i, a) in w.players.enumerated() where i / 2 == team { a.brain?.volleyCheer(sim: a.sim) }
        case .serveReady(let p):
            if p < 2 { A11yEvents.say("Your serve. Tap Hit to toss, tap again at the top", .normal) }
        case .matchOver: AudioHub.shared.play(.cheerSmall)
        case .drillHit(let good): AudioHub.shared.play(good ? .statUp : .stumble, volume: 0.6)
        case .flag: AudioHub.shared.play(.goodStep)
        case .drillBall, .drillOver: break
        }
    }

    // MARK: the ball (animating decor)

    func refreshVolleyBall(_ room: RoomRenderer) -> Bool {
        let w = volleyWork
        guard volley.inScene, let s = volley.sim else {
            if w.ballShown { room.setDecorActive(RoomMesh()); w.ballShown = false }
            return false
        }
        let b = RoomMeshBuilder()
        b.material = .plain
        func add(_ m: RoomMesh) {
            let off = UInt32(b.mesh.vertices.count)
            b.mesh.vertices.append(contentsOf: m.vertices); b.mesh.indices.append(contentsOf: m.indices.map { $0 + off })
        }
        if s.drillKind != .sprint {
            VolleyBallMesh.shadow(x: s.ball.pos.x, z: s.ball.z, height: s.ball.pos.y, into: b)
            if let r = s.ring, s.phase == .rally { VolleyBallMesh.timingRing(r, time: s.clock, into: b) }
            add(VolleyBallMesh.build(centre: SIMD3(s.ball.pos.x, s.ball.pos.y, s.ball.z), spin: s.ball.spin))
            if !w.trail.isEmpty { VolleyBallMesh.trail(w.trail, into: b) }
        }
        if s.drillKind == .spike {
            for (k, x) in s.cushions.enumerated() {
                let target = k == s.targetCushion
                b.roundedBox(centre: SIMD3(x, 0.10, 0), half: SIMD3(0.42, 0.10, 0.42), radius: 0.09, segments: 3, aoFloor: false,
                             color: target ? ParkShapes.srgb(0.98, 0.50, 0.58) : ParkShapes.srgb(0.99, 0.94, 0.82))
            }
        }
        if s.drillKind == .sprint {
            for (k, pt) in s.flags.enumerated() where k >= s.flagIndex {
                let cur = k == s.flagIndex
                let col = cur ? ParkShapes.srgb(0.98, 0.50, 0.58) : ParkShapes.srgb(0.86, 0.90, 0.95)
                b.roundedBox(centre: SIMD3(pt.x, 0.45, pt.y), half: SIMD3(0.025, 0.45, 0.025), radius: 0.02, segments: 2, aoFloor: false, color: ParkShapes.srgb(0.96, 0.94, 0.88))
                b.roundedBox(centre: SIMD3(pt.x + 0.17, 0.78, pt.y), half: SIMD3(cur ? 0.19 : 0.13, cur ? 0.1 : 0.07, 0.015), radius: 0.015, segments: 2, aoFloor: false, color: col)
            }
        }
        for pf in w.puffs { VolleyBallMesh.puff(x: pf.x, z: pf.z, age: pf.age / 0.6, size: pf.size, into: b) }
        // the control ring under the Jelbie you steer, and an arrow over him
        if !s.isDrill, s.phase != .over, s.players.indices.contains(s.controlled) {
            let p = s.players[s.controlled]
            VolleyBallMesh.controlMark(x: p.x, z: p.z, top: p.top, time: s.clock, into: b)
        }
        room.setDecorActive(b.mesh)
        w.ballShown = true
        return true
    }
}

extension GameCare {
    /// Capture aid (the simulator only): `-VolleySlow 0.15` slows the court's time; `-VolleyDemo bonk|spike|dig|serve|cheer` plays one move over and over for the review sheet.
    nonisolated(unsafe) static let volleyTimeScale: Float = { let v = Float(UserDefaults.standard.double(forKey: "VolleySlow")); return v > 0 ? v : 1 }()
    /// The match-point slow beat (0.3 for a moment), multiplied into the court's time.
    nonisolated(unsafe) static var volleySlowScale: Float = 1

    #if targetEnvironment(simulator)
    /// Where the capture aids print: the file named by `-VolleyAidLog <path>` (appended to), else stderr.
    func volleyAidLog(_ line: String) {
        if let path = UserDefaults.standard.string(forKey: "VolleyAidLog") {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        } else { FileHandle.standardError.write(Data(line.utf8)) }
    }

    /// Capture aid: `-VolleyGap 1` tracks the least centre-to-centre distance of each team's two real soft bodies (a body is ~1.1 wide) and prints it every 2 s, with the
    /// wall-clock time of each second's closest moment when it is under 1.8 (to find the frames in a screen recording).
    func volleyGapAid(_ sim: VolleySim) {
        guard UserDefaults.standard.bool(forKey: "VolleyGap"), volley.bodyPos.count >= 4 else { return }
        let w = volleyWork
        for team in 0..<2 {
            let a = volley.bodyPos[team * 2], b = volley.bodyPos[team * 2 + 1]
            let d = hypotf(a.x - b.x, a.z - b.z)
            w.gapMin[team] = min(w.gapMin[team], d)
            if d < w.gapWindow[team], sim.players.count >= 4 {
                let p = sim.players[team * 2], q = sim.players[team * 2 + 1]
                w.gapNote[team] = "acts \(p.act)/\(q.act) bodies (\(a.x), \(a.z)) (\(b.x), \(b.z)) wants (\(p.wantX), \(p.wantZ)) (\(q.wantX), \(q.wantZ)) phase \(sim.phase)"
            }
            w.gapWindow[team] = min(w.gapWindow[team], d)
        }
        w.gapTick += 1
        if w.gapTick % 60 == 0 {
            for team in 0..<2 where w.gapWindow[team] < 1.8 { volleyAidLog("VOLLEYCLOSE t=\(Date().timeIntervalSince1970) team=\(team) d=\(w.gapWindow[team]) \(w.gapNote[team])\n") }
            w.gapWindow = [.infinity, .infinity]
        }
        if w.gapTick % 120 == 0 { volleyAidLog("VOLLEYGAP min ours=\(w.gapMin[0]) theirs=\(w.gapMin[1]) (body width 1.1)\n") }
    }

    /// Capture aid: `-VolleyOverlap 1` counts, while a rally is on, the frames where two teammates' screen boxes overlap by more than 30% (per team) and prints the totals every 2 s.
    func volleyOverlapAid(_ s: VolleySim) {
        guard UserDefaults.standard.bool(forKey: "VolleyOverlap"), s.phase == .rally, volley.bodyPos.count >= 4 else { return }
        let w = volleyWork, size = CGSize(width: 1206, height: 2622)
        for team in 0..<2 {
            let a = volley.bodyPos[team * 2], b = volley.bodyPos[team * 2 + 1]
            if let o = VolleyView.overlap(a, b, size: size) { w.overlapFrames[team * 2] += 1; if o > 0.3 { w.overlapFrames[team * 2 + 1] += 1 } }
        }
        w.overlapTick += 1
        if w.overlapTick % 120 == 0 { volleyAidLog("VOLLEYOVERLAP frames=\(w.overlapFrames[0]) over30=\(w.overlapFrames[1]) (our team)  frames=\(w.overlapFrames[2]) over30=\(w.overlapFrames[3]) (theirs)\n") }
    }

    func volleyDemo(_ s: inout VolleySim) {
        guard let k = UserDefaults.standard.string(forKey: "VolleyDemo"), s.players.indices.contains(s.controlled) else { return }
        let w = volleyWork
        let p = s.players[s.controlled]
        switch k {
        case "rally":          // both teams play themselves (the assists), for the review frames
            s.autoMove = true; s.autoJump = true
            if s.waitingToServe, s.servingPlayer == s.controlled { s.tap() }          // (his own serve: toss, then the serve at the top)
            if s.phase == .rally, p.act == .stand, let r = s.ring, abs(r.tau - r.lead) < 0.03, s.hitLabel == "Serve!" { s.tap() }
        case "bonk", "spike":
            guard s.phase == .rally else { return }
            let b = s.ball
            s.setStick(SIMD2(max(-1, min(1, (b.pos.x - p.x) / 0.9)), max(-1, min(1, (b.z - p.z) / 0.9))))
            if p.act == .stand, let r = s.ring, abs(r.tau - r.lead) < 0.03 { s.tap() }
        case "dig":
            guard s.phase == .rally else { return }
            if !w.ballShown || s.clock - w.demoT > 4.5 { w.demoT = s.clock; w.demoStage = 0 }
            if w.demoStage == 0, p.act == .stand, s.clock - w.demoT > 0.2 { s.debugBall(pos: SIMD2(p.x + 0.9, 1.5), vel: SIMD2(-0.1, -0.5), z: p.z); w.demoStage = 1 }
            if w.demoStage == 1, s.ball.pos.y < 1.2, p.act == .stand { s.tap(); w.demoStage = 2 }
        case "serve":
            if s.waitingToServe, s.servingPlayer == s.controlled { s.tap() }
            if s.phase == .rally, p.act == .stand, let r = s.ring, abs(r.tau - r.lead) < 0.03 { s.tap() }
        case "cheer":
            if s.waitingToServe, s.servingPlayer == s.controlled { s.tap() }
            if s.phase == .rally, s.clock - w.demoT > 3 { w.demoT = s.clock; s.forcePoint(team: 0) }
        default: break
        }
    }
    #endif
}
