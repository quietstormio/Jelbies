//
//  GameCare+Decor.swift
//  The store's decor in the room: keeps the live field (Room/DecorModel.swift) in step with what the player placed, ticks the animations (a sat-in
//  beanbag, a booped plant, the ball), feeds the room renderer (resting pieces join the cached room, animating ones are drawn per frame), and the
//  Place / drag / Put away flow of the Bag. Positions are saved in the StoreBook. Decor is earned and bought with Drops like everything else.
//

import Foundation
import QuartzCore
import UIKit
import simd

/// What the room last drew for the decor.
struct DecorDrawn {
    var storeRevision = -1
    var cafeHidden = false
    var fieldVersion = -1
    var active: Set<Int> = []
    var activeShown = false
}

extension GameCare {
    /// The placed pieces reach the field (and so the walk resolver and the Jellies) the moment the store changes.
    func syncDecor() {
        let hide = cafe.hidesDecor          // in the café the room's furniture is away (it is not that room)
        if store.revision != decorDrawn.storeRevision || hide != decorDrawn.cafeHidden {
            decorDrawn.storeRevision = store.revision; decorDrawn.cafeHidden = hide
            DecorField.shared.set(hide ? [] : store.placedDecor)
        }
    }

    /// Once per fixed step (the stage calls it with every Jelly ticked).
    func tickDecor(dt: Float) {
        tickRoomSwitch(dt: dt)
        syncDecor()
        let f = DecorField.shared
        guard !f.feet.isEmpty else { return }
        f.bodies = raceBook.actors.compactMap { a in a.brain.map { (id: $0.steerID, pos: $0.position) } }          // (the soccer ball bumps off them gently)
        f.tick(dt: dt)
        if var w = arrangeWait {                 // a double tap on a piece in use: wait for the Jelly to hop off (at most ~4 s), then pick it up
            w.left -= dt
            if !decorBusy(w.uid) { arrangeWait = nil; startArrange(on: w.uid) }
            else if w.left <= 0 { arrangeWait = nil }
            else { arrangeWait = w }
        }
        if !arranging, let r = f.restingBall() { store.setPosition(r.uid, r.at) }          // the ball stays where it stopped
    }

    /// After the frame's last step: rebuilds the decor mesh when a piece was added / moved / put away or started or stopped animating, and every frame
    /// while one animates.
    func refreshDecor(renderer: MelonRenderer?, time: Float) {
        guard let room = renderer?.room else { return }
        syncDecor()
        let f = DecorField.shared
        let active = Set(f.anim.filter { $0.value.active }.keys)
        if f.version != decorDrawn.fieldVersion || active != decorDrawn.active {
            decorDrawn.fieldVersion = f.version; decorDrawn.active = active
            room.setDecorStatic(DecorModels.build(feet: f.feet.filter { !active.contains($0.uid) }, field: f, time: time))
        }
        if !active.isEmpty {
            room.setDecorActive(DecorModels.build(feet: f.feet.filter { active.contains($0.uid) }, field: f, time: time))
            decorDrawn.activeShown = true
        } else if decorDrawn.activeShown {
            room.setDecorActive(RoomMesh()); decorDrawn.activeShown = false
        }
    }

    // MARK: place / arrange / put away

    /// Bag "Place": the piece appears at a free floor spot and arrange mode starts on it (drag to move; Done to finish).
    @discardableResult
    func placeDecor(_ itemID: String) -> PlacedDecor? {
        guard let p = store.place(itemID) else { AudioHub.shared.play(.notEnough); return nil }
        syncDecor()
        AudioHub.shared.play(.placeItem)
        arranging = true; arrangingUID = p.uid
        return p
    }
    func beginArrange(_ uid: Int? = nil) { arranging = true; arrangingUID = uid }

    /// A Jelly is using the piece (sitting in the beanbag, booping the plant, on his way to it) or is still standing inside it.
    func decorBusy(_ uid: Int) -> Bool {
        if DecorField.shared.occupant[uid] != nil { return true }
        for a in raceBook.actors { if let b = a.brain, b.idleState.decorUID == uid || b.decorIgnore == uid { return true } }
        return false
    }

    /// Double tap on a placed piece: arrange mode starts with it picked up. A piece a Jelly is using is never moved from under him: he is asked to hop off first,
    /// and the pick-up happens when he has (`tickDecor`).
    func pickUpDecor(_ uid: Int) {
        guard !arranging, store.placedDecor.contains(where: { $0.uid == uid }), !tripActive, !bath.active, !focus.isActive else { return }
        if !decorBusy(uid) { startArrange(on: uid); return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if let f = DecorField.shared.foot(uid) {
            let c = DecorField.shared.position(f)
            for a in raceBook.actors {
                guard let b = a.brain, b.idleState.decorUID == uid || DecorField.shared.occupant[uid] == b.steerID || b.decorIgnore == uid else { continue }
                b.idleReset(a.skinner)                                      // he stops what he is doing with the piece ...
                let away = simd_length(b.position - c) > 1e-3 ? simd_normalize(b.position - c) : SIMD2<Float>(0, 1)
                let out = GameCamera.constrain(SIMD3(c.x + away.x * (f.spec.radius + 1.4), 0, c.y + away.y * (f.spec.radius + 1.4)), ignoreDecor: uid)
                b.requestNow(.goTo(SIMD2(out.x, out.z)))                    // ... and steps off it
            }
        }
        arrangeWait = (uid, 4)
    }
    private func startArrange(on uid: Int) {
        arranging = true; arrangingUID = uid
        DecorField.shared.kick(uid, 0.8)
        AudioHub.shared.play(.placeItem)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func endArrange() { arranging = false; arrangingUID = nil; arrangeWait = nil }

    /// Moves the piece being dragged toward `floor` (snapped to the nearest valid spot along the way; stays put when nothing near is valid).
    @discardableResult
    func dragDecor(_ uid: Int, to floor: SIMD2<Float>) -> Bool {
        guard let cur = store.placedDecor.first(where: { $0.uid == uid }), !decorBusy(uid) else { return false }          // (never from under a Jelly)
        if store.move(uid, to: floor) { syncDecor(); return true }
        // blocked: slide along the line from where it is to the finger, as far as it is valid
        var best = cur.at
        for k in 1...12 {
            let p = cur.at + (floor - cur.at) * (Float(k) / 12)
            if DecorPlacement.isValid(cur.kind, at: p, among: store.placedDecor, ignoring: uid) { best = p } else { break }
        }
        // a finger across the middle: keep following on one axis when only the other is blocked
        for q in [SIMD2<Float>(floor.x, best.y), SIMD2<Float>(best.x, floor.y), SIMD2<Float>(floor.x, cur.z), SIMD2<Float>(cur.x, floor.y)] where simd_distance(q, floor) < simd_distance(best, floor) - 1e-4 {
            if DecorPlacement.isValid(cur.kind, at: q, among: store.placedDecor, ignoring: uid) { best = q }
        }
        if best != cur.at, store.move(uid, to: best) { syncDecor(); return true }
        return false
    }
    /// The finger let go: the piece settles (a sound).
    func dropDecor(_ uid: Int) {
        AudioHub.shared.play(.placeItem, volume: 0.7)
        DecorField.shared.kick(uid, 0.5)
    }
    func putAwayDecor(_ uid: Int) {
        store.putAway(uid); syncDecor()
        AudioHub.shared.play(.placeItem, volume: 0.5)
        if arrangingUID == uid { arrangingUID = nil }
        if store.placedDecor.isEmpty { arranging = false }
    }

    /// The decor piece whose footprint is under a floor point (the nearest one within its reach), for picking it up with a finger.
    func decorPiece(at floor: SIMD2<Float>) -> PlacedDecor? {
        var best: (PlacedDecor, Float)?
        for p in store.placedDecor {
            let f = DecorField.shared.foot(p.uid)
            let d = (f.map { DecorField.shared.position($0) } ?? p.at)
            let dist = simd_distance(floor, d) - p.kind.spec.radius
            if dist < 0.25, best == nil || dist < best!.1 { best = (p, dist) }
        }
        return best?.0
    }

    /// The floor point (x, z) under a screen point in a view of `size`, or nil when the ray misses the floor.
    func floorPoint(screen: CGPoint, size: CGSize) -> SIMD2<Float>? { GameCamera.floorPoint(screen: screen, size: size) }
}

extension GameCare {
    /// A double tap lands on both a piece and a Jelly's drawn body: the Jelly wins unless the piece is clearly nearer the camera (`jellyDistance` is where the ray meets his body).
    static func decorWins(pieceT: Float, jellyDistance: Float?) -> Bool { jellyDistance.map { $0 > pieceT + 0.3 } ?? true }

    /// The piece under a screen point (a double tap), with the distance from the camera to where the ray meets it. Nil when none.
    func decorHit(screen: CGPoint, size: CGSize) -> (piece: PlacedDecor, t: Float)? {
        guard size.width > 1, size.height > 1 else { return nil }
        let cam = GameCamera.camera(aspect: Float(size.width / size.height))
        let ndc = SIMD2<Float>(Float(screen.x / size.width) * 2 - 1, 1 - Float(screen.y / size.height) * 2)
        let ray = unproject(ndc: ndc, invViewProj: cam.invViewProj)
        guard let h = DecorField.shared.hit(origin: ray.o, dir: simd_normalize(ray.d)), let p = store.placedDecor.first(where: { $0.uid == h.uid }) else { return nil }
        return (p, h.t)
    }
}
