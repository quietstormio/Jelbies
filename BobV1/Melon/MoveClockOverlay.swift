//
//  MoveClockOverlay.swift
//  move-chooser-r2: `-MoveClockOverlay 1` (DevArgs builds only) draws the game clock the logs use (`variety.now` of body 0: the `t=` of the [push] / [emotespot] lines) in seconds, one decimal,
//  small in the top-left corner, so a video strip is cut by reading the picture. Nothing else reads it.
//

import SwiftUI

nonisolated enum MoveClockOverlay {
    nonisolated(unsafe) static var on: Bool = DevArgs.enabled && UserDefaults.standard.integer(forKey: "MoveClockOverlay") == 1
    nonisolated(unsafe) static var t: Float = 0
}

struct MoveClockView: View {
    var body: some View {
        TimelineView(.animation) { _ in
            Text(String(format: "%.1f", MoveClockOverlay.t))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.black.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 50).padding(.leading, 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
