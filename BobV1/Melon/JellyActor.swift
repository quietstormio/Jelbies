//
//  JellyActor.swift
//  One Jelly of the room, as the stage runs him: soft body + skinner (+ brain), where he spawns, and his saved state (`JellyProfile`, owned by GameCare).
//  The stage holds `[JellyActor]` and loops them; Jelly 0 is Bob and every Bob-only feature (meals, Clean, voice, the close-up) drives `actors[0]`.
//  All actors share the same sim mesh, render mesh and embedding (same appearance); each has its own particles, skin state and GPU slot (= its index).
//

import Foundation
import simd

@MainActor
final class JellyActor {
    let id: Int
    let name: String
    let sim: SoftBody
    let skinner: Skinner
    var brain: BlobBrain?
    /// Where he starts (centroid x, z).
    let spawn: SIMD2<Float>
    /// What he keeps (GameCare owns it): needs, dirt, the look the room draws it with, his book of words. Nil only for a stage without a game.
    weak var profile: JellyProfile?
    weak var care: GameCare?
    /// The colours he is drawn in (nil = the model's palette, i.e. Bob's).
    var appearance: Palette?
    var needs: BlobNeeds? { profile?.needs }
    var grime: BlobGrime? { profile?.grime }
    var look: BathLook { profile?.look ?? .dry }
    var words: VoiceTraining? { profile?.training }
    /// The roster / double-tap selection currently points at him (highlighting or confirmed).
    var selected: Bool { care.map { $0.select.selectedID == id || $0.select.confirmed == id } ?? false }

    nonisolated deinit {}

    init(id: Int, name: String, simMesh sm: SimMesh, renderMesh rm: RenderMesh, embedding emb: (tetOf: [UInt32], w: [Float]),
         appearance ap: BlobAppearance, firmness: Float, damping: Float, spawn: SIMD2<Float>) {
        self.id = id; self.name = name; self.spawn = spawn
        sim = SoftBody(mesh: sm, firmness: firmness, damping: damping)
        skinner = Skinner(simTets: sm.tets, embedding: emb, vertexCount: rm.vertexCount,
                          eyes: buildEyeRig(render: rm, sim: sm, appearance: ap),
                          antennae: buildAntennaRig(render: rm, sim: sm))
        skinner.configureTail(rm)
    }

    // MARK: sleep (a settled Jelly skips his sim step)

    /// Consecutive fixed steps of calm before he sleeps (0.5 s at 60 Hz; the body's own rest snap needs ~0.25 s of stillness first).
    static let sleepAfterSteps = 30
    private(set) var asleep = false
    private var calmSteps = 0
    private var seenEpoch = -1
    /// Counters for the perf line: fixed steps skipped, and wake-ups.
    private(set) var sleptSteps = 0, wakeCount = 0

    /// Brain says nothing is going on: no action, command, request, script, idle behaviour or exertion.
    private var brainIsStill: Bool {
        guard let b = brain, b.enabled else { return false }
        // asleep on his back (the hold stage): the attractor is constant and nothing else is going on, so his sim may sleep too
        if b.isNapping { return b.social == nil && b.pending == nil && !b.commanded && b.commandedIdle == nil && !b.interruptScript && !b.commandedFlip && !b.commandedNameHop }
        if case .none = b.script {} else { return false }
        return b.social == nil && b.activity == .idle && !b.commanded && b.pending == nil && b.idleState.kind == nil && b.commandedIdle == nil && !b.isExerting && !b.earsActive
    }

    /// Call once per fixed step, after the brain / care ticks and before the sim step. Returns true if his sim should step.
    /// He falls asleep after `sleepAfterSteps` calm steps (settled body, still brain, nothing holding him: `forceAwake` = touched, in a close-up,
    /// bath, meal ...). Any brain action, touch or outside edit of the body (epoch) wakes him on the very step it happens; his body is at rest with
    /// zero velocity, so neither falling asleep nor waking changes a vertex.
    func updateSleep(forceAwake: Bool) -> Bool {
        let epoch = sim.epoch
        let calm = !forceAwake && epoch == seenEpoch && brainIsStill && sim.isSettled
        seenEpoch = epoch
        if !calm {
            calmSteps = 0
            if asleep { asleep = false; wakeCount += 1 }
            return true
        }
        calmSteps += 1
        if asleep { sleptSteps += 1; return false }
        if calmSteps >= Self.sleepAfterSteps { asleep = true; sleptSteps += 1; return false }
        return true
    }

    /// Drops him onto the floor at his spawn spot (the origin when `shift` is off: the single-Jelly game and the studio).
    func reset(drop: Float, shift: Bool) {
        sim.reset(drop: drop)
        if shift { sim.targets = []; sim.shift(byXZ: spawn) }
        brain?.currentPose(sim)          // the brain's root follows the body, or its first pose drive would pull him back to the origin
    }

    /// His floor spot now: the body's centroid when it is free, else the brain's root.
    var floor: SIMD2<Float> { brain.map { GameCare.floorPos($0, sim) } ?? { let c = sim.centroid(); return SIMD2(c.x, c.z) }() }
    /// He is walking somewhere (the others steer around a Jelly that stands still; between two walkers the lower id gives way).
    var isWalking: Bool { brain.map { $0.activity == .walking || $0.activity == .coming } ?? false }
}

/// The fixed-step work that runs on every core: one body per iteration. Free functions on nonisolated types, so no main-actor closure ever runs
/// on a worker thread. Bodies share nothing but the (read-only) render index; each writes only its own particles / vertex stream.
nonisolated enum JellyParallel {
    /// Below this many bodies the work runs inline on the calling thread (a single Jelly pays nothing for the dispatch).
    static let minForThreads = 2

    static func step(_ sims: [SoftBody]) {
        if sims.count < minForThreads { for s in sims { s.step() }; return }
        sims.withUnsafeBufferPointer { b in
            DispatchQueue.concurrentPerform(iterations: b.count) { b[$0].step() }
        }
    }

    struct SkinJob { var skinner: Skinner; var sim: SoftBody; var dst: UnsafeMutablePointer<Float> }

    static func skin(_ jobs: [SkinJob], index: [UInt32]) {
        if jobs.count < minForThreads { for j in jobs { j.skinner.update(x: j.sim.x, index: index, into: j.dst) }; return }
        jobs.withUnsafeBufferPointer { b in
            DispatchQueue.concurrentPerform(iterations: b.count) { b[$0].skinner.update(x: b[$0].sim.x, index: index, into: b[$0].dst) }
        }
    }
}
