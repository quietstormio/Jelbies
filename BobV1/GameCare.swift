//
//  GameCare.swift
//  Care actions of the game screen (feed / water / call). The SwiftUI menu calls feed() / water() / call();
//  the stage controller calls tick() once per fixed sim step, which talks to Bob's brain and the renderer's bowls.
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class GameCare {
    enum Phase { case appearing, waiting, leaving }
    struct Bowl {
        var kind: RoomProp.Kind
        var spot: SIMD2<Float>
        var phase: Phase = .appearing
        var scale: Float = 0
        var level: Float = 1
        var age: Float = 0
        var started = false      // he has begun eating / drinking this bowl
        var request: BlobRequest { kind == .food ? .eat(at: spot) : .drink(at: spot) }
    }

    /// Each bowl is out independently: Feed is disabled only while the food bowl is out, Water while the water bowl is.
    private(set) var foodOut = false
    private(set) var waterOut = false
    /// Mirrors the brain's activity for the menu / tests.
    private(set) var busy = false
    var bowlOut: Bool { foodOut || waterOut }

    @ObservationIgnored private var bowls: [Bowl] = []
    @ObservationIgnored private var queued: [BlobRequest] = []      // one-shot brain requests (wave / come)
    @ObservationIgnored private var hooked = false
    @ObservationIgnored private var servingKind: RoomProp.Kind?     // the bowl he is working on
    @ObservationIgnored private var callRunning = false
    @ObservationIgnored private var finished: [BlobRequest] = []
    @ObservationIgnored private var idleT: Float = 0
    @ObservationIgnored private var retries = 0

    static let bowlObstacle: Float = 0.4
    static let bowlTimeout: Float = 45

    // Not isolated: Swift 6.2's implicit isolated deinit (swift_task_deinitOnExecutor) aborts on the iOS 26.2 runtime; see MelonModel.
    nonisolated deinit {}

    func feed() { put(.food, at: GameCamera.foodBowlSpot) }
    func water() { put(.water, at: GameCamera.waterBowlSpot) }
    func wave() { queued = [.wave] }
    /// Calls him over; if he was working on a bowl he goes back to it afterwards.
    func call() { queued = [.come(to: GameCamera.callSpot)] }

    private func put(_ kind: RoomProp.Kind, at spot: SIMD2<Float>) {
        guard !bowls.contains(where: { $0.kind == kind }) else { return }
        bowls.append(Bowl(kind: kind, spot: spot))
        sync()
    }

    private func sync() {
        foodOut = bowls.contains { $0.kind == .food }
        waterOut = bowls.contains { $0.kind == .water }
    }

    /// Floor obstacle for the brain's resolver: pushes a point out of the bowls.
    func obstacle(_ p: SIMD3<Float>, radius: Float) -> SIMD3<Float> {
        var q = p
        for b in bowls where b.scale > 0.3 {
            let r = Self.bowlObstacle + radius * 0.15
            let d = SIMD2(q.x, q.z) - b.spot
            let len = simd_length(d)
            guard len < r else { continue }
            let dir = len > 1e-4 ? d / len : SIMD2(0, 1)
            let n = b.spot + dir * r
            q = SIMD3(n.x, q.y, n.y)
        }
        return q
    }

    func tick(brain: BlobBrain, renderer: MelonRenderer?, dt: Float) {
        if !hooked {
            hooked = true
            brain.onFinished = { [weak self] r in self?.finished.append(r) }
            let base = brain.resolve
            brain.resolve = { [weak self] p, r in
                let q = base(p, r)
                return self?.obstacle(q, radius: r) ?? q
            }
        }
        let act = brain.activity
        busy = act != .idle && act != .lookingAround && act != .steppingInPlace

        // finished jobs
        for r in finished {
            switch r {
            case .come: callRunning = false; retries = 0
            case .eat, .drink:
                if let k = servingKind, let i = bowls.firstIndex(where: { $0.kind == k }) { bowls[i].phase = .leaving }
                servingKind = nil; retries = 0
            default: break
            }
        }
        finished.removeAll()

        // one-shot requests
        if let r = queued.first {
            queued.removeFirst()
            brain.requestNow(r)
            if case .come = r { callRunning = true }
        }

        // bowls
        for i in bowls.indices {
            bowls[i].age += dt
            switch bowls[i].phase {
            case .appearing:
                bowls[i].scale = min(1, bowls[i].scale + dt / 0.35)
                if bowls[i].scale >= 1 { bowls[i].phase = .waiting }
            case .waiting:
                if bowls[i].kind == servingKind, act == .eating || act == .drinking {
                    bowls[i].started = true
                    let drink = bowls[i].kind == .water
                    bowls[i].level = max(drink ? 0.3 : 0, bowls[i].level - dt / (drink ? 3.4 : 3.2))
                }
                if bowls[i].age > Self.bowlTimeout { bowls[i].phase = .leaving }
            case .leaving:
                bowls[i].scale = max(0, bowls[i].scale - dt / 0.45)
                if bowls[i].kind == .food { bowls[i].level = max(0, bowls[i].level - dt * 0.5) }
            }
        }
        let before = bowls.count
        bowls.removeAll { $0.phase == .leaving && $0.scale <= 0 }
        if bowls.count != before { sync() }
        if let k = servingKind, !bowls.contains(where: { $0.kind == k && $0.phase != .leaving }) { servingKind = nil }

        // pick the next bowl to serve (one after another), unless he is busy being called
        if !callRunning, queued.isEmpty {
            if servingKind == nil, let b = bowls.first(where: { $0.phase == .waiting }) {
                servingKind = b.kind; idleT = 0; retries = 0
                brain.requestNow(b.request)
            } else if let k = servingKind, let b = bowls.first(where: { $0.kind == k }) {
                // the request was cancelled (for example he was grabbed): ask again a couple of times, then give up
                if act == .idle || act == .lookingAround || act == .steppingInPlace {
                    idleT += dt
                    if idleT > 0.8 {
                        idleT = 0
                        if retries < 2 { retries += 1; brain.requestNow(b.request) }
                        else if let i = bowls.firstIndex(where: { $0.kind == k }) { bowls[i].phase = .leaving; servingKind = nil }
                    }
                } else { idleT = 0 }
            }
        }

        renderer?.room?.props = bowls.map {
            let e = $0.scale * $0.scale * (3 - 2 * $0.scale)
            return RoomProp(kind: $0.kind, pos: $0.spot, scale: max(e, 0.001), level: ($0.level * 20).rounded() / 20)
        }
    }
}
