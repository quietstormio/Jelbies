//
//  FeatureSpec.swift
//  The character features' data (feature_compat.json, written by tools/convert_char_art.py from the art lab): the animation data of Pip's spines,
//  Moss's daisy and Lavender's wings, the flap-hop keyframes, and the per-wearable compatibility rules with the measured wing clearance tables.
//  `FeatureCompat.solve` turns what a Jelly WEARS right now into what his feature does: which spines hide, where the daisy sits (on the hat, with a
//  variant hat under it), how far the wings shift and how far they may flap, or whether they fold flat.
//

import Foundation
import simd

nonisolated struct FeatureSpec: Codable, Sendable {
    struct Spine: Codable, Sendable {
        var part: String, zone: String
        var base: [Float], normal: [Float], axis: [Float], pivot: [Float]
        var height: Float, maxDeg: Float, hz: Float, damping: Float, lag: Float
    }
    struct Daisy: Codable, Sendable {
        var id: String
        var anchor: [Float], stemPivot: [Float], flowerCentre: [Float], flowerNormal: [Float]
        var petals: [String]
        var closeDeg: Float, idleDeg: [Float], idleHz: Float, headLag: Float, droopDeg: Float, closeTime: Float
    }
    struct WingSide: Codable, Sendable { var hinge: [Float], flapAxis: [Float], spreadAxis: [Float], parts: [String] }
    struct Wings: Codable, Sendable { var anchor: [Float]; var sides: [String: WingSide] }
    struct HopKey: Codable, Sendable { var t: Float, lift: Float, drift: Float, sy: Float, pitchDeg: Float, flap: Float, spread: Float, dangle: Float }
    struct Osc: Codable, Sendable { var mean: Float, amp: Float, hz: Float }
    struct Hop: Codable, Sendable {
        var total: Float, maxLift: Float, drift: Float
        var keyframes: [HopKey]
        var oscFrom: Float, oscTo: Float
        var lift: Osc, hover: Osc, decay: Osc
    }
    struct MossRule: Codable, Sendable { var rule: String; var anchor: [Float]?; var tilt: Float?; var sink: Float?; var variant: String? }
    struct LavRule: Codable, Sendable { var rule: String; var dy: Float?; var flapMin: Float?; var flapMax: Float?; var spreadMax: Float? }
    struct Pair: Codable, Sendable { var slot: String; var pipHide: [String]; var moss: MossRule; var lav: LavRule }
    struct MeshInfo: Codable, Sendable { var vertices: Int, triangles: Int; var parts: [String] }

    var version: Int
    var top: Float
    var dys: [Float]
    var meshes: [String: MeshInfo]
    var spines: [Spine]
    var daisy: Daisy, daisyOnHat: Daisy
    var wings: Wings
    var hop: Hop
    var pairs: [String: Pair]
    /// Per wearable art id, per vertical wing shift ("-0.12" ...): [min flap, max flap] in degrees, or null where the wings clip at rest.
    var wingLimits: [String: [String: [Float]?]]

    nonisolated(unsafe) private static var _shared: FeatureSpec?
    private static let lock = NSLock()
    private final class Token {}
    static var shared: FeatureSpec {
        lock.lock(); defer { lock.unlock() }
        if let s = _shared { return s }
        let url = Bundle.main.url(forResource: "feature_compat", withExtension: "json") ?? Bundle(for: Token.self).url(forResource: "feature_compat", withExtension: "json")
        let s = (url.flatMap { try? Data(contentsOf: $0) }).flatMap { try? JSONDecoder().decode(FeatureSpec.self, from: $0) } ?? FeatureSpec.empty
        _shared = s
        return s
    }
    static let empty = FeatureSpec(version: 0, top: 1.3458, dys: [], meshes: [:], spines: [],
                                   daisy: Daisy(id: "", anchor: [0, 0, 0], stemPivot: [0, 0, 0], flowerCentre: [0, 0, 0], flowerNormal: [0, 1, 0], petals: [], closeDeg: 0, idleDeg: [0, 0], idleHz: 0, headLag: 0, droopDeg: 0, closeTime: 1),
                                   daisyOnHat: Daisy(id: "", anchor: [0, 0, 0], stemPivot: [0, 0, 0], flowerCentre: [0, 0, 0], flowerNormal: [0, 1, 0], petals: [], closeDeg: 0, idleDeg: [0, 0], idleHz: 0, headLag: 0, droopDeg: 0, closeTime: 1),
                                   wings: Wings(anchor: [0, 0, 0], sides: [:]),
                                   hop: Hop(total: 0, maxLift: 0, drift: 0, keyframes: [], oscFrom: 0, oscTo: 0, lift: Osc(mean: 0, amp: 0, hz: 0), hover: Osc(mean: 0, amp: 0, hz: 0), decay: Osc(mean: 0, amp: 0, hz: 0)),
                                   pairs: [:], wingLimits: [:])
}

nonisolated extension Array where Element == Float {
    var v3: SIMD3<Float> { count >= 3 ? SIMD3(self[0], self[1], self[2]) : .zero }
}

/// What a Jelly's feature does under what he wears now (FeatureCompat.solve).
nonisolated struct FeatureFit: Equatable, Sendable {
    /// Pip: the art id of the head item the spines grow through (when it encloses the head; see FeatureSet.emit).
    var spineHat: String?
    /// (Spines are never hidden any more; kept empty so the tests and old callers read the same shape.)
    var hiddenParts: Set<String> = []
    /// Moss: the sprout is hidden (propeller beanie).
    var hidden = false
    /// Moss: the on-hat sprout instead of the plain one, placed by `anchor` / `tilt` / `sink` (work/daisy.py: rotate about the crown by tilt, move the
    /// crown to `anchor`, sink along the tilted stem axis).
    var onHat = false
    var anchor = SIMD3<Float>(0, 1.3458, 0), tilt: Float = 0, sink: Float = 0
    /// The hat drawn instead of the worn one while the sprout sits on it (nopom / nobutton / short variants): worn art id -> variant art id.
    var hatVariant: [String: String] = [:]
    /// Lavender: the vertical wing shift and the flap / spread clamps; `folded` = no placement fits, the wings lie flat and the flap-hop is a plain hop.
    var wingDY: Float = 0, flapMin: Float = -40, flapMax: Float = 75, spreadMax: Float = 40
    var folded = false
}

nonisolated enum FeatureCompat {
    static let fullFlap: ClosedRange<Float> = -40...75
    /// Where Moss's daisy sits on the hats whose art-lab rule was "hide" (placement as the other rules: crown moved to `anchor`, tilted, sunk).
    static let hatDaisy: [String: FeatureSpec.MossRule] = [
        "cowboy_hat": .init(rule: "adjust", anchor: [0.0, 1.3758, 0.0], tilt: 0, sink: 0, variant: nil),
        "beret": .init(rule: "adjust", anchor: [0.0, 1.30, 0.42], tilt: 55, sink: 0.05, variant: nil),
        "propeller_beanie": .init(rule: "adjust", anchor: [0.0, 1.30, 0.42], tilt: 55, sink: 0.05, variant: nil),
    ]

    /// The fit of `feature` under the worn art ids (what the wardrobe SHOWS now, not the whole outfit: a hat that poofed off for the night frees the spines).
    static func solve(_ feature: JellyFeature, worn: [String], spec: FeatureSpec = .shared) -> FeatureFit {
        var fit = FeatureFit()
        switch feature {
        case .none: return fit
        case .spines:
            // Pip's spines NEVER vanish under what he wears. Under a hat that encloses his head they grow through the TOP of its crown (a mohawk through
            // the hat: FeatureSet.emit seats each base on the fitted crown); with the perch items (bows, headphones, antennae ...) they stay as they are.
            for w in worn { if spec.pairs[w]?.slot == "head" { fit.spineHat = w } }
        case .daisy:
            // one head item at most; its rule places the sprout
            for w in worn {
                guard let p = spec.pairs[w], p.slot == "head" else { continue }
                var rule = p.moss
                // the daisy never vanishes under a hat: where the art lab said "hide", it is tucked on the hat instead (hatDaisy)
                if rule.rule == "hide" { rule = hatDaisy[w] ?? FeatureSpec.MossRule(rule: "adjust", anchor: [0, spec.top + 0.03, 0], tilt: 0, sink: 0, variant: nil) }
                switch rule.rule {
                case "hide": fit.hidden = true
                case "adjust":
                    fit.onHat = true
                    fit.anchor = rule.anchor?.v3 ?? SIMD3(0, spec.top, 0); fit.tilt = rule.tilt ?? 0; fit.sink = rule.sink ?? 0
                    if let v = rule.variant { fit.hatVariant[w] = v }
                default: break
                }
            }
        case .wings:
            let relevant = worn.filter { spec.wingLimits[$0] != nil || (spec.pairs[$0]?.lav.rule ?? "ok") != "ok" }
            if relevant.isEmpty { break }
            if relevant.count == 1, let p = spec.pairs[relevant[0]] {
                // the art lab's own choice for a single item (compat_sheet.png was checked with these)
                if p.lav.rule == "hide" { fit.folded = true; fit.flapMin = 0; fit.flapMax = 0; fit.spreadMax = 0; break }
                fit.wingDY = p.lav.dy ?? 0; fit.flapMin = p.lav.flapMin ?? -40; fit.flapMax = p.lav.flapMax ?? 75; fit.spreadMax = p.lav.spreadMax ?? 40
                break
            }
            if let s = solveWings(relevant, spec: spec) {
                fit.wingDY = s.dy; fit.flapMin = s.lo; fit.flapMax = s.hi; fit.spreadMax = min(40, 0.4 * max(s.hi, 0))
            } else {
                fit.folded = true; fit.wingDY = 0; fit.flapMin = 0; fit.flapMax = 0; fit.spreadMax = 0
            }
        }
        return fit
    }

    /// The best wing shift and flap range over several worn items (work/wingsolve.py `solve`): the intersection of each item's measured range at that
    /// shift; an item not measured at a shift beyond [-0.08, 0.04] rules that shift out; nil = nothing fits (fold).
    static func solveWings(_ worn: [String], spec: FeatureSpec) -> (dy: Float, lo: Float, hi: Float)? {
        var best: (score: (Float, Float, Float, Float), dy: Float, lo: Float, hi: Float)?
        for dy in spec.dys {
            var lo = fullFlap.lowerBound, hi = fullFlap.upperBound, ok = true
            for w in worn {
                guard let table = spec.wingLimits[w] else { continue }
                guard let entry = table[key(dy)] else {
                    if dy < -0.08 - 1e-4 || dy > 0.04 + 1e-4 { ok = false }
                    continue
                }
                guard let r = entry, r.count == 2 else { ok = false; break }
                lo = max(lo, r[0]); hi = min(hi, r[1])
            }
            if !ok || hi < lo { continue }
            let score = (min(hi, 30), lo <= -20 ? Float(1) : 0, -abs(dy), hi)
            if best == nil || score > best!.score { best = (score, dy, lo, hi) }
        }
        return best.map { ($0.dy, $0.lo, $0.hi) }
    }
    static func key(_ dy: Float) -> String {
        let r = (dy * 100).rounded() / 100
        if r == 0 { return "0.0" }
        var s = String(format: "%.2f", r)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s += "0" }
        return s
    }
}
