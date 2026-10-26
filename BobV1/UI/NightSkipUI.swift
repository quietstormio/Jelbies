//
//  NightSkipUI.swift
//  The soft "Sleep until morning" moon button, the small "Day N" chip, and the cut-scene's cover (dim -> starry night with Zzz). See GameCare+SkipNight.swift.
//

import SwiftUI

/// "Sleep until morning": a small cream moon disc; once every Jelbie is asleep it grows a label (the goodnight flow's offer).
struct SleepUntilMorningButton: View {
    let care: GameCare
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if care.nightSkipOffered {
                let all = care.rosterAllAsleep
                Button { care.startNightSkip() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill").font(.system(size: 15, weight: .semibold))
                        if all { Text("Sleep until morning").font(SK.font(13, .bold)).lineLimit(1).minimumScaleFactor(0.7) }
                    }
                    .foregroundStyle(Color(red: 0.36, green: 0.32, blue: 0.55))
                    .padding(.horizontal, all ? 14 : 0).frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(Color(red: 0.93, green: 0.91, blue: 0.98)).opacity(0.94))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.3), value: all)
                .accessibilityLabel("Sleep until morning")
                .accessibilityIdentifier("sleep-until-morning")
                .transition(.opacity)
            }
        }
    }
}

/// "Day 3": small and quiet.
struct DayChip: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if DayClock.shared.showsDay {
                Text("Day \(DayClock.shared.day)")
                    .font(SK.font(12, .heavy)).foregroundStyle(SK.ink.opacity(0.7)).monospacedDigit()
                    .padding(.horizontal, 10).frame(minHeight: 26)
                    .background(Capsule().fill(SK.cream.opacity(0.8)))
                    .accessibilityLabel("Day \(DayClock.shared.day)")
                    .accessibilityIdentifier("day-chip")
            }
        }
    }
}

/// The cut-scene cover: navy dim, then stars, a moon and drifting Zzz. A tap anywhere skips the cut-scene.
struct NightSkipVeil: View {
    let care: GameCare
    var body: some View {
        let s = care.nightSkip
        ZStack {
            if s.active || s.cover > 0.001 {
                Color(red: 0.05, green: 0.06, blue: 0.16).opacity(s.cover).ignoresSafeArea()
                if s.stars > 0.001 && !s.reduce {
                    StarsAndZzz().opacity(s.stars).ignoresSafeArea()
                }
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(s.active)
        .onTapGesture { care.skipNightCutscene() }
        .accessibilityHidden(!s.active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.active ? "Sleeping until morning. Tap to skip." : "")
    }
}

private struct StarsAndZzz: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height, u = min(w, h) / 400
                ZStack {
                    Canvas { g, size in
                        var seed: UInt64 = 0x9E3779B97F4A7C15
                        func r() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
                        for i in 0..<70 {
                            let x = r() * size.width, y = r() * size.height * 0.8, rad = (0.8 + r() * 1.8) * u, ph = r() * 6.28
                            let a = 0.45 + 0.45 * sin(t * (0.8 + Double(i % 5) * 0.25) + ph)
                            g.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(.white.opacity(a)))
                        }
                    }
                    Image(systemName: "moon.fill").font(.system(size: 64 * u)).foregroundStyle(Color(red: 1, green: 0.95, blue: 0.75))
                        .shadow(color: Color(red: 1, green: 0.95, blue: 0.7).opacity(0.5), radius: 18 * u)
                        .position(x: w * 0.74, y: h * 0.2)
                    ForEach(0..<3, id: \.self) { i in
                        let p = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Text(i == 1 ? "Zz" : "Z").font(.system(size: (26 + Double(i) * 9) * u, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85 * sin(p * .pi)))
                            .position(x: w * (0.36 + 0.1 * Double(i)) + 12 * u * sin(p * 5), y: h * (0.62 - 0.22 * p))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
