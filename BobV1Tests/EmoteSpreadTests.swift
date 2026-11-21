//
//  EmoteSpreadTests.swift
//  The owner's 11-20 ask (emote-spread-r1): emotes (solo, pair, group) use the whole home floor, not the rug. 3 Jelmiko in the living room, portrait and landscape of an iPhone 17 Pro Max,
//  happy and the owner's low state (19:00, hunger / thirst 0.08 = grumpy). Every body-sample inside an emote is binned on the walkable floor (the app's own RoamFloor spans).
//  Bars: the 1.5 u circle round the rug centre holds at most 1.5x its share of the floor area; each depth third and each width third (equal-area thirds) holds 20...45 %.
//  EMOTESPREAD_MIN (sim minutes per run, default 6), EMOTESPREAD_SEEDS ("1,2,3").
//

import XCTest
import simd
@testable import BobV1

@MainActor
final class EmoteSpreadTests: XCTestCase {
    override func setUp() { DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); ToyTuning.settle = 0 }
    override func tearDown() {
        DecorField.shared.clear(); ToyTuning.settle = 5
        GameCamera.configureRoom(count: 1); GameCamera.clearRoam(); RoomLayout.apply(RoomCatalog.home)
        HUDLayout.measuredSize = .zero; HUDLayout.measuredInsets = .zero
        SocialTests.keep.removeAll(); EmoteSpot.reset(); EmoteSpot.enabled = true; GameCamera.homeRailCutouts = false
    }

    func testLowPortrait() { run(low: true, aspect: SpaceCheckTests.portrait) }
    func testLowLandscape() { run(low: true, aspect: SpaceCheckTests.landscape) }
    func testHappyPortrait() { run(low: false, aspect: SpaceCheckTests.portrait) }
    func testHappyLandscape() { run(low: false, aspect: SpaceCheckTests.landscape) }

    private func run(low: Bool, aspect: Float) {
        let env = ProcessInfo.processInfo.environment
        let minutes = Double(env["EMOTESPREAD_MIN"] ?? "6") ?? 6
        let seeds = (env["EMOTESPREAD_SEEDS"] ?? "1,2,3").split(separator: ",").compactMap { UInt64($0) }
        let port = aspect < 1
        HUDLayout.measuredSize = port ? CGSize(width: 440, height: 956) : CGSize(width: 956, height: 440)
        HUDLayout.measuredInsets = port ? UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0) : UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
        DayClock.shared.forcedHour = low ? 19 : 12
        defer { DayClock.shared.forcedHour = nil }
        var samples: [SIMD2<Float>] = []
        var floorCells: [SIMD2<Float>] = []
        for seed in seeds {
            GameCamera.clearRoam(); DecorField.shared.clear(); DecorField.shared.toys = ToyBook(); EmoteSpot.reset()
            RoomLayout.apply(RoomCatalog.home); GameCamera.configureRoom(count: 3)
            let rf = GameCamera.refreshRoam(aspect: aspect)!
            if floorCells.isEmpty {
                for (i, z) in rf.zs.enumerated() { for sp in rf.free[i] { var x = sp.lowerBound; while x <= sp.upperBound { floorCells.append(SIMD2(x, z)); x += 0.1 } } }
            }
            let lab = SocialTests.Lab(n: 3, positions: JellyRoster.spawnSpots(count: 3), quiet: false, seed: seed &* 1009 &+ 3 &* 17)
            for r in lab.rigs {
                r.sim.arenaCenter = GameCamera.arenaCenter; r.sim.arenaRadius = GameCamera.arenaRadius
                let b = r.brain
                b.anticsEnabled = true; b.idleMood = .happy; b.watching = true; b.sleepEnabled = true; b.homeRoom = true
                if low { b.idleMood = BlobNeeds.mood(of: [0.08, 0.08, 0.5]); b.idleNight = DayClock.shared.nightFactor; b.idleMorning = DayClock.shared.morningFactor; b.idleDeepNight = DayClock.shared.deepNightFactor }
            }
            for s in 0..<Int(minutes * 3600) {
                lab.tick(watching: false)
                guard s % 6 == 0 else { continue }
                for r in lab.rigs {
                    let b = r.brain
                    let inEmote = b.social != nil || (b.idleState.kind.map { k in !["sleep", "sit", "wander"].contains("\(k)") && !BlobBrain.decorKinds.contains(k) } ?? false)
                    if inEmote { samples.append(GameCare.floorPos(b, r.sim)) }
                }
            }
            SocialTests.keep.removeAll()
        }
        let zs = floorCells.map(\.y).sorted(), xs = floorCells.map(\.x).sorted()
        let n = floorCells.count
        let z1 = zs[n / 3], z2 = zs[2 * n / 3], x1 = xs[n / 3], x2 = xs[2 * n / 3]
        let circleArea = Float(floorCells.filter { simd_distance($0, RoomLayout.rugCentre) < 1.5 }.count) / Float(n)
        let total = Float(max(samples.count, 1))
        func share(_ f: (SIMD2<Float>) -> Bool) -> Float { Float(samples.filter(f).count) / total }
        let circle = share { simd_distance($0, RoomLayout.rugCentre) < 1.5 }
        let depth = [share { $0.y < z1 }, share { $0.y >= z1 && $0.y < z2 }, share { $0.y >= z2 }]
        let width = [share { $0.x < x1 }, share { $0.x >= x1 && $0.x < x2 }, share { $0.x >= x2 }]
        print(String(format: "[emotespread] low %d aspect %.2f samples %d circle %.3f (area %.3f) depth back/mid/front %.2f/%.2f/%.2f width L/C/R %.2f/%.2f/%.2f", low ? 1 : 0, aspect, samples.count, circle, circleArea, depth[0], depth[1], depth[2], width[0], width[1], width[2]))
        XCTAssertGreaterThan(samples.count, 400, "enough emote samples")
        XCTAssertLessThanOrEqual(circle, 1.5 * circleArea, "emote time inside 1.5 u of the rug centre <= 1.5x the circle's share of the floor")
        for (i, d) in depth.enumerated() { XCTAssertTrue((0.20...0.45).contains(d), "depth third \(i) holds \(d)") }
        for (i, w) in width.enumerated() { XCTAssertTrue((0.20...0.45).contains(w), "width third \(i) holds \(w)") }
    }
}
