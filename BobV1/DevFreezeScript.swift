//
//  DevFreezeScript.swift
//  Capture aid (dev builds / simulator only, never an archive): `-FreezeScript "wait:6;call:1;wait:1.5;cancel;wait:30"` runs those steps on the home
//  stage, and `-FreezeProbe 1` logs every Jelmiko's brain state once a second as `[freeze] ...` (the come-here-freeze-r1 repro matrix).
//  Steps: wait:<s>  call:<id>  callall  callids:<a,b>  cancel (the Cancel pill)  release (Let go)  tick:<id> (log now).
//

import Foundation

@MainActor
enum DevFreezeScript {
    static func line(_ care: GameCare) -> String {
        var parts = ["ticks:\(ResumeFrames.ticks)", "ph:\(care.focus.phase)", "ids:\(care.focusGroup.ids)", "saved:\(care.focusGroup.saved.mapValues { $0 ? 1 : 0 })"]
        for id in 0..<care.jellies.count {
            guard let b = care.brainFor(id) else { continue }
            parts.append("[\(id) scr:\(b.scriptKindName) job:\(b.job == nil ? "-" : "Y") cmd:\(b.commanded ? 1 : 0) res:\(b.reserved ? 1 : 0) idleBlk:\(b.idleBlocked ? 1 : 0) auto:\(b.autonomy ? 1 : 0) pend:\(b.pending == nil ? 0 : 1) act:\(b.activity) pos:\(String(format: "%.2f,%.2f", b.position.x, b.position.y))]")
        }
        return parts.joined(separator: " ")
    }

    static func run(care: GameCare, script: String?, probe: Bool, sleep: @escaping (Double) async -> Void) async {
        guard DevArgs.enabled else { return }
        if UserDefaults.standard.object(forKey: "FreezeFix") != nil, UserDefaults.standard.integer(forKey: "FreezeFix") == 0 { FocusGroup.handBackFix = false; FocusGroup.netEnabled = false; NSLog("[freeze] FIX OFF (hand-back and safety net)") }          // -FreezeFix 0: the build as it was
        if probe {
            Task { @MainActor in
                var t = 0
                while true { NSLog("[freeze] t=%d %@", t, line(care)); t += 1; try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        guard let script else { return }
        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let kv = step.split(separator: ":", maxSplits: 1).map(String.init)
            let arg = kv.count > 1 ? kv[1] : ""
            NSLog("[freeze] step %@ | %@", step, line(care))
            switch kv[0] {
            case "wait": await sleep(Double(arg) ?? 1)
            case "call": care.comeHere(jelly: Int(arg) ?? 0)
            case "callall": care.comeHereEveryone()
            case "callids": care.beginFocus(ids: arg.split(separator: ",").compactMap { Int($0) })
            case "cancel": care.cancelGroupAction()
            case "release": care.release()
            default: break
            }
        }
    }
}
