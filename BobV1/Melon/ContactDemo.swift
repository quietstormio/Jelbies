//
//  ContactDemo.swift
//  Capture aid only (launch arguments; nothing happens without them): force one touching emote between chosen Jelbies in the real app.
//    -ContactDemo <SocialKind raw value | lieDown | sleepPile; groupHug, circleDance, groupCheer take the whole cast>   e.g. swayHug, noseBoop, backToBack, cuddleLean, groupHug, lieDown
//    -ContactDemoIds 0,1[,2]                          roster slots of the cast; the first one starts it (default: everyone, in order)
//    -ContactCam low|side                             camera (Photo-mode orbit pose); works without -ContactDemo
//    -ContactDemoDelay <s>                            wait before it starts (default 4)
//  The cast is taken off autonomy so nothing else interrupts the scene. Used by BobV1UITests/ContactCaptureUITests.swift.
//

import Foundation
import simd

enum ContactDemo {
    /// Result line to the console and (simulator shares the host filesystem) to $CONTACTDEMO_LOG when set.
    static func note(_ f: String, _ a: CVarArg...) {
        let line = String(format: f, arguments: a)
        NSLog("[contactdemo] %@", line)
        if let p = ProcessInfo.processInfo.environment["CONTACTDEMO_LOG"], let h = FileHandle(forWritingAtPath: p) ?? { FileManager.default.createFile(atPath: p, contents: nil); return FileHandle(forWritingAtPath: p) }() { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); h.closeFile() }
    }
    /// `-ContactCam low|side`: the Photo-mode orbit pose, set once (low = a low 3/4 view from the right, side = a steep orbit, nearly along the row of Jelbies).
    static func applyCamera() {
        guard let c = UserDefaults.standard.string(forKey: "ContactCam") else { return }
        PhotoCam.reset(); PhotoCam.active = true
        switch c {
        case "side": PhotoCam.yaw = 1.2; PhotoCam.pitch = -0.3; PhotoCam.zoom = 0.8; PhotoCam.pan = SIMD2(0, 0.45)
        default: PhotoCam.yaw = 0.45; PhotoCam.pitch = -0.3; PhotoCam.zoom = 0.8; PhotoCam.pan = SIMD2(0, 0.45)
        }
    }

    @MainActor static func run(care: GameCare) async {
        let d = UserDefaults.standard
        applyCamera()
        guard let name = d.string(forKey: "ContactDemo"), !name.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64((d.double(forKey: "ContactDemoDelay") > 0 ? d.double(forKey: "ContactDemoDelay") : 4) * 1e9))
        for _ in 0..<300 where care.raceBook.actors.count < 2 || care.raceBook.actors.contains(where: { $0.brain == nil }) { try? await Task.sleep(nanoseconds: 100_000_000) }          // (the roster may still be loading)
        let actors = care.raceBook.actors
        let ids = d.string(forKey: "ContactDemoIds").map { $0.split(separator: ",").compactMap { Int($0) } } ?? Array(actors.indices)
        let cast = ids.compactMap { actors.indices.contains($0) ? actors[$0] : nil }.filter { $0.brain != nil }
        guard cast.count >= 2 else { note(" cast too small (%d)", cast.count); return }
        for a in cast { a.brain?.autonomy = false; a.brain?.idleForced = true }
        // side by side across the screen first (a pair along the camera axis hides the touch): spots at z -0.9 (the camera's look-at depth), 2.6 u apart (3: 2.4 u)
        let half: Float = (name == "lieDown" || name == "sleepPile") ? 0.65 : 1.3          // (the lie-down / sleep placement wants them ~1.2 u apart, as the Lab does)
        let xs: [Float] = cast.count == 2 ? [-half, half] : (0..<cast.count).map { (Float($0) - Float(cast.count - 1) / 2) * 1.8 }
        let spots = xs.map { SIMD2<Float>($0, -0.9) }
        for a in cast { if let b = a.brain { note(" start (%.2f, %.2f)", b.position.x, b.position.y) } }
        for (a, g) in zip(cast, spots) { a.brain?.requestNow(.goTo(g)) }
        for _ in 0..<250 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if zip(cast, spots).allSatisfy({ a, g in a.brain.map { simd_distance($0.position, g) < 0.5 } ?? true }) { break }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for a in cast { if let b = a.brain { note(" at (%.2f, %.2f) steer=%d", b.position.x, b.position.y, b.steerID) } }
        if name == "sleepPile" {          // the first falls asleep, the others join him a few seconds later
            _ = cast[0].brain?.idleStart(.sleep, cast[0].sim); cast[0].brain?.sleep.hold = 600
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            for a in cast.dropFirst() { let ok = a.brain?.idleStart(.sleep, a.sim) ?? false; a.brain?.sleep.hold = 600; note(" sleepPile join=%d", ok ? 1 : 0) }
            return
        }
        if name == "lieDown" {
            var ok = true
            for a in cast { ok = (a.brain?.idleStart(.lieDown, a.sim) ?? false) && ok }
            note(" lieDown started=%d", ok ? 1 : 0)
            return
        }
        guard let kind = SocialKind(rawValue: name), let a = cast.first, let ab = a.brain, let bb = cast[1].brain else { note(" unknown kind %@", name); return }
        if kind == .groupHug || kind == .circleDance || kind == .groupCheer {          // (a group: everyone else in the cast joins; socialStart(kind, with: one) only finds the near ones)
            note(" %@ started=%d crew=%d", name, ab.socialStartGroup(kind, with: cast.dropFirst().compactMap(\.brain), a.sim) ? 1 : 0, cast.count)
            return
        }
        note(" %@ started=%d", name, ab.socialStart(kind, with: bb, a.sim) ? 1 : 0)
    }
}
