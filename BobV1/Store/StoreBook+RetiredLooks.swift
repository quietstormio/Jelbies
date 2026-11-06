//
//  StoreBook+RetiredLooks.swift
//  Looks removed from the game (`WearLook.retired`, the gold chain): a save that owns or wears one has it unowned and taken off every Jelbie silently on load
//  (no refund). Idempotent. The enum case stays so the old save still decodes.
//

import Foundation

extension StoreBook {
    static func dropRetiredLooks(_ s: Saved) -> (saved: Saved, changed: Bool) {
        var out = s, changed = false
        for l in WearLook.retired {
            let ids: Set<String> = [l.rawValue, l.row.storeID]
            changed = changed || out.wearables.contains { ids.contains($0) } || out.worn.values.contains { $0.values.contains { ids.contains($0) } }
            out.wearables.removeAll { ids.contains($0) }
            out.awarded?.removeAll { ids.contains($0) }
            for k in out.worn.keys { out.worn[k] = out.worn[k]?.filter { !ids.contains($0.value) } }
        }
        return (out, changed)
    }
}
