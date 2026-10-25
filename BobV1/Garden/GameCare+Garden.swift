//
//  GameCare+Garden.swift
//  The Garden's care layer: the growth clock, a tap on a plot (plant / water / harvest), what the harvest gives, handing the renderer its meshes, and the
//  Jelbies' garden visits (GardenLife.swift). Growth runs even while the Jelbies live somewhere else; the picture and the visits only while the Garden is home.
//

import Foundation
import simd
import QuartzCore

extension GameCare {
    private static var nowSeconds: Double { Date().timeIntervalSince1970 }

    /// The Garden is what is on screen (the home, and no outing / Clean has replaced it).
    var gardenShown: Bool { roomID == .garden && !tripActive && !roomSwitch.active }

    /// A plot tap is welcome now (nothing else has the screen).
    var gardenAcceptsTaps: Bool {
        gardenShown && !bath.active && !focus.isActive && !arranging && !trayOut && dining.phase == .absent && !groupActive && !PhotoMode.shared.active
    }

    // MARK: clock (every fixed step, from tickDecor)

    func tickGarden(dt: Float) {
        garden.clock += dt
        if garden.clock >= 1 { garden.clock = 0; garden.tick(now: Self.nowSeconds) }
        if roomID == .garden { tickGardenLife(dt: dt) } else if garden.life.visit != nil { garden.life.visit = nil }
    }

    // MARK: taps

    /// A tap on plot `i`.
    func gardenTapped(plot i: Int) {
        guard gardenAcceptsTaps else { return }
        let now = Self.nowSeconds
        garden.tick(now: now)
        switch garden.stage(i) {
        case 0:
            AudioHub.shared.uiTap()
            garden.pickerPlot = i
        case 3:
            harvestGarden(i)
        default:
            if garden.water(i, now: now) {
                AudioHub.shared.play(.splash)
                let hrs = Int(GardenTuning.waterSeconds / 3600)
                garden.say("Watered! It grows for the next \(hrs) hours.", now: now)
                gardenHelper(at: i)
            } else {
                AudioHub.shared.uiTap()
                garden.say("Still plenty wet. Come back later.", now: now)
            }
        }
    }

    /// Plants `k` in plot `i`, spending one seed packet.
    @discardableResult
    func plantGarden(_ k: GardenPlant, at i: Int) -> Bool {
        let now = Self.nowSeconds
        guard garden.plots.indices.contains(i), garden.plots[i].plant == nil, store.use(k.seedID) else { AudioHub.shared.play(.notEnough); return false }
        garden.plant(k, at: i, now: now)
        garden.pickerPlot = nil
        AudioHub.shared.play(.sparkle)
        garden.say("Planted! Tap it to water.", now: now)
        return true
    }

    /// The bag's "Plant" button: the first empty plot.
    func plantFromBag(_ seedID: String) {
        guard let k = GardenPlant.allCases.first(where: { $0.seedID == seedID }), let i = garden.firstEmpty() else { return }
        plantGarden(k, at: i)
    }

    private func harvestGarden(_ i: Int) {
        let now = Self.nowSeconds
        guard let k = garden.harvest(i, now: now) else { return }
        AudioHub.shared.play(.perkSparkle)
        if let food = k.harvestFood {
            store.grant(food, GardenTuning.servings)
            garden.say("Picked \(GardenTuning.servings) \(k.title.lowercased()) servings. They are in the bag!", now: now)
        } else {
            for j in jellies { j.perks.grant(.cozy, duration: GardenTuning.cozySeconds) }
            garden.say("You smell the \(k.title.lowercased())s. Everyone feels cozy!", now: now)
        }
        gardenHelper(at: i)
    }

    // MARK: renderer

    /// After the frame's last step (the stage calls it next to `refreshDecor`).
    func refreshGarden(renderer: MelonRenderer?, time: Float) {
        guard let room = renderer?.room else { return }
        if gardenShown {
            let now = Self.nowSeconds
            if !garden.drawnShown || garden.drawnRevision != garden.revision {
                room.setGardenPlants(GardenPlants.build(garden, now: now))
                garden.drawnRevision = garden.revision; garden.drawnShown = true
            }
            let ripe = (0..<GardenTuning.plotCount).filter { garden.stage($0) == 3 }
            room.setGardenLive(GardenLive.build(t: time, night: room.daylight.lamp.w, ripe: ripe, can: garden.canActive(now: now)))
        } else if garden.drawnShown {
            room.setGardenPlants(RoomMesh()); room.setGardenLive(RoomMesh())
            garden.drawnShown = false; garden.drawnRevision = -1
        }
    }

    // MARK: the Jelbies' visits

    private var gardenBusy: Bool {
        !gardenShown || roomActivityBlocker() != nil || PhotoMode.shared.active || select.phase != .none || tripActive || bath.active || focus.isActive
    }

    /// Whether Jelbie `a` is calm enough to be sent somewhere.
    private func gardenCalm(_ a: JellyActor) -> Bool {
        guard let b = a.brain else { return false }
        return b.autonomy && b.activity == .idle && b.idleState.kind == nil && b.pending == nil && !b.commanded && b.commandedIdle == nil
            && b.social == nil && !b.held && !b.isSleeping && !b.interruptScript && !b.commandedFlip
    }

    /// The nearest calm Jelbie hops over when you water or pick (the existing jump for joy).
    func gardenHelper(at plot: Int) {
        guard gardenShown, garden.life.visit == nil else { return }
        let p = GardenLayout.plotCentre(plot)
        let target = SIMD2<Float>(p.x, -2.85)
        let cands = raceBook.actors.enumerated().filter { gardenCalm($0.element) }
        guard let best = cands.min(by: { simd_distance($0.element.floor, target) < simd_distance($1.element.floor, target) }) else { return }
        startVisit(actor: best.offset, spot: target, move: .joy, activity: .help)
    }

    private func startVisit(actor: Int, spot: SIMD2<Float>, move: IdleKind, activity: GardenActivity) {
        guard raceBook.actors.indices.contains(actor), let brain = raceBook.actors[actor].brain else { return }
        let q = brain.fixed(spot)
        guard simd_distance(q, spot) < 0.6 else { return }
        for (k, o) in raceBook.actors.enumerated() where k != actor && simd_distance(o.floor, q) < 1.1 { return }
        brain.requestNow(.goTo(q))
        garden.life.visit = GardenLifeState.Visit(actor: actor, spot: q, move: move)
        garden.life.last = activity
    }

    func tickGardenLife(dt: Float) {
        var life = garden.life
        defer { garden.life = life }
        if gardenBusy { life.visit = nil; life.cooldown = max(life.cooldown, 8); return }
        if var v = life.visit {
            guard raceBook.actors.indices.contains(v.actor), let brain = raceBook.actors[v.actor].brain else { life.visit = nil; return }
            v.waited += dt
            let here = raceBook.actors[v.actor].floor
            let near = simd_distance(here, v.spot) < 0.45
            let stopped = v.waited > 1.5 && brain.pending == nil && brain.activity == .idle && simd_distance(here, v.spot) < 0.9
            if near || stopped {
                brain.commandedIdle = v.move
                life.visit = nil
                life.cooldown = Float.random(in: 28...55)
            } else if v.waited > 16 || brain.commanded {
                life.visit = nil; life.cooldown = 12
            } else { life.visit = v }
            return
        }
        life.cooldown -= dt
        guard life.cooldown <= 0 else { return }
        life.cooldown = Float.random(in: 20...40)
        let cands = raceBook.actors.enumerated().filter { gardenCalm($0.element) }
        guard let pick = cands.randomElement() else { return }
        let night = DayLight.at(hour: DayClock.shared.displayHour).lamp.w
        let t = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
        var options: [(GardenActivity, SIMD2<Float>, IdleKind)] = [
            (.sniff, SIMD2(GardenLayout.bedA.x + 1.45, GardenLayout.bedA.y + 0.2), .look),
            (.sniff, SIMD2(GardenLayout.bedB.x - 1.45, GardenLayout.bedB.y + 0.1), .look),
            (.sniff, SIMD2(-0.9, -2.95), .look),
            (.splash, SIMD2(GardenLayout.birdBath.x + 1.1, GardenLayout.birdBath.y + 0.5), .bounce),
        ]
        if night < 0.45 {
            let i = Int.random(in: 0..<GardenLive.butterflyCount)
            let bf = GardenLive.butterfly(i, t: t + 4)
            options.append((.chase, SIMD2(min(max(bf.x, -3.0), 3.0), min(max(bf.z, -2.0), 1.8)), .joy))
            options.append((.sunbathe, SIMD2(GardenLayout.deck.min.x + 0.7, GardenLayout.deck.min.y + 1.5), .lieDown))
        }
        let choices = options.filter { $0.0 != life.last }
        guard let o = (choices.isEmpty ? options : choices).randomElement() else { return }
        garden.life = life
        startVisit(actor: pick.offset, spot: o.1, move: o.2, activity: o.0)
        life = garden.life
    }
}
