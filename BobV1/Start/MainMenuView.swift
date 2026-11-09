//
//  MainMenuView.swift
//  The title screen (Cloud Jelly): white sky with slowly drifting Mist bubbles, the Jelbies logo bobbing in the top third, and two jelly buttons.
//  Continue (only with a save) is the blue primary; New Game is the white secondary, confirmed on a white rimmed card when it would wipe a save.
//

import SwiftUI

/// One composition for every screen: the iPhone portrait design (logo on top, Continue / New Game stacked, the face peeking from the bottom),
/// grown to FILL the screen. The element scale `s` (logo, buttons, text, spacing) is limited by the width (logo <= ~83 %) and by the height left above
/// the face; the face's own scale spans the width but never hides its eyes. At the 440x956 design size every number equals the approved portrait look.
/// `s` never goes below `minScale` (buttons stay >= 44 pt tall); on a very short screen the face is pushed down (peeks less) instead.
struct MenuMetrics {
    static let minScale: CGFloat = 0.72          // 62 * 0.72 = 44.6 pt: the smaller (New Game) button keeps a 44 pt tap height
    var s: CGFloat, titleTop: CGFloat, buttonsGap: CGFloat, faceScale: CGFloat, faceTop: CGFloat
    var btnScale: CGFloat, btnWidth: CGFloat          // buttons: tap-height scale, and their width (pills widen on a short, wide screen)

    init(w: CGFloat, h: CGFloat, hasSave: Bool) {
        let aspect = w / h
        // Where the rim of the face starts: 65 % of the height on an iPhone portrait, lower on wider screens (more room for the stack).
        var top = h * (0.6514 + 0.0486 * min(1, max(0, (aspect - 0.46) / 0.29)))
        let titleUnits = 364 / 0.96 * 307 / 620, btnUnits: CGFloat = hasSave ? 74 + 8 + 20 + 62 + 6 : 74 + 8          // 188, 170 (82 with one button)
        let content = titleUnits + btnUnits
        let faceGap = h * 0.015, minGaps = h * 0.07
        let fitH = (top - faceGap - minGaps) / content
        let pad = min(w, h) > 600          // iPad-sized window: scale from the short side so a wide window does not blow the art up
        var raw = min(pad ? min(w, h) / 440 : w / 440, fitH)
        if aspect > 1 { raw = min(raw, 0.55 * w / 379, 0.40 * w / 300) }          // landscape: the logo and buttons stay a sensible share of the width
        let sc = max(raw, Self.minScale)
        if raw < Self.minScale { top = max(top, content * sc + minGaps + 14 * sc) }          // short screen: the face peeks less
        let free = max(0, top - faceGap - content * sc)
        let topShare = 156.0 / 251.0
        s = sc
        titleTop = max(8, free * topShare)
        buttonsGap = max(4, free * (1 - topShare))
        faceScale = max(1.0, min(4.8 * (pad ? min(w, h) : w) / 440, (0.91 * h - top) / 51.5))
        faceTop = top
        btnScale = sc; btnWidth = 300 * sc
        if pad && aspect > 1 && aspect <= 1.6 {          // iPad landscape: a big face peeks from the bottom and the whole stack (logo + pills) sits ABOVE its rim, so nothing covers the eyes
            let sf = min(0.27 * h / 51.5, 0.46 * w / 102)
            let eyesY = h * 0.93
            let ft = eyesY - 51.5 * sf
            let topPad: CGFloat = 30                                              // clears the status bar
            let avail = ft - 12 - topPad
            let sl = max(0.5, min(0.88 * avail / content, 0.55 * w / 379, 0.40 * w / 300, min(w, h) / 440))
            let freeP = max(0, avail - content * sl)
            s = sl; btnScale = sl; btnWidth = 300 * sl
            titleTop = topPad + freeP * topShare
            buttonsGap = max(4, freeP * (1 - topShare))
            faceScale = sf
            faceTop = ft
        } else if aspect > 1.6 {          // a short, wide screen (iPhone landscape): decouple width from height so the stack spans the screen
            let k: CGFloat = hasSave ? 0.75 : 0.9
            let sf: CGFloat = 3.6                                                // the Jelbie peeks with brows and eyes: ~49 % of the width incl. its rim
            let eyesY = h * 0.92                                                 // eyes ~8 % above the bottom edge
            let ft = eyesY - 51.5 * sf                                           // rim top (the buttons may overlap it, never the brows or eyes)
            let stackBottom = eyesY - 17 * sf - 4 - 8                            // above the brows (8 pt for the bob)
            let pad: CGFloat = 6
            let btnH = btnUnits * k
            let logoH = stackBottom - pad - 6 - btnH
            let sl = min(logoH / titleUnits, 0.55 * w / 379)
            s = sl; btnScale = k; btnWidth = 0.85 * 379 * sl
            titleTop = pad - h * 0.05          // the swing frame has empty room above the mascot: lift the stack so the pills clear the rim
            buttonsGap = max(4, stackBottom - pad - titleUnits * sl - btnH)
            faceScale = sf
            faceTop = ft
        }
    }
}

struct MainMenuView: View {
    let flow: StartFlow
    private let hasSave = StartFlow.hasSave()
    @State private var confirmNew = false
    @State private var loading = false          // Continue / New Game tapped: the spinner replaces the buttons until the screen is swapped
    private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var still: Bool { reduceMotion || A11ySettings.shared.reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let m = MenuMetrics(w: w, h: h, hasSave: hasSave)
            ZStack {
                TitleBackdrop(still: still, size: geo.size, landscape: w > h, palette: theme.palette, scale: m.s, faceScale: m.faceScale, faceTop: m.faceTop)
                    .id(theme.palette.id).transition(.opacity)          // a new theme colour crossfades in
                VStack(spacing: 0) {
                    title(width: 364 * m.s).padding(.top, m.titleTop)
                    buttons(k: m.btnScale).frame(width: m.btnWidth).padding(.top, m.buttonsGap)
                        .opacity(loading ? 0 : 1).disabled(loading)
                        .overlay { if loading { ThemedSpinner(palette: theme.palette).transition(.identity) } }          // same frame as the tap, no fade
                    Spacer(minLength: 0)
                }
                if confirmNew { confirmCard.transition(.opacity) }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: confirmNew)
        .animation(.easeInOut(duration: 0.5), value: theme.selection)
        .onAppear {
            LaunchTiming.mark("menu shown")
            #if targetEnvironment(simulator)
            if hasSave, UserDefaults.standard.object(forKey: "AutoContinue") != nil {          // timing aid: taps Continue after N seconds
                let after = UserDefaults.standard.double(forKey: "AutoContinue")
                Task { @MainActor in try? await Task.sleep(nanoseconds: UInt64(after * 1e9)); flow.continueGame() }
            }
            #endif
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("main-menu")
    }

    /// Show the spinner first, let it commit (the room build after Continue runs on the main thread and would otherwise freeze the menu before the spinner is drawn), then go.
    private func begin(_ go: @escaping @MainActor () -> Void) {
        guard !loading else { return }
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { loading = true }
        Task { @MainActor in try? await Task.sleep(for: .milliseconds(120)); go() }
    }

    private func title(width: CGFloat) -> some View {
        // The still official logo, centred in the same 620x307 frame the old swing video used, so the layout above and below it does not move.
        ZStack {
            Image("JelbiesLogo").resizable().scaledToFit().themedLogo().frame(width: width)
                .shadow(color: theme.palette.shadow, radius: 0, x: 0, y: 7 * width / 364)
        }
        .frame(width: width / 0.96)
        .aspectRatio(620.0 / 307.0, contentMode: .fit)
        .accessibilityElement().accessibilityLabel("Jelbies").accessibilityAddTraits(.isHeader)
    }

    private func buttons(k: CGFloat) -> some View {
        VStack(spacing: 20 * k) {
            if hasSave {
                Button("Continue") { AudioHub.shared.uiTap(); begin { flow.continueGame() } }
                    .buttonStyle(TitleButtonStyle(primary: true, k: k, palette: theme.palette)).accessibilityIdentifier("menu-continue")
                Button("New Game") { AudioHub.shared.uiTap(); confirmNew = true }
                    .buttonStyle(TitleButtonStyle(primary: false, k: k, palette: theme.palette)).accessibilityIdentifier("menu-new")
            } else {
                Button("New Game") { AudioHub.shared.uiTap(); begin { flow.startOver() } }
                    .buttonStyle(TitleButtonStyle(primary: true, k: k, palette: theme.palette)).accessibilityIdentifier("menu-start")
            }
        }
    }

    /// "Start over?" as the white card with the thick Jelly rim, over a pale veil.
    private var confirmCard: some View {
        ZStack {
            Color.white.opacity(0.6).ignoresSafeArea().onTapGesture { confirmNew = false }
            ScrollView {
            VStack(spacing: 12) {
                Text("Start over?").font(CloudTheme.font(26, .bold)).foregroundStyle(CloudTheme.ink).accessibilityAddTraits(.isHeader)
                Text("Your Jelbies, JellyCoins and items will be gone for good once you bring a new Jelbie home. Press and hold the red button to confirm.").font(CloudTheme.font(16, .medium)).foregroundStyle(CloudTheme.ink.opacity(0.8))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Keep playing") { confirmNew = false }
                    .buttonStyle(JellyButtonStyle(.primary, size: 20, minHeight: 48)).accessibilityIdentifier("menu-keep")
                HoldToConfirm(title: "Hold to start over", id: "menu-start-over") { confirmNew = false; begin { flow.startOver() } }
            }
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: 340)
            .cloudCard(radius: 30)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)          // large text / landscape: the card scrolls instead of clipping its buttons
        }
    }
}

/// Title buttons: Continue = white pill with a solid lip; New Game = blue pill with a white rim. Press drops by the lip.
/// Colours come from the theme palette (Sky Blue New Game fill is #3672B3: white text 4.98:1; the mockup's #3E7DC0 is 4.28:1).
private struct TitleButtonStyle: ButtonStyle {
    let primary: Bool
    let k: CGFloat
    let palette: ThemePalette
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        let lip = (primary ? 8 : 6) * k
        let hgt = (primary ? 74 : 62) * k
        configuration.label
            .font(.system(size: (primary ? 27 : 22) * k, weight: primary ? .black : .heavy, design: .rounded))
            .foregroundStyle(primary ? palette.continueText : Color.white)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity).frame(height: hgt)
            .background {
                ZStack {
                    Capsule().fill(palette.lip).offset(y: p ? 0 : lip)
                    Capsule().fill(primary ? Color.white : palette.newGame)
                    if !primary { Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 3 * k) }
                }
            }
            .offset(y: p ? lip : 0)
            .padding(.bottom, lip)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: p)
    }
}

private enum JelbieArt {
    /// The mockup's body path in its own unit space (centre 0,0, ~102 wide).
    static let body: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -59))
        p.addCurve(to: CGPoint(x: 51, y: -2), control1: CGPoint(x: 29, y: -59), control2: CGPoint(x: 51, y: -33))
        p.addCurve(to: CGPoint(x: 26, y: 46), control1: CGPoint(x: 51, y: 22), control2: CGPoint(x: 44, y: 40))
        p.addCurve(to: CGPoint(x: -26, y: 46), control1: CGPoint(x: 14, y: 49), control2: CGPoint(x: -14, y: 49))
        p.addCurve(to: CGPoint(x: -51, y: -2), control1: CGPoint(x: -44, y: 40), control2: CGPoint(x: -51, y: 22))
        p.addCurve(to: CGPoint(x: 0, y: -59), control1: CGPoint(x: -51, y: -33), control2: CGPoint(x: -29, y: -59))
        p.closeSubpath()
        return p
    }()
    static func circle(_ x: Double, _ y: Double, _ r: Double) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    /// Faceless silhouette: body, side arms, feet.
    static let silhouette: Path = {
        var p = body
        p.addPath(circle(-52.5, 14, 11)); p.addPath(circle(52.5, 14, 11))
        p.addEllipse(in: CGRect(x: -21.7 - 11.5, y: 49 - 8.5, width: 23, height: 17))
        p.addEllipse(in: CGRect(x: 21.7 - 11.5, y: 49 - 8.5, width: 23, height: 17))
        return p
    }()
    /// One 72 pt tile: silhouettes at (18,18) and (54,54), scale 0.19.
    static let tile: Path = {
        var p = Path()
        for c in [18.0, 54.0] {
            p.addPath(silhouette.applying(CGAffineTransform(scaleX: 0.19, y: 0.19).concatenating(CGAffineTransform(translationX: c, y: c))))
        }
        return p
    }()
}

/// Blue title backdrop: scrolling rotated Jelbie pattern, twinkling sparkles, the peeking Jelbie.
struct TitleBackdrop: View {
    let still: Bool
    let size: CGSize
    let landscape: Bool
    var palette: ThemePalette = ThemeMath.palette(.sky)
    /// The menu composition scale (nil = w/440, the portrait design) and how far the face is pushed down on a very short screen.
    var scale: CGFloat? = nil
    var faceScale: CGFloat? = nil
    var faceTop: CGFloat? = nil
    /// false = just the colour and the pattern (the loading screen).
    var extras = true

    private static func sparkle(_ cx: Double, _ cy: Double, _ r: Double, _ t: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - r))
        p.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + r * 0.1, y: cy - r * 0.6), control2: CGPoint(x: cx + r * 0.4, y: cy - r * 0.1))
        p.addCurve(to: CGPoint(x: cx, y: cy + r), control1: CGPoint(x: cx + r * 0.4, y: cy + r * 0.1), control2: CGPoint(x: cx + r * 0.1, y: cy + r * 0.6))
        p.addCurve(to: CGPoint(x: cx - r, y: cy), control1: CGPoint(x: cx - r * 0.1, y: cy + r * 0.6), control2: CGPoint(x: cx - r * 0.4, y: cy + r * 0.1))
        p.addCurve(to: CGPoint(x: cx, y: cy - r), control1: CGPoint(x: cx - r * 0.4, y: cy - r * 0.1), control2: CGPoint(x: cx - r * 0.1, y: cy - r * 0.6))
        p.closeSubpath()
        return p
    }

    /// The rotated Jelbie pattern at phase 0, drawn once into a Metal-backed layer (`drawingGroup`) that is a little larger than the screen. It is
    /// periodic, so the 9 s scroll is just this layer sliding by the phase offset; the ~361 tile paths are no longer re-filled at 30 Hz.
    private struct PatternLayer: View, Equatable {
        let w: Double, h: Double, opacity: Double
        static let period = 72.0
        var body: some View {
            let ps = min(w, h) / 440
            let m = 2 * Self.period * ps                       // margin >= the longest slide (one period along the diagonal)
            Canvas { ctx, sz in
                var pc = ctx
                pc.translateBy(x: sz.width / 2, y: sz.height / 2)
                pc.rotate(by: .degrees(-10))
                pc.scaleBy(x: ps, y: ps)
                let R = Int((hypot(sz.width, sz.height) / ps / Self.period).rounded(.up)) / 2 + 2
                let tilePath = JelbieArt.tile
                let color = Color.white.opacity(opacity)
                for i in -R...R { for j in -R...R {
                    pc.fill(tilePath.applying(CGAffineTransform(translationX: Double(i) * Self.period, y: Double(j) * Self.period)), with: .color(color))
                } }
            }
            .frame(width: w + 2 * m, height: h + 2 * m)
            .drawingGroup()
        }
        /// Where the layer sits at this phase: the tile-space slide (-phase*72, -phase*72) scaled, then turned by the pattern's -10 degrees.
        static func slide(phase: Double, w: Double, h: Double) -> CGSize {
            let ps = min(w, h) / 440
            let d = -phase * period * ps
            let a = -10.0 * Double.pi / 180
            return CGSize(width: d * cos(a) - d * sin(a), height: d * sin(a) + d * cos(a))
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { tl in
                let t = still ? 0 : tl.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: 9)) / 9
                let slide = PatternLayer.slide(phase: phase, w: geo.size.width, h: geo.size.height)
                ZStack {
                    palette.bg
                    PatternLayer(w: geo.size.width, h: geo.size.height, opacity: palette.patternOpacity)
                        .equatable()
                        .offset(slide)
                    if extras { foreground(t: t) }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Sparkles and the peeking Jelbie (a few dozen paths; the only thing that still redraws each frame).
    private func foreground(t: Double) -> some View {
        Canvas { ctx, sz in
            do {
                let w = sz.width, h = sz.height
                // Sparkles (positions are fractions of the 440x956 design)
                let tw = still ? 1.0 : 0.65 + 0.35 * cos(t * 2 * .pi / 2.4)
                let ds = Double(scale ?? w / 440)
                // iPad-sized windows: this canvas is taller than the screen (it shares a ZStack with the oversized pattern layer, margin 2 x 72 x short/440 on
                // every side) and so starts that far above it; move the drawing back by the margin so the face lands where MenuMetrics put it. iPhone: unchanged.
                let padShift = (faceTop != nil && min(size.width, size.height) > 600) ? Double(2 * 72 * min(size.width, size.height) / 440) : 0
                var sc = ctx
                sc.opacity = tw
                for (x, y, r) in [(52.0, 157.5, 7.5), (398.0, 337.5, 7.5), (380.0, 133.0, 5.0)] {
                    sc.fill(Self.sparkle(w / 2 + (x - 220) * ds, y * ds + padShift, r * ds, t), with: .color(.white))
                }
                // Peeking Jelbie
                let scale = Double(faceScale ?? CGFloat(4.8 * ds))      // zoomed in: just the head dome, brows and eyes
                let cx = w / 2
                let bob = still ? 0 : -10 * ds * (0.5 - 0.5 * cos(t * 2 * .pi / 3.2))
                let cy = (faceTop.map { Double($0) + 65.5 * scale } ?? 0.91 * h + 14 * scale) + bob + padShift                            // eyes sit ~9% of the screen above the bottom
                var jc = ctx
                jc.translateBy(x: cx, y: cy)
                jc.scaleBy(x: scale, y: scale)
                let rim = palette.rim
                for path in [JelbieArt.body, JelbieArt.circle(-52.5, 14, 10), JelbieArt.circle(52.5, 14, 10)] {
                    jc.fill(path, with: .color(rim))
                    jc.stroke(path, with: .color(rim), style: StrokeStyle(lineWidth: 13, lineJoin: .round))
                }
                jc.fill(JelbieArt.body, with: .color(.white))
                var cc = jc
                cc.clip(to: JelbieArt.body)
                cc.fill(JelbieArt.body, with: .color(palette.shade))
                cc.fill(JelbieArt.body.applying(CGAffineTransform(translationX: -5, y: -6)), with: .color(.white))
                // Eyes (blink)
                let ph = still ? 0 : t.truncatingRemainder(dividingBy: 4.6) / 4.6
                let sy2: Double = ph < 0.93 ? 1 : ph < 0.95 ? 1 - 0.88 * (ph - 0.93) / 0.02 : ph < 1 ? 0.12 + 0.88 * (ph - 0.95) / 0.05 : 1
                var ec = jc
                ec.translateBy(x: 0, y: -14); ec.scaleBy(x: 1, y: sy2); ec.translateBy(x: 0, y: 14)
                let eye = palette.eye
                for x in [-19.5, 19.5] {
                    ec.fill(JelbieArt.circle(x, -14, 4.8), with: .color(eye))
                    ec.fill(JelbieArt.circle(x, -16.2, 1.7), with: .color(.white))
                }
                var l = Path(); l.move(to: CGPoint(x: -27, y: -27)); l.addQuadCurve(to: CGPoint(x: -12, y: -28), control: CGPoint(x: -19.5, y: -31))
                var r = Path(); r.move(to: CGPoint(x: 12, y: -28)); r.addQuadCurve(to: CGPoint(x: 27, y: -27), control: CGPoint(x: 19.5, y: -31))
                for b in [l, r] { jc.stroke(b, with: .color(eye), style: StrokeStyle(lineWidth: 2.2, lineCap: .round)) }
            }
        }
    }
}
