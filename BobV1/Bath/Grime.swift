//
//  Grime.swift
//  Lint builds up on his soft, slightly tacky skin as he roams (dust, crumbs, leaves, glitter, sock fuzz). Not a need: no bubble.
//  Persisted (UserDefaults, like BlobNeeds.v1). Also: the room sparkle left by a clean-up, which fades slowly and is knocked down by new lint,
//  and a tiny Drops wallet (no Drops economy existed in the code yet: peeling a dropped Jelly Drop adds one here).
//

import Foundation
import Observation
import simd

/// Every tunable of the grime in one place.
enum GrimeTuning {
    /// World units walked / run per new lint bit (about one bit per 1-2 minutes of normal roaming).
    static let unitsPerBit: Float = 40
    static let maxBits = BathLook.maxLint
    /// One bit in this many is a dropped Jelly Drop.
    static let dropEvery = 8
    /// Seconds for a full room sparkle to fade out on its own, and how much each new bit knocks off.
    static let sparkleSeconds: Float = 210
    static let sparkleKnock: Float = 0.18
    static let saveEvery: Float = 15
    static let defaultsKey = "BlobGrime.v1"
}

/// Earned-only currency (design: races pay most, care pays steady). Only the lint Drop feeds it for now.
@MainActor
@Observable
final class DropsWallet {
    private(set) var count = 0
    @ObservationIgnored private let persists: Bool
    static let key = "BlobDrops.v1"
    init(persists: Bool = true) {
        self.persists = persists
        if persists { count = UserDefaults.standard.integer(forKey: Self.key) }
    }
    nonisolated deinit {}
    func add(_ n: Int = 1) {
        count += n
        if persists { UserDefaults.standard.set(count, forKey: Self.key) }
    }
}

@MainActor
@Observable
final class BlobGrime {
    private(set) var bits: [LintBit] = []
    /// 0...1, the shine left from the last clean-up.
    var sparkle: Float = 0
    @ObservationIgnored private(set) var distance: Float = 0
    @ObservationIgnored private(set) var made = 0
    @ObservationIgnored private var saveT: Float = 0
    @ObservationIgnored private var rng: UInt32
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored var unitsPerBit = GrimeTuning.unitsPerBit

    init(persists: Bool = true, seed: UInt32 = 0xB47B) {
        self.persists = persists
        rng = seed
        if persists { load() }
    }
    nonisolated deinit {}

    private func rand() -> Float { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return Float(rng >> 8) / Float(1 << 24) }

    /// Walking / running adds distance; every `unitsPerBit` makes a bit. `travelled` is the floor distance moved this step (0 when idle).
    func step(dt: Float, travelled: Float) {
        if sparkle > 0 { sparkle = max(0, sparkle - dt / GrimeTuning.sparkleSeconds) }
        if travelled > 0 {
            distance += travelled
            while distance >= unitsPerBit { distance -= unitsPerBit; addBit() }
        }
        saveT += dt
        if saveT > GrimeTuning.saveEvery { saveT = 0; save() }
    }

    @discardableResult
    func addBit() -> LintBit? {
        guard bits.count < GrimeTuning.maxBits else { return nil }
        made += 1
        let kind: LintKind
        if made % GrimeTuning.dropEvery == 0 { kind = .drop }
        else { kind = [LintKind.dust, .crumb, .leaf, .glitter, .fuzz][Int(rand() * 5) % 5] }
        var dir: SIMD3<Float>
        if kind == .leaf, rand() < 0.5 { dir = simd_normalize(SIMD3(rand() - 0.5, 1.0, (rand() - 0.5) * 0.4 - 0.1)) }    // on the crown, out of reach
        else { dir = Self.spot(rand: { self.rand() }) }
        let bit = LintBit(kind: kind, dir: dir, spin: rand() * 2 * .pi, size: 0.06 + 0.08 * rand())
        bits.append(bit)
        sparkle = max(0, sparkle - GrimeTuning.sparkleKnock)
        save()
        return bit
    }

    /// A funny place: not the face band (front, eye / mouth height), not the feet (the bottom rows).
    static func spot(rand: () -> Float) -> SIMD3<Float> {
        for _ in 0..<40 {
            let polar = (0.08 + 0.64 * rand()) * .pi                      // 14 deg ... 130 deg from the top
            let az = (rand() * 2 - 1) * .pi
            let d = SIMD3(sinf(polar) * sinf(az), cosf(polar), sinf(polar) * cosf(az))
            let face = d.z > 0.35 && d.y > -0.2 && d.y < 0.55 && abs(d.x) < 0.8     // eyes, brows, mouth
            if !face { return d }
        }
        return SIMD3(0, 0.2, -1)
    }

    /// Start peeling every stuck bit within `radius` (world units) of the hit `local`. Returns the indices that began to peel.
    @discardableResult
    func startPeel(hit local: SIMD3<Float>, radius: Float) -> [Int] {
        var out: [Int] = []
        let reach = radius * BathLook.radiansPerUnit
        for i in bits.indices where bits[i].peel == 0 {
            if BathLook.angle(bits[i].dir, hit: local) < reach + bits[i].size * BathLook.radiansPerUnit { bits[i].peel = 0.001; out.append(i) }
        }
        return out
    }

    /// Advance the peel animation; returns the bits that just finished (removed).
    func advancePeel(dt: Float, seconds: Float = 0.28) -> [LintBit] {
        var gone: [LintBit] = []
        for i in bits.indices where bits[i].peel > 0 { bits[i].peel = min(1, bits[i].peel + dt / seconds) }
        bits.removeAll { if $0.peel >= 1 { gone.append($0); return true }; return false }
        if !gone.isEmpty { save() }
        return gone
    }

    var peeling: Bool { bits.contains { $0.peel > 0 } }
    func clearAll() { bits.removeAll(); save() }

    // MARK: persistence

    private struct Saved: Codable {
        struct Bit: Codable { var k: UInt8; var d: [Float]; var s: Float; var z: Float }
        var bits: [Bit]; var sparkle: Float; var distance: Float; var made: Int; var at: Double
    }
    func save() {
        guard persists else { return }
        let s = Saved(bits: bits.map { .init(k: $0.kind.rawValue, d: [$0.dir.x, $0.dir.y, $0.dir.z], s: $0.spin, z: $0.size) },
                      sparkle: sparkle, distance: distance, made: made, at: Date().timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: GrimeTuning.defaultsKey) }
    }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: GrimeTuning.defaultsKey), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        bits = s.bits.compactMap { b in
            guard b.d.count == 3, let k = LintKind(rawValue: b.k) else { return nil }
            return LintBit(kind: k, dir: SIMD3(b.d[0], b.d[1], b.d[2]), spin: b.s, size: b.z)
        }
        distance = s.distance; made = s.made
        let away = Float(max(0, Date().timeIntervalSince1970 - s.at))
        sparkle = max(0, s.sparkle - away / GrimeTuning.sparkleSeconds)
    }
}
