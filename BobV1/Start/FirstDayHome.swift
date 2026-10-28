//
//  FirstDayHome.swift
//  "First day home": the short beat after a new player has chosen and named their first Jelbie (and after Settings > Watch the opening). A cozy,
//  illustrated room in the opening's art style (moving boxes, one open with a blanket peeking out, a window onto Wobble Isle's dawn sky) where the
//  chosen Jelbie (the real 3D one, ShowcaseStage cutout, with its species features) bounces in and does a happy hop. Captions: "Welcome home,
//  <name>!" then how Drops work. ~6 s after the Jelbie is ready; a tap moves on, Skip leaves, then a cross-fade into the room.
//  Reduce Motion: no bounce-in, plain fades. VoiceOver reads the captions. Simulator-only capture flag: -FirstDayChar 0...3 shows it directly.
//

import SwiftUI

/// The beat's state lives in a class: the stage's escaping callbacks hold early copies of this struct, whose @State would not be the live storage.
@MainActor @Observable final class FirstDayState {
    var model: MelonModel?
    var readyAt: Date?
    var startedAt = Date()
    var step = 0                    // 0: Welcome home, 1: how Drops work
    var stepAt = Date()
    var leaving = false
    var snapshot: [String: Any] = [:]
    var task: Task<Void, Never>?
}

struct FirstDayHomeView: View {
    @State private var st = FirstDayState()
    let character: Int
    let name: String
    let replay: Bool
    var finished: () -> Void

    @State private var camera = PickerCamera()
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnv

    private var motion: Bool { !(reduceMotionEnv || A11ySettings.shared.reduceMotion) }
    static let lines: (String, String) = ("", "Take good care of them, earn JellyCoins around town, and one day you can adopt another friend from the Spring.")
    private var holdCapture: Bool {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.object(forKey: "FirstDayHold") != nil          // capture aid: wait for the Jelbie, then stay (-FirstDayHold <seconds before the second caption>)
        #else
        return false
        #endif
    }
    private var caption: String { st.step == 0 ? "Welcome home, \(name)!" : Self.lines.1 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                    scene(now: tl.date, size: size)
                }
                Color.clear.contentShape(Rectangle()).onTapGesture { tapped() }.accessibilityHidden(true)
                skipPill(geo)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .opacity(st.leaving ? 0 : 1)
        .animation(.easeOut(duration: 0.5), value: st.leaving)
        .task { begin() }
        .onDisappear { st.task?.cancel(); if replay { Self.restore(st.snapshot); st.snapshot = [:] } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-day-home")
    }

    // MARK: frame

    private func scene(now: Date, size: CGSize) -> some View {
        let portrait = size.height >= size.width
        let t = now.timeIntervalSince(st.startedAt)
        let f = min(portrait ? size.width * 0.82 : size.height * 0.95, 340)
        let feet = CGPoint(x: size.width / 2, y: size.height * (portrait ? 0.66 : 0.70))
        let age = st.readyAt.map { now.timeIntervalSince($0) } ?? -1
        return ZStack {
            Canvas { ctx, sz in FirstDayArt.room(ctx, sz, t: motion ? t : 0, feet: feet, unit: portrait ? Double(sz.width) / 400 : Double(sz.height) / 460) }
            ShowcaseStage(roster: [character], focusFirst: true, fullScreen: false, cutout: true, onReady: { m in ready(m) })
                .frame(width: f, height: f)
                .scaleEffect(jelbieScale(age), anchor: .init(x: 0.5, y: 0.73))
                .position(x: feet.x, y: feet.y - 0.23 * f + jelbieDrop(age, f: f))
                .opacity(age < 0 ? 0 : min(1, age / 0.12))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Canvas { ctx, _ in sparkles(ctx, feet: feet, f: f, age: age) }.allowsHitTesting(false)
            captionView(now: now, size: size, portrait: portrait)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// The bounce-in: drops from above, lands, small damped bounces. Reduce Motion: stays put.
    private func jelbieDrop(_ age: Double, f: Double) -> Double {
        guard motion, age >= 0 else { return 0 }
        if age < 0.5 { let p = age / 0.5; return -f * 0.95 * (1 - p * p) }
        let u = age - 0.5
        return -abs(sin(u * 9.5)) * f * 0.16 * exp(-u * 4.2)
    }
    private func jelbieScale(_ age: Double) -> Double {
        guard motion, age >= 0 else { return 1 }
        if age < 0.5 { return 0.7 + 0.3 * (age / 0.5) }
        let u = age - 0.5
        return 1 + 0.07 * sin(u * 16) * exp(-u * 4)
    }

    private func sparkles(_ ctx: GraphicsContext, feet: CGPoint, f: Double, age: Double) {
        guard motion, age > 0.45, age < 1.6 else { return }
        let g = (age - 0.45) / 1.15
        for i in 0..<12 {
            let a = Double(i) / 12 * .pi * 2
            let d = (30 + 120 * g) * f / 300
            let p = CGPoint(x: feet.x + cos(a) * d * 1.3, y: feet.y - 0.2 * f + sin(a) * d)
            ctx.fill(OArt.star4(p, (3 + 4 * OArt.hash(i, 9)) * (1 - g) + 0.5), with: .color(OArt.C(i % 2 == 0 ? 0xFFFFFF : 0xFFE07A, 1 - g)))
        }
    }

    private func captionView(now: Date, size: CGSize, portrait: Bool) -> some View {
        let local = now.timeIntervalSince(st.stepAt)
        let a = motion ? OArt.smooth((local - 0.15) / 0.6) : 1
        let big = st.step == 0
        let fs: CGFloat = big ? (portrait ? min(40, size.width * 0.1) : 34) : (portrait ? min(25, size.width * 0.065) : 22)
        return Text(caption)
            .font(SK.font(fs, big ? .black : .heavy))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(fs * 0.12)
            .shadow(color: Color(hex: 0x5A3A2A).opacity(0.7), radius: 6, y: 2)
            .padding(.horizontal, size.width * (portrait ? 0.09 : 0.18))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, size.height * (portrait ? 0.08 : 0.05))
            .opacity(a)
            .id(st.step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption)
            .accessibilityAddTraits(.isHeader)
    }

    private func skipPill(_ geo: GeometryProxy) -> some View {
        let top = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
        return Button { finish() } label: {
            HStack(spacing: 5) {
                Text("Skip").font(SK.font(17, .heavy))
                Image(systemName: "forward.fill").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(SK.ink)
            .padding(.horizontal, 16).frame(minWidth: 72, minHeight: 44)
            .background(Capsule().fill(Color.white.opacity(0.8)).shadow(color: Color(hex: 0x5A3A2A).opacity(0.25), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip").accessibilityIdentifier("first-day-skip")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, max(geo.safeAreaInsets.top, top, 14) + 6).padding(.trailing, max(geo.safeAreaInsets.trailing, 0) + 16)
    }

    // MARK: flow

    private func begin() {
        if replay { st.snapshot = OpeningStoryView.saveSnapshot() }
        camera.engage()
        st.startedAt = Date(); st.stepAt = Date()
        Task { @MainActor in for _ in 0..<6 { LaunchGate.shared.stageTicked(); try? await Task.sleep(nanoseconds: 800_000_000) } }
        A11yAnnounce.say(caption, priority: .high)
        st.task = Task { @MainActor in
            // wait for the Jelbie to stand (the stage builds a real room), but never longer than 9 s
            for _ in 0..<(holdCapture ? 6000 : 90) where st.readyAt == nil && !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }
            if st.readyAt == nil { st.readyAt = Date() }
            st.stepAt = Date()
            try? await Task.sleep(nanoseconds: UInt64(2.9 * 1e9))
            guard !Task.isCancelled else { return }
            if holdCapture { try? await Task.sleep(nanoseconds: UInt64(Double(UserDefaults.standard.integer(forKey: "FirstDayHold")) * 1e9)); if UserDefaults.standard.integer(forKey: "FirstDayHold") > 5 { goStep(1, auto: true) }; return }
            goStep(1, auto: true)
            try? await Task.sleep(nanoseconds: UInt64(4.4 * 1e9))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func ready(_ m: MelonModel) {
        st.model = m
        guard st.readyAt == nil else { return }
        st.readyAt = Date()
        AudioHub.shared.playOpening("opening_pop", volume: 0.9)
        AudioHub.shared.playOpening("sparkle_1", volume: 0.6)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let b = m.care.brainFor(0), !m.paused else { return }
            if motion { b.wantJoy() } else { b.blinkRequested = true }
            b.face(.happy, hold: 2.5)
        }
    }

    private func goStep(_ s: Int, auto: Bool) {
        guard st.step != s else { return }
        withAnimation(.easeInOut(duration: 0.3)) { st.step = s }
        st.stepAt = Date()
        A11yAnnounce.say(caption, priority: .high)
        if !auto { AudioHub.shared.playOpening("opening_twinkle", volume: 0.4) }
    }

    private func tapped() {
        guard !st.leaving else { return }
        if st.step == 0 { st.task?.cancel(); goStep(1, auto: false); restartTail() } else { finish() }
    }
    /// After a tap on the first caption, the second one stays ~5 s then leaves.
    private func restartTail() {
        st.task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(5.0 * 1e9))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !st.leaving else { return }
        st.leaving = true
        st.task?.cancel()
        camera.release()          // before the room (or the picker) engages its own
        if replay { Self.restore(st.snapshot); st.snapshot = [:] }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            finished()
        }
    }

    private static func restore(_ s: [String: Any]) { OpeningStoryView.restoreSnapshot(s) }
}

// MARK: the room

enum FirstDayArt {
    typealias C = OArt

    static func room(_ ctx: GraphicsContext, _ size: CGSize, t: Double, feet: CGPoint, unit u: Double) {
        let w = Double(size.width), h = Double(size.height)
        let floorY = feet.y - 38 * u
        // wall
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: floorY)), with: .linearGradient(Gradient(colors: [C.C(0xFFEBD8), C.C(0xF7D2B8)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))
        // a soft stripe of wallpaper dots
        for i in 0..<22 {
            let x = (Double(i) + 0.5) / 22 * w
            for j in 0..<6 {
                let y = floorY * (Double(j) + 0.5 + (i % 2 == 0 ? 0 : 0.5)) / 6.6
                ctx.fill(C.ell(x, y, 2.2 * u, 2.2 * u), with: .color(C.C(0xFFFFFF, 0.28)))
            }
        }
        // floor boards
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: h - floorY)), with: .linearGradient(Gradient(colors: [C.C(0xE8C59A), C.C(0xD6A877)]), startPoint: CGPoint(x: 0, y: floorY), endPoint: CGPoint(x: 0, y: h)))
        for k in 1..<7 {
            let y = floorY + (h - floorY) * pow(Double(k) / 7, 1.4)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(p, with: .color(C.C(0xA97C50, 0.3)), lineWidth: 1.2)
        }
        // baseboard
        ctx.fill(Path(CGRect(x: 0, y: floorY - 9 * u, width: w, height: 9 * u)), with: .color(C.C(0xFFF8EC)))
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: 2.5 * u)), with: .color(C.C(0xB98B5E, 0.5)))

        window(ctx, cx: w / 2, top: max(120, h * 0.13), u: u, t: t)
        stringLights(ctx, w: w, y: floorY * 0.12, u: u, t: t)
        rug(ctx, feet: feet, u: u)
        // moving boxes: left stack, right pair
        box(ctx, x: w * 0.17, y: floorY + 30 * u, w: 86 * u, h: 62 * u, u: u, open: false)
        box(ctx, x: w * 0.19, y: floorY - 20 * u, w: 70 * u, h: 50 * u, u: u, open: false, tilt: -2)
        box(ctx, x: w * 0.80, y: floorY + 52 * u, w: 96 * u, h: 66 * u, u: u, open: true)
        box(ctx, x: w * 0.77, y: floorY - 6 * u, w: 62 * u, h: 46 * u, u: u, open: false, tilt: 3)
        // plant waiting to be unpacked
        plant(ctx, x: w * 0.33, y: floorY + 6 * u, u: u)
        // warm light from the window onto the floor
        var beam = Path()
        beam.move(to: CGPoint(x: w / 2 - 70 * u, y: floorY)); beam.addLine(to: CGPoint(x: w / 2 + 70 * u, y: floorY))
        beam.addLine(to: CGPoint(x: w / 2 + 150 * u, y: h)); beam.addLine(to: CGPoint(x: w / 2 - 150 * u, y: h)); beam.closeSubpath()
        ctx.fill(beam, with: .linearGradient(Gradient(colors: [C.C(0xFFF3CF, 0.30), C.C(0xFFF3CF, 0)]), startPoint: CGPoint(x: 0, y: floorY), endPoint: CGPoint(x: 0, y: h)))
    }

    private static func window(_ ctx: GraphicsContext, cx: Double, top: Double, u: Double, t: Double) {
        let ww = 200 * u, wh = 190 * u
        let r = CGRect(x: cx - ww / 2, y: top, width: ww, height: wh)
        // frame and glass
        ctx.fill(Path(roundedRect: r.insetBy(dx: -9 * u, dy: -9 * u), cornerRadius: 22 * u), with: .color(C.C(0xFFF8EC)))
        ctx.fill(Path(roundedRect: r.insetBy(dx: -9 * u, dy: -9 * u), cornerRadius: 22 * u).strokedPath(StrokeStyle(lineWidth: 2)), with: .color(C.C(0xD9B98F)))
        let glass = Path(roundedRect: r, cornerRadius: 14 * u)
        ctx.drawLayer { l in
            l.clip(to: glass)
            l.fill(Path(r), with: .linearGradient(Gradient(colors: [C.C(0x86B6EC), C.C(0xF3C6DC), C.C(0xFFE2B8)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            // the sun coming up
            let sun = CGPoint(x: r.midX + 34 * u, y: r.maxY - 46 * u)
            l.fill(C.ell(sun.x, sun.y, 80 * u, 80 * u), with: .radialGradient(Gradient(colors: [C.C(0xFFF3C8, 0.9), C.C(0xFFF3C8, 0)]), center: sun, startRadius: 0, endRadius: 80 * u))
            l.fill(C.ell(sun.x, sun.y, 21 * u, 21 * u), with: .color(C.C(0xFFF6D2)))
            // a drifting cloud and a tiny floating island far away
            let dx = sin(t * 0.25) * 8 * u
            for (ox, oy, rr) in [(-50.0, -52.0, 1.0), (20, -70, 0.7)] as [(Double, Double, Double)] {
                let c = CGPoint(x: r.midX + ox * u + dx * rr, y: r.midY + oy * u)
                l.fill(C.ell(c.x, c.y, 26 * u * rr, 8 * u * rr), with: .color(.white.opacity(0.9)))
                l.fill(C.ell(c.x - 8 * u * rr, c.y - 5 * u * rr, 13 * u * rr, 8 * u * rr), with: .color(.white.opacity(0.9)))
            }
            let ix = r.midX - 38 * u, iy = r.midY + 26 * u + sin(t * 1.2) * 2 * u
            var rock = Path()
            rock.move(to: CGPoint(x: ix - 30 * u, y: iy)); rock.addLine(to: CGPoint(x: ix + 30 * u, y: iy)); rock.addLine(to: CGPoint(x: ix + 4 * u, y: iy + 24 * u)); rock.closeSubpath()
            l.fill(rock, with: .color(C.C(0xB89572)))
            l.fill(C.ell(ix, iy, 30 * u, 7 * u), with: .color(C.C(0xA8DDB6)))
            l.fill(C.ell(ix - 10 * u, iy - 8 * u, 6 * u, 7 * u), with: .color(C.C(0x72C48C)))
            l.fill(C.ell(ix + 12 * u, iy - 7 * u, 5 * u, 6 * u), with: .color(C.C(0x72C48C)))
            // a little glass shine
            var sh = Path(); sh.move(to: CGPoint(x: r.minX + 16 * u, y: r.minY + 60 * u)); sh.addLine(to: CGPoint(x: r.minX + 56 * u, y: r.minY + 10 * u))
            l.stroke(sh, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 9 * u, lineCap: .round))
        }
        // muntins
        var m = Path()
        m.move(to: CGPoint(x: r.midX, y: r.minY)); m.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        m.move(to: CGPoint(x: r.minX, y: r.midY)); m.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        ctx.stroke(m, with: .color(C.C(0xFFF8EC)), lineWidth: 5 * u)
        // sill
        ctx.fill(Path(roundedRect: CGRect(x: r.minX - 18 * u, y: r.maxY + 6 * u, width: ww + 36 * u, height: 12 * u), cornerRadius: 5 * u), with: .color(C.C(0xFFF8EC)))
        // curtains, tied back
        for side in [-1.0, 1.0] {
            let x0 = cx + side * (ww / 2 + 14 * u)
            var c = Path()
            c.move(to: CGPoint(x: x0, y: top - 14 * u))
            c.addLine(to: CGPoint(x: x0 + side * 40 * u, y: top - 14 * u))
            c.addCurve(to: CGPoint(x: x0 + side * 26 * u, y: top + wh * 0.58), control1: CGPoint(x: x0 + side * 46 * u, y: top + wh * 0.2), control2: CGPoint(x: x0 + side * 8 * u, y: top + wh * 0.4))
            c.addCurve(to: CGPoint(x: x0 + side * 36 * u, y: top + wh + 14 * u), control1: CGPoint(x: x0 + side * 44 * u, y: top + wh * 0.75), control2: CGPoint(x: x0 + side * 30 * u, y: top + wh * 0.92))
            c.addLine(to: CGPoint(x: x0 - side * 2 * u, y: top + wh + 14 * u))
            c.closeSubpath()
            ctx.fill(c, with: .linearGradient(Gradient(colors: [C.C(0xF7B3C5), C.C(0xEE96AC)]), startPoint: CGPoint(x: x0, y: top), endPoint: CGPoint(x: x0 + side * 40 * u, y: top)))
            ctx.fill(C.ell(x0 + side * 22 * u, top + wh * 0.56, 6 * u, 4 * u), with: .color(C.C(0xFFE07A)))
        }
        ctx.fill(Path(roundedRect: CGRect(x: cx - ww / 2 - 46 * u, y: top - 22 * u, width: ww + 92 * u, height: 8 * u), cornerRadius: 4 * u), with: .color(C.C(0xB58D67)))
    }

    private static func stringLights(_ ctx: GraphicsContext, w: Double, y: Double, u: Double, t: Double) {
        var p = Path()
        p.move(to: CGPoint(x: -10, y: y)); p.addQuadCurve(to: CGPoint(x: w + 10, y: y), control: CGPoint(x: w / 2, y: y + 58 * u))
        ctx.stroke(p, with: .color(C.C(0x8B6B4C, 0.7)), lineWidth: 1.4)
        let cols: [UInt32] = [0xFFE07A, 0xF7B3C5, 0x9DD0F2, 0xA8DDB6]
        for i in 0..<9 {
            let s = (Double(i) + 0.5) / 9
            let x = -10 + (w + 20) * s
            let by = y + 2 * s * (1 - s) * 58 * u + 4 * u
            let tw = 0.7 + 0.3 * sin(t * 2 + Double(i))
            let c = cols[i % 4]
            ctx.fill(C.ell(x, by + 6 * u, 15 * u, 15 * u), with: .radialGradient(Gradient(colors: [C.C(c, 0.5 * tw), C.C(c, 0)]), center: CGPoint(x: x, y: by + 6 * u), startRadius: 0, endRadius: 15 * u))
            ctx.fill(C.ell(x, by + 6 * u, 3.6 * u, 4.6 * u), with: .color(C.C(c)))
        }
    }

    private static func rug(_ ctx: GraphicsContext, feet: CGPoint, u: Double) {
        ctx.fill(C.ell(feet.x, feet.y + 2 * u, 150 * u, 40 * u), with: .color(Color(hex: 0x6B4A2E).opacity(0.18)))
        ctx.fill(C.ell(feet.x, feet.y, 146 * u, 38 * u), with: .linearGradient(Gradient(colors: [C.C(0xF7B3C5), C.C(0xEE96AC)]), startPoint: CGPoint(x: 0, y: feet.y - 38 * u), endPoint: CGPoint(x: 0, y: feet.y + 38 * u)))
        ctx.stroke(C.ell(feet.x, feet.y, 122 * u, 30 * u), with: .color(C.C(0xFFF8EC, 0.85)), style: StrokeStyle(lineWidth: 3 * u, dash: [10 * u, 7 * u]))
        ctx.fill(C.ell(feet.x, feet.y, 84 * u, 20 * u), with: .color(C.C(0xFFE3EA, 0.7)))
    }

    private static func box(_ ctx: GraphicsContext, x: Double, y: Double, w: Double, h: Double, u: Double, open: Bool, tilt: Double = 0) {
        var c = ctx
        c.translateBy(x: x, y: y); c.rotate(by: .degrees(tilt))
        c.fill(C.ell(0, h * 0.02, w * 0.62, h * 0.12), with: .color(Color(hex: 0x6B4A2E).opacity(0.2)))
        let body = CGRect(x: -w / 2, y: -h, width: w, height: h)
        c.fill(Path(roundedRect: body, cornerRadius: 4 * u), with: .linearGradient(Gradient(colors: [C.C(0xD9AE78), C.C(0xC49A63)]), startPoint: CGPoint(x: 0, y: -h), endPoint: CGPoint(x: 0, y: 0)))
        c.stroke(Path(roundedRect: body, cornerRadius: 4 * u), with: .color(C.C(0x9C7345, 0.6)), lineWidth: 1.4)
        // tape and a fragile mark
        c.fill(Path(CGRect(x: -7 * u, y: -h, width: 14 * u, height: h)), with: .color(C.C(0xF3E2BC, 0.85)))
        c.fill(Path(roundedRect: CGRect(x: w * 0.12, y: -h * 0.62, width: w * 0.3, height: h * 0.26), cornerRadius: 3 * u), with: .color(C.C(0xFFF8EC, 0.85)))
        c.fill(C.ell(w * 0.27, -h * 0.49, 3.6 * u, 3.6 * u), with: .color(C.C(0xEE96AC)))
        if open {
            // flaps folded out, a blanket peeking over the rim
            for s in [-1.0, 1.0] {
                var flap = Path()
                flap.move(to: CGPoint(x: s * w * 0.5, y: -h)); flap.addLine(to: CGPoint(x: s * (w * 0.5 + 16 * u), y: -h - 20 * u))
                flap.addLine(to: CGPoint(x: s * (w * 0.5 - 22 * u), y: -h - 22 * u)); flap.addLine(to: CGPoint(x: s * (w * 0.5 - 26 * u), y: -h)); flap.closeSubpath()
                c.fill(flap, with: .color(C.C(0xC49A63)))
            }
            c.fill(C.ell(0, -h, w * 0.5, 9 * u), with: .color(C.C(0x8A6A48)))
            var bl = Path()
            bl.move(to: CGPoint(x: -w * 0.42, y: -h))
            bl.addCurve(to: CGPoint(x: -w * 0.06, y: -h - 24 * u), control1: CGPoint(x: -w * 0.42, y: -h - 22 * u), control2: CGPoint(x: -w * 0.24, y: -h - 26 * u))
            bl.addCurve(to: CGPoint(x: w * 0.34, y: -h - 12 * u), control1: CGPoint(x: w * 0.1, y: -h - 22 * u), control2: CGPoint(x: w * 0.18, y: -h - 8 * u))
            bl.addLine(to: CGPoint(x: w * 0.4, y: -h + 2 * u)); bl.addLine(to: CGPoint(x: -w * 0.42, y: -h + 2 * u)); bl.closeSubpath()
            c.fill(bl, with: .linearGradient(Gradient(colors: [C.C(0xB9A5E8), C.C(0x9D86D6)]), startPoint: CGPoint(x: 0, y: -h - 26 * u), endPoint: CGPoint(x: 0, y: -h)))
            for k in 0..<4 {
                var st = Path(); let sx = -w * 0.3 + Double(k) * w * 0.18
                st.move(to: CGPoint(x: sx, y: -h - 18 * u + Double(k % 2) * 4 * u)); st.addLine(to: CGPoint(x: sx + 4 * u, y: -h + 1 * u))
                c.stroke(st, with: .color(.white.opacity(0.55)), lineWidth: 3 * u)
            }
        }
    }

    private static func plant(_ ctx: GraphicsContext, x: Double, y: Double, u: Double) {
        ctx.fill(C.ell(x, y, 26 * u, 6 * u), with: .color(Color(hex: 0x6B4A2E).opacity(0.18)))
        for (dx, dy, rot) in [(-8.0, -44.0, -0.4), (0, -54, 0), (9, -42, 0.45)] as [(Double, Double, Double)] {
            var c = ctx; c.translateBy(x: x + dx * u, y: y + dy * u); c.rotate(by: .radians(rot))
            c.fill(C.ell(0, 0, 8 * u, 17 * u), with: .color(C.C(0x72C48C)))
        }
        var pot = Path()
        pot.move(to: CGPoint(x: x - 15 * u, y: y - 30 * u)); pot.addLine(to: CGPoint(x: x + 15 * u, y: y - 30 * u))
        pot.addLine(to: CGPoint(x: x + 11 * u, y: y)); pot.addLine(to: CGPoint(x: x - 11 * u, y: y)); pot.closeSubpath()
        ctx.fill(pot, with: .color(C.C(0xEE96AC)))
        ctx.fill(Path(roundedRect: CGRect(x: x - 17 * u, y: y - 34 * u, width: 34 * u, height: 8 * u), cornerRadius: 3 * u), with: .color(C.C(0xF7B3C5)))
    }
}
