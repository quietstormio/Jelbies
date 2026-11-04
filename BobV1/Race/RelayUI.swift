//
//  RelayUI.swift
//  The relay's screen furniture: the title and "who runs" words, the baton (a small glowing jelly drop that rides over each team's runner and hops
//  from head to head at a handoff), the soft "Tag!" sparkle at the line, and the team results card. All 2D over the 3D track; the bodies and the
//  floor markers are the stage's.
//

import SwiftUI
import simd

enum RelayText {
    static func runner(_ race: RaceFlow) -> String {
        guard let plan = race.relayPlan else { return "" }
        return plan.teams[0][min(race.ui.leg, 2)].name
    }
    static func title(_ race: RaceFlow) -> String {
        let course = race.ui.course == .puddle ? "" : " · \(race.ui.course.title)"
        if race.ui.phase == .results { return "Relay\(course)" }
        return "Relay · Leg \(min(race.ui.leg, 2) + 1) of 3 · \(runner(race))\(course)"
    }
}

/// The baton and the tag sparkle.
struct RelayOverlay: View {
    let care: GameCare
    private static let colours: [Color] = [Color(red: 1.0, green: 0.52, blue: 0.70), Color(red: 0.36, green: 0.80, blue: 0.80), Color(red: 1.0, green: 0.76, blue: 0.30)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            Canvas { ctx, size in
                guard let drop = ctx.resolveSymbol(id: 0), let spark = ctx.resolveSymbol(id: 1) else { return }
                let rb = care.raceBook.relay
                guard rb.teams.count == 3, size.width > 1 else { return }
                let vp = GameCamera.camera(aspect: Float(size.width / max(size.height, 1)), race: 1, raceFollow: care.raceBook.follow).viewProj
                func project(_ w: SIMD3<Float>) -> CGPoint? {
                    let q = vp * SIMD4<Float>(w, 1)
                    guard q.w > 1e-4 else { return nil }
                    return CGPoint(x: CGFloat(q.x / q.w * 0.5 + 0.5) * size.width, y: CGFloat(1 - (q.y / q.w * 0.5 + 0.5)) * size.height)
                }
                func head(_ a: JellyActor) -> SIMD3<Float> { let c = a.sim.centroid(); return SIMD3(c.x, c.y + Float(BlobShape.H) * 0.62, c.z) }
                for t in 0..<3 {
                    let bt = rb.batons[t]
                    let hold = rb.teams[t][min(rb.active[t], 2)]
                    var w = head(hold)
                    if bt.age < 1, let f = bt.from, let to = bt.to {
                        let e = max(0, bt.age), a = head(f), b = head(to)
                        w = a + (b - a) * e + SIMD3(0, 0.9 * sinf(.pi * e), 0)
                    }
                    guard let p = project(w) else { continue }
                    let r: CGFloat = t == 0 ? 11 : 8
                    var c = ctx
                    c.opacity = 0.35
                    c.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.7, y: p.y - r * 1.7, width: r * 3.4, height: r * 3.4)), with: .color(Self.colours[t]))
                    c.opacity = 1
                    c.translateBy(x: p.x, y: p.y); c.scaleBy(x: r / 16, y: r / 16)
                    c.draw(drop, at: .zero)
                }
                for tag in rb.tags {
                    guard let p = project(tag.world) else { continue }
                    let k = CGFloat(tag.age / 0.9)
                    for i in 0..<6 {
                        let ang = Double(i) / 6 * 2 * .pi + 0.4
                        var c = ctx
                        c.opacity = Double(1 - k)
                        c.translateBy(x: p.x + CGFloat(cos(ang)) * 46 * k, y: p.y + CGFloat(sin(ang)) * 30 * k - 14)
                        c.scaleBy(x: 0.7 + 0.5 * (1 - k), y: 0.7 + 0.5 * (1 - k))
                        c.draw(spark, at: .zero)
                    }
                }
            } symbols: {
                Image(systemName: "drop.fill").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white).shadow(color: .yellow, radius: 4).tag(0)
                Image(systemName: "sparkle").font(.system(size: 20, weight: .heavy)).foregroundStyle(Color(red: 1, green: 0.88, blue: 0.4)).tag(1)
            }
            .overlay(alignment: .top) { tagWord }
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }

    /// "Tag!" for the player's own handoff.
    @ViewBuilder private var tagWord: some View {
        if let t = care.raceBook.relay.tags.last(where: { $0.player }), t.age < 0.8 {
            Text("Tag!")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: FocusStyle.pink.opacity(0.9), radius: 0, x: 0, y: 3)
                .opacity(Double(1 - t.age / 0.8))
                .scaleEffect(1 + CGFloat(t.age) * 0.3)
                .padding(.top, 150)
        }
    }
}

/// The team results: 1st / 2nd / 3rd, the prize, "Back home".
struct RelayResultsCard: View {
    let race: RaceFlow
    let home: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    private var tight: Bool { vsc == .compact }
    private func ordinal(_ p: Int) -> String { p == 1 ? "1st" : p == 2 ? "2nd" : "3rd" }
    private func medal(_ p: Int) -> Color {
        p == 1 ? Color(red: 0.98, green: 0.80, blue: 0.35) : p == 2 ? Color(red: 0.80, green: 0.84, blue: 0.90) : Color(red: 0.90, green: 0.68, blue: 0.52)
    }

    var body: some View {
        VStack(spacing: tight ? 6 : 14) {
            Text(race.ui.playerPlace == 1 ? "Your team won!" : "Relay finished!")
                .playFont(tight ? 24 : 30, .heavy)
                .foregroundStyle(CareMenu.brown)
            VStack(spacing: tight ? 2 : 8) {
                ForEach(Array(race.relayRows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 12) {
                        Text(ordinal(r.place)).playFont(17, .heavy).foregroundStyle(CareMenu.brown)
                            .frame(minWidth: 52, minHeight: 34).background(Capsule().fill(medal(r.place)))
                        Text(r.team).playFont(20, r.isPlayer ? .heavy : .semibold).foregroundStyle(CareMenu.brown)
                        Spacer()
                        Text(r.time.map { String(format: "%.1f s", $0) } ?? "-").playFont(18, .semibold).monospacedDigit().foregroundStyle(CareMenu.brown.opacity(0.85))
                    }
                    .padding(.horizontal, 10).padding(.vertical, tight ? 2 : 5)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(r.isPlayer ? FocusStyle.pink.opacity(0.28) : Color.clear))
                }
            }
            HStack(spacing: 8) {
                JellyCoinIcon(size: 22)
                Text("+\(race.ui.earned) JellyCoins").playFont(20, .bold).foregroundStyle(CareMenu.brown)
            }
            if race.ui.waddleGain > 0.0005 {
                Text("Your runners got a little quicker").playFont(14, .medium).foregroundStyle(CareMenu.brown.opacity(0.85))
            }
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                home()
            } label: {
                Text("Back home").playFont(20, .bold).foregroundStyle(.white)
                    .padding(.horizontal, 30).padding(.vertical, tight ? 8 : 12)
                    .background(Capsule().fill(SK.pinkStrong).shadow(color: FocusStyle.shadow.opacity(0.25), radius: 6, y: 3))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("race-home")
        }
        .padding(.horizontal, 22).padding(.vertical, tight ? 10 : 20)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(CareMenu.cream).shadow(color: FocusStyle.shadow.opacity(0.3), radius: 6, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("relay-card")
    }
}
