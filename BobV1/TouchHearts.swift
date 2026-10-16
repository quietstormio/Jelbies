//
//  TouchHearts.swift
//  Little hearts that float up from the finger while Bob is enjoying being petted. Reads `TouchPlay.hearts` (screen fractions) every
//  frame; draws nothing (and costs nothing) when there are none. Not hit-testable.
//

import SwiftUI

struct TouchHeartsView: View {
    let play: TouchPlay

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: play.hearts.isEmpty)) { tl in
            Canvas { ctx, size in
                let now = CACurrentMediaTime()
                guard let sym = ctx.resolveSymbol(id: 0) else { return }
                for h in play.hearts {
                    let a = (now - h.born) / TouchPlay.heartLife
                    guard a >= 0, a < 1 else { continue }
                    let rise = CGFloat(a) * 0.14
                    let x = (CGFloat(h.x) + CGFloat(h.dx) * CGFloat(a)) * size.width
                    let y = (CGFloat(h.y) - rise) * size.height
                    var c = ctx
                    c.opacity = a < 0.15 ? a / 0.15 : (1 - a) / 0.85
                    c.translateBy(x: x, y: y)
                    let s = 0.6 + 0.5 * min(1, a * 4)
                    c.scaleBy(x: s, y: s)
                    c.draw(sym, at: .zero)
                }
                _ = tl.date
            } symbols: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.56))
                    .tag(0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
