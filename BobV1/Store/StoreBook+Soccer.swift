//
//  StoreBook+Soccer.swift
//  Save migration for the soccer round: a player who owned footballs owns soccer balls instead (placed pieces are mapped by `DecorKind`'s decoder).
//

import Foundation

extension StoreBook {
    /// Folds the removed `decor-football` count into `decor-soccerball` (nothing else changes).
    static func migrateSoccer(_ s: Saved) -> Saved {
        var out = s
        if let n = out.counts["decor-football"] {
            out.counts["decor-football"] = nil
            out.counts[DecorKind.soccerball.storeID, default: 0] += n
        }
        return out
    }
}
