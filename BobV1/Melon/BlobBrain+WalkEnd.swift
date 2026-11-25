//
//  BlobBrain+WalkEnd.swift
//  move-crowd-r2: the hand-off from the end of a walk to the stand (the walk itself is locked; this is the settle after it). Switch `BlobBrain.walkEndSettle`
//  (`-WalkEndSettle 0` / env WALKENDSETTLE=0 = the old hand-off).
//

import Foundation

extension BlobBrain {
    nonisolated(unsafe) static var walkEndSettle: Bool = {
        if let e = ProcessInfo.processInfo.environment["WALKENDSETTLE"] { return e != "0" }
        if DevArgs.enabled, UserDefaults.standard.object(forKey: "WalkEndSettle") != nil { return UserDefaults.standard.integer(forKey: "WalkEndSettle") != 0 }
        return false
    }()
}
