//
//  AntennaFit.swift
//  The hat rule of the green Jelmiko's two antennas (AntennaBean), computed from the real wardrobe geometry like Teddy's ears (TeddyFit):
//    1. an ENCLOSING hat (beanie, top hat, party hat, cap ...) covers the top of the head: the antennas tuck away (shrink onto their bases, as Teddy's covered ears do) and come back when it comes off
//    2. the headbands that already carry their own antennae or ears (bee antennae, cat / frog / bunny ears, headphones): the body antennas tuck, so there are never four of them
//    3. an open piece (bow, flower clip, visor, sweatband ...) that clears the antennas and their swing leaves them out; one that touches them tucks them
//

import simd
import Foundation

nonisolated enum AntennaFit {
    /// Headbands that are antennae / ears themselves.
    static let bands: Set<String> = TeddyFit.earBands.union(["bee_antennae"])
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Bool] = [:]
    static func clearCache() { lock.lock(); cache = [:]; lock.unlock() }

    /// True when the antennas must tuck away under what is worn (`worn` = the shown art ids).
    static func tucked(worn: [String]) -> Bool {
        let key = worn.sorted().joined(separator: ",")
        lock.lock(); let c = cache[key]; lock.unlock()
        if let c { return c }
        var out = false
        let body = WearBody.shared
        var hats: [(WearPrepared, [SIMD3<Float>])] = []
        for w in worn {
            if bands.contains(w) { out = true; break }
            guard let look = WearLook.pieces.first(where: { $0.art == w }), look.slot == .head, let piece = WearMeshes.prepare(look, body: body) else { continue }
            if piece.crownEnclosing { out = true; break }
            hats.append((piece, TeddyFit.surfacePoints(piece)))
        }
        if !out, !hats.isEmpty {
            let pts = AntennaBean.visiblePoints()
            for (piece, cloud) in hats where TeddyFit.clips(pts, piece: piece, cloud: cloud, margin: TeddyFit.bandClearance) { out = true; break }
        }
        lock.lock(); cache[key] = out; lock.unlock()
        return out
    }
}
