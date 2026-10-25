//
//  GroomChrome.swift
//  The Groomer's screen furniture: the picker card (who goes, three tiers), the shop-front cut-scene (a soft illustrated storefront drawn in SwiftUI shapes: striped
//  awning, round window with a bathtub, "Jelly Spa" sign, bubbles from the chimney and the door, steam when the dryer runs, the shop bouncing to the bell and
//  wobbling to the washing; tap to skip), the "So fresh!" banner and the blocked-entry toast. Views only; GameCare+Groom.swift owns the rules.
//  Reduce Motion: no wobble, bounce or drift; the scene just fades in and out.
//

import SwiftUI

struct GroomChrome: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    @Environment(\.accessibilityReduceMotion) private var reduceEnv
    private var groom: GroomTrip { care.groom }
    private var reduce: Bool { reduceEnv || A11ySettings.shared.reduceMotion }

    private func tint(_ id: Int) -> Color {
        let t = JellyRoster.tint(care.jelly(id)?.character ?? id)
        return Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
    }

    var body: some View {
        ZStack {
            if groom.picking { picker }
            if groom.showsShop {
                GroomShopScene(groom: groom, reduce: reduce)
                    .opacity(Double(groom.shopAlpha)).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture { groom.skip() }
                    .accessibilityElement(children: .ignore).accessibilityLabel("The Jelly Spa. \(groom.tier.name).")
                    .accessibilityHint("Double tap to skip").accessibilityAddTraits(.isButton).accessibilityIdentifier("groom-shop")
                    .transition(.opacity)
            }
            if groom.celebrating {
                let late = groom.cheerT > GroomTuning.cheerSeconds - 0.8
                VStack {
                    Text(groom.tier.banner).font(SK.font(26, .black)).foregroundStyle(SK.ink)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 7, y: 3))
                        .scaleEffect(reduce || groom.cheerT > 0.35 ? 1 : 0.8)
                        .accessibilityIdentifier("groom-banner")
                    Spacer()
                }
                .padding(.top, vsc == .compact ? 14 : 70)
                .opacity(late ? 0 : 1).animation(.easeOut(duration: 0.4), value: late)
                .animation(reduce ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: groom.cheerT > 0.35)
                .allowsHitTesting(false).transition(.opacity)
            }
            if let t = groom.toast {
                VStack {
                    Spacer()
                    HStack {
                        Text(t).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(SK.cream).shadow(color: SK.shadow.opacity(0.22), radius: 6, y: 2))
                            .accessibilityIdentifier("groom-toast")
                        Spacer(minLength: 20)
                    }
                    .padding(.leading, 16).padding(.bottom, 24)
                }
                .allowsHitTesting(false).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: groom.toast)
        .animation(.easeInOut(duration: 0.2), value: groom.picking)
        .onChange(of: groom.toast) { _, t in if let t { A11yAnnounce.say(t) } }
        .allowsHitTesting(groom.picking || groom.showsShop || groom.toast != nil)
    }

    // MARK: the picker

    private var picker: some View {
        ZStack {
            Color(red: 0.30, green: 0.20, blue: 0.14).opacity(0.28).ignoresSafeArea().onTapGesture { groom.cancelPicker() }.accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                pickerContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { pickerContent }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 460, maxHeight: vsc == .compact ? 330 : 620)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.25), radius: 10, y: 4))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("groom-picker")
        }
        .transition(.opacity)
    }

    private var pickerContent: some View {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "bubbles.and.sparkles.fill").font(.system(size: 20, weight: .heavy)).foregroundStyle(SK.ink)
                        Text("Jelly Spa").font(SK.font(22, .black)).foregroundStyle(SK.ink)
                        Spacer(minLength: 0)
                        DropsPill(wallet: care.bath.wallet)
                    }
                    Text("A fresh, shiny clean-up without the scrubbing. Price is per Jelbie.").font(SK.font(13, .bold)).foregroundStyle(SK.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        ForEach(care.jellies, id: \.id) { j in
                            let on = groom.picked.contains(j.id)
                            Button { AudioHub.shared.uiTap(); groom.toggle(j.id) } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(tint(j.id)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5))
                                    Text(j.name).font(SK.font(14, .heavy)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .bold)).foregroundStyle(SK.ink)
                                }
                                .padding(.horizontal, 9).frame(minHeight: 44)
                                .background(Capsule().fill(on ? SK.honey : Color.white.opacity(0.8)))
                            }
                            .buttonStyle(.plain).accessibilityLabel(j.name).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("groom-pick-\(j.id)")
                        }
                        Spacer(minLength: 0)
                    }
                    ForEach(GroomTier.allCases) { tier in
                        let total = tier.total(count: groom.picked.count)
                        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); care.startGroom(tier) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tier.symbol).font(.system(size: 22, weight: .heavy)).foregroundStyle(SK.ink)
                                    .frame(width: 50, height: 50).background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tier == .royal ? SK.honey : tier == .spa ? SK.pink : SK.sky))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tier.name).font(SK.font(18, .black)).foregroundStyle(SK.ink)
                                    Text(tier.blurb).font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                VStack(spacing: 0) {
                                    Text("\(total)").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                                    Text("Drops").font(SK.font(11, .heavy)).foregroundStyle(SK.muted)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 66)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.85)))
                            .opacity(total <= care.bath.wallet.count ? 1 : 0.65)
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(tier.name), \(total) Drops. \(tier.blurb)").accessibilityIdentifier("groom-tier-\(tier.rawValue)")
                    }
                    if let r = groom.refusal {
                        Text(r).font(SK.font(14, .heavy)).foregroundStyle(SK.pinkStrong).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("groom-refusal")
                    }
                    Button { AudioHub.shared.uiTap(); groom.cancelPicker() } label: {
                        Text("Not now").font(SK.font(16, .heavy)).foregroundStyle(SK.muted).padding(.horizontal, 22).frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.8)))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("groom-cancel")
                }
                .padding(16)
    }
}

// MARK: - the shop front

/// The Jelly Spa seen from the street: soft, rounded, pastel. All shapes; `W` is the shop's width and everything is placed in units of it.
struct GroomShopScene: View {
    let groom: GroomTrip
    let reduce: Bool

    private static let skyTop = Color(red: 0.75, green: 0.90, blue: 0.96), skyLow = Color(red: 0.99, green: 0.95, blue: 0.89)
    private static let roof = Color(red: 0.49, green: 0.77, blue: 0.81), wall = Color(red: 1.0, green: 0.95, blue: 0.92)
    private static let awnPink = Color(red: 0.95, green: 0.61, blue: 0.71), glass = Color(red: 0.80, green: 0.92, blue: 0.97)
    private static let door = Color(red: 0.62, green: 0.85, blue: 0.69), doorDeep = Color(red: 0.49, green: 0.75, blue: 0.57)
    private static let hill = Color(red: 0.75, green: 0.89, blue: 0.71), brick = Color(red: 0.93, green: 0.72, blue: 0.66)

    var body: some View {
        GeometryReader { g in
            let W = min(g.size.width * 0.8, g.size.height * 0.86 / 1.05)
            ZStack {
                LinearGradient(colors: [Self.skyTop, Self.skyLow], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                clouds(g.size)
                Ellipse().fill(Self.hill).frame(width: g.size.width * 1.7, height: g.size.height * 0.5)
                    .position(x: g.size.width / 2, y: g.size.height * 0.5 + W * 0.525 + g.size.height * 0.25 - W * 0.02)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
                    let t = reduce ? 0 : tl.date.timeIntervalSinceReferenceDate
                    let st = Double(groom.shopT)
                    let washing = groom.phase == .shop
                    // bounce to the bell at the start, wobble to the washing while it runs
                    let bounce = reduce ? 0 : -abs(sin(st * 13)) * exp(-st * 3.2) * W * 0.035
                    let wob = reduce || !washing ? 0 : sin(t * 5.2) * 0.9 + sin(t * 11.3) * 0.25
                    let squash = reduce || !washing ? 0 : sin(t * 9.1) * 0.006
                    shop(W: W, t: t, st: st)
                        .frame(width: W, height: W * 1.05)
                        .overlay(alignment: .topLeading) {          // (an overlay: the bubbles rise above the shop's box without changing its size)
                            Canvas { ctx, _ in ctx.translateBy(x: 0, y: W * 0.6); drawBubbles(&ctx, W: W, t: t) }
                                .frame(width: W, height: W * 1.65).offset(y: -W * 0.6).allowsHitTesting(false)
                        }
                        .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                        .rotationEffect(.degrees(wob), anchor: .bottom)
                        .offset(y: bounce)
                }
                .frame(width: W, height: W * 1.05)
                .position(x: g.size.width / 2, y: g.size.height * 0.5 - W * 0.02)
                VStack {
                    Spacer()
                    Text("Tap to skip").font(SK.font(12, .heavy)).foregroundStyle(SK.muted.opacity(0.7)).padding(.bottom, 26)
                }
            }
        }
    }

    private func clouds(_ s: CGSize) -> some View {
        ZStack {
            cloud(w: s.width * 0.28).position(x: s.width * 0.18, y: s.height * 0.14)
            cloud(w: s.width * 0.22).position(x: s.width * 0.84, y: s.height * 0.22)
        }
    }
    private func cloud(w: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.85)).frame(width: w, height: w * 0.32)
            Circle().fill(Color.white.opacity(0.85)).frame(width: w * 0.36).offset(x: -w * 0.1, y: -w * 0.14)
            Circle().fill(Color.white.opacity(0.85)).frame(width: w * 0.28).offset(x: w * 0.12, y: -w * 0.1)
        }
    }

    private func at(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ W: CGFloat) -> some ViewModifier { Place(x: x * W, y: y * W, w: w * W, h: h * W) }
    private struct Place: ViewModifier {
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        func body(content: Content) -> some View { content.frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2) }
    }

    @ViewBuilder
    private func shop(W: CGFloat, t: Double, st: Double) -> some View {
        let ink = SK.ink
        ZStack(alignment: .topLeading) {
            // chimney + roof + body
            RoundedRectangle(cornerRadius: W * 0.02, style: .continuous).fill(Self.brick).modifier(at(0.68, 0.03, 0.13, 0.22, W))
            Capsule().fill(Color.white.opacity(0.9)).modifier(at(0.665, 0.02, 0.16, 0.035, W))
            RoundedRectangle(cornerRadius: W * 0.05, style: .continuous).fill(Self.wall)
                .overlay(RoundedRectangle(cornerRadius: W * 0.05, style: .continuous).strokeBorder(Color.white, lineWidth: 3))
                .shadow(color: SK.shadow.opacity(0.18), radius: W * 0.02, y: W * 0.012).modifier(at(0.04, 0.27, 0.92, 0.69, W))
            Capsule().fill(Self.roof).shadow(color: SK.shadow.opacity(0.15), radius: W * 0.015, y: W * 0.01).modifier(at(-0.02, 0.17, 1.04, 0.14, W))
            // sign
            ZStack {
                RoundedRectangle(cornerRadius: W * 0.04, style: .continuous).fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: W * 0.04, style: .continuous).strokeBorder(SK.honeyDeep, lineWidth: 3))
                HStack(spacing: W * 0.015) {
                    Image(systemName: "sparkle").font(.system(size: W * 0.045, weight: .heavy)).foregroundStyle(SK.honeyDeep)
                    Text("Jelly Spa").font(SK.font(W * 0.082, .black)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                    Image(systemName: "sparkle").font(.system(size: W * 0.045, weight: .heavy)).foregroundStyle(SK.honeyDeep)
                }.padding(.horizontal, W * 0.02)
            }.modifier(at(0.2, 0.315, 0.6, 0.14, W))
            // striped awning
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: W * 0.05, bottomTrailingRadius: W * 0.05, topTrailingRadius: 0, style: .continuous)
                        .fill(i % 2 == 0 ? Self.awnPink : Color.white)
                }
            }.shadow(color: SK.shadow.opacity(0.15), radius: W * 0.01, y: W * 0.01).modifier(at(0.02, 0.47, 0.96, 0.095, W))
            // round window with a bathtub
            ZStack {
                Circle().fill(SK.honey)
                Circle().fill(Self.glass).padding(W * 0.02)
                tub(W: W)
            }.modifier(at(0.09, 0.6, 0.35, 0.35, W))
            // door (opens a little with the bell)
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: W * 0.15, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: W * 0.15, style: .continuous).fill(Self.doorDeep)
                UnevenRoundedRectangle(topLeadingRadius: W * 0.15, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: W * 0.15, style: .continuous)
                    .fill(Self.door).padding(.leading, W * 0.012).padding(.trailing, W * 0.012 + W * 0.05 * CGFloat(min(st / 0.6, 1)))
                Circle().fill(SK.honeyDeep).frame(width: W * 0.03).offset(x: W * 0.085 - W * 0.05 * CGFloat(min(st / 0.6, 1)), y: W * 0.03)
            }.modifier(at(0.58, 0.6, 0.3, 0.36, W))
            // bubbles out of the chimney and the door, steam when the dryer runs
            if groom.dryerOn { steam(W: W, t: t) }
            // the tier name, small
            Text(groom.tier.name).font(SK.font(W * 0.05, .heavy)).foregroundStyle(ink)
                .padding(.horizontal, W * 0.03).padding(.vertical, W * 0.008).background(Capsule().fill(Color.white.opacity(0.9)))
                .modifier(at(0.3, 0.98, 0.4, 0.06, W)).accessibilityIdentifier("groom-tier-name")
        }
    }

    private func tub(W: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color.white).frame(width: W * 0.04, height: W * 0.012).offset(x: -W * 0.07, y: -W * 0.085)         // the tap
            RoundedRectangle(cornerRadius: W * 0.01).fill(Color.white).frame(width: W * 0.012, height: W * 0.035).offset(x: -W * 0.085, y: -W * 0.07)
            UnevenRoundedRectangle(topLeadingRadius: W * 0.01, bottomLeadingRadius: W * 0.06, bottomTrailingRadius: W * 0.06, topTrailingRadius: W * 0.01, style: .continuous)
                .fill(Color.white).frame(width: W * 0.21, height: W * 0.1).offset(y: W * 0.012)
            ForEach([-1.0, 1.0], id: \.self) { s in Circle().fill(Color.white).frame(width: W * 0.025).offset(x: CGFloat(s) * W * 0.07, y: W * 0.074) }
            ForEach(0..<3, id: \.self) { i in Circle().fill(Self.glass.opacity(0.9)).overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5)).frame(width: W * (0.034 - CGFloat(i) * 0.006)).offset(x: CGFloat(i - 1) * W * 0.05, y: -W * 0.04 - CGFloat(i % 2) * W * 0.02) }
        }
    }

    /// Soap bubbles rising and drifting, each a pure function of time (no state): from the chimney top and from the door.
    private func drawBubbles(_ ctx: inout GraphicsContext, W: CGFloat, t: Double) {
        let sources: [(CGPoint, Int, CGFloat)] = [(CGPoint(x: 0.745 * W, y: 0.03 * W), 9, 0.55 * W), (CGPoint(x: 0.73 * W, y: 0.62 * W), 5, 0.3 * W)]
        for (src, count, rise) in sources {
            for i in 0..<count {
                let f = Double(i)
                let speed = 0.16 + 0.05 * Double((i * 7) % 5)
                let ph = reduce ? (f + 1) / Double(count + 1) : (t * speed + f * 0.37).truncatingRemainder(dividingBy: 1)
                let r = W * (0.012 + 0.008 * CGFloat((i * 3) % 4))
                let x = src.x + CGFloat(sin(t * 1.4 + f * 1.9)) * W * 0.03 * (reduce ? 0 : 1) + CGFloat(((i * 5) % 7) - 3) * W * 0.012 + CGFloat(ph) * W * 0.05
                let y = src.y - CGFloat(ph) * rise
                let a = sin(ph * .pi) * 0.85
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(a * 0.45)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(Color(red: 0.6, green: 0.85, blue: 0.95).opacity(a)), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.4, height: r * 0.4)), with: .color(Color.white.opacity(a)))
            }
        }
    }

    /// Soft steam puffs out of the roof vent (left of the sign) while the dryer runs.
    private func steam(W: CGFloat, t: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: W * 0.01).fill(Self.roof.opacity(0.9)).frame(width: W * 0.07, height: W * 0.05).position(x: W * 0.17, y: W * 0.165)
            ForEach(0..<5, id: \.self) { i in
                let ph = reduce ? Double(i) / 5 : (t * 0.45 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                Circle().fill(Color.white).frame(width: W * (0.05 + 0.07 * CGFloat(ph)))
                    .opacity((1 - ph) * 0.8)
                    .position(x: W * (0.17 - 0.05 * CGFloat(ph)) + CGFloat(sin(t * 2 + Double(i))) * W * 0.012 * (reduce ? 0 : 1), y: W * (0.14 - 0.14 * CGFloat(ph)))
            }
        }
        .frame(width: W, height: W * 1.05).allowsHitTesting(false)
    }
}
