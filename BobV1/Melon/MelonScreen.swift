//
//  MelonScreen.swift
//  The editorial screen: masthead, status chip, specimen panel, readouts, notes, and the stage region.
//

import SwiftUI

struct MelonScreen<Stage: View>: View {
    @Bindable var model: MelonModel
    private let stage: () -> Stage

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: MelonModel, @ViewBuilder stage: @escaping () -> Stage) {
        self.model = model
        self.stage = stage
    }

    var body: some View {
        GeometryReader { geo in
            let gutter = min(max(20, geo.size.width * 0.03), 44)
            Group {
                if hSize == .compact {
                    stacked(size: geo.size, gutter: gutter)
                } else {
                    overlay(size: geo.size, gutter: gutter)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(MelonTheme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
        .tint(MelonTheme.ink)
        .onAppear { model.applyReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, v in model.applyReduceMotion(v) }
    }

    // MARK: Stage region (stage + offline card)

    private var stageRegion: some View {
        ZStack {
            // NOTE (compact layout): the stage lives inside a ScrollView. The injected stage must be a UIKit
            // view (UIViewRepresentable) that owns its touches via its own gesture recognizers / touchesBegan.
            // A touch that begins inside such a view is claimed by its recognizers, so the enclosing
            // ScrollView's pan does not start and one-finger drags orbit/grab instead of scrolling.
            stage()
                .opacity(model.isUnavailable ? 0 : 1)
            if case .unavailable(let reason) = model.status {
                FallbackCard(detail: reason)
            } else if let reason = model.metalUnavailableReason {
                FallbackCard(detail: reason)
            }
        }
    }

    // MARK: Compact (stacked)

    private func stacked(size: CGSize, gutter: CGFloat) -> some View {
        let stageH = min(max(300, size.height * 0.56), 600)
        let h1 = min(max(46, size.width * 0.14), 76)
        return ScrollView {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Masthead(headingSize: h1, compact: true)
                    Spacer(minLength: 0)
                    StatusChip(status: model.status, reduceMotion: reduceMotion, compact: true)
                }
                .padding(.top, gutter)
                .padding(.horizontal, gutter)
                .padding(.bottom, 12)

                stageRegion
                    .frame(height: stageH)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .top) { Rectangle().fill(MelonTheme.line).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(MelonTheme.line).frame(height: 1) }

                Readouts(model: model, fullWidth: true)
                    .padding(.horizontal, gutter)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                SpecimenPanel(model: model, translucent: false)
                    .padding(.horizontal, gutter)
                    .padding(.top, 14)

                NotesDisclosure(model: model, translucent: false)
                    .padding(.horizontal, gutter)
                    .padding(.top, 14)
                    .padding(.bottom, gutter)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Regular (overlay)

    private func overlay(size: CGSize, gutter: CGFloat) -> some View {
        let h1 = min(max(58, size.width * 0.074), 118)
        return ZStack {
            stageRegion.frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    Masthead(headingSize: h1, compact: false)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 14) {
                        StatusChip(status: model.status, reduceMotion: reduceMotion, compact: false)
                        SpecimenPanel(model: model, translucent: true)
                            .frame(width: 256)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    Readouts(model: model, fullWidth: false)
                    Spacer(minLength: 0)
                    NotesDisclosure(model: model, translucent: true)
                        .frame(width: 300)
                }
            }
            .padding(gutter)
        }
    }
}

// MARK: - Masthead

private struct Masthead: View {
    let headingSize: CGFloat
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PET STUDIES / NO. 001")
                .melonLabel(size: compact ? 10 : 10.5, tracking: compact ? 0.15 : 0.2)
                .lineLimit(1)
                .fixedSize()
                .padding(.bottom, compact ? 12 : 18)
            Text("Bob.")
            .font(MelonTheme.serifItalic(headingSize))
            .tracking(-headingSize * 0.025)
            .lineSpacing(-headingSize * 0.16)
            .foregroundStyle(MelonTheme.ink)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bob")
            .accessibilityAddTraits(.isHeader)
            Text("A small, round jelly.\nMostly unbothered.\nEats when he feels like it.")
                .font(MelonTheme.serif(compact ? 14 : 15))
                .foregroundStyle(MelonTheme.muted)
                .lineSpacing(4)
                .padding(.top, compact ? 12 : 20)
        }
    }
}

// MARK: - Status chip

private struct StatusChip: View {
    let status: MelonStatus
    let reduceMotion: Bool
    let compact: Bool
    @State private var dim = false

    private var text: String {
        switch status {
        case .starting: "METAL · STARTING"
        case .live: "METAL · LIVE"
        case .paused: "METAL · PAUSED"
        case .unavailable: "METAL · UNAVAILABLE"
        }
    }
    private var isLive: Bool { if case .live = status { return true } else { return false } }

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            dot
            Text(text)
                .font(MelonTheme.mono(compact ? 9.5 : 10.5, .medium))
                .tracking((compact ? 9.5 : 10.5) * 0.14)
                .foregroundStyle(isLive ? MelonTheme.ink : MelonTheme.muted)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, compact ? 5 : 7)
        .padding(.leading, compact ? 7 : 9)
        .padding(.trailing, compact ? 8 : 10)
        .overlay(Rectangle().stroke(MelonTheme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.capitalized)
        .accessibilityIdentifier("status-chip")
    }

    @ViewBuilder private var dot: some View {
        switch status {
        case .live:
            Circle().fill(MelonTheme.live).frame(width: 7, height: 7)
                .overlay(Circle().stroke(MelonTheme.live, lineWidth: 1))
                .opacity(dim ? 0.35 : 1)
                .onAppear { startBreathing() }
                .onChange(of: reduceMotion) { _, _ in startBreathing() }
        case .paused:
            Circle().stroke(MelonTheme.ink, lineWidth: 1).frame(width: 7, height: 7)
        case .unavailable:
            Circle().fill(MelonTheme.accent).frame(width: 7, height: 7)
        case .starting:
            Circle().stroke(MelonTheme.muted, lineWidth: 1).frame(width: 7, height: 7)
        }
    }

    private func startBreathing() {
        if reduceMotion { dim = false; return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { dim = true }
    }
}

// MARK: - Specimen panel

private struct SpecimenPanel: View {
    @Bindable var model: MelonModel
    let translucent: Bool

    private var accent: Color { Color(linear: model.palette.palette.uiFlesh) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE SPECIMEN").melonLabel()
                Spacer()
                Text("fig. 1").font(MelonTheme.serifItalic(13)).foregroundStyle(MelonTheme.muted)
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(MelonTheme.line).frame(height: 1) }

            group {
                Text("Colour").melonLabel()
                HStack(spacing: 8) {
                    ForEach(PaletteKey.allCases) { key in
                        Swatch(key: key, selected: model.palette == key) { model.palette = key }
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Colour")
            }

            group {
                SliderRow(title: "Firmness", value: $model.firmness, lo: "trembling", hi: "set", id: "slider-firmness")
                SliderRow(title: "Internal damping", value: $model.damping, lo: "lively", hi: "syrupy", id: "slider-damping")
                    .padding(.top, 14)
            }

            group(last: true) {
                HStack(spacing: 8) {
                    Button("Give it a nudge") { model.nudge() }
                        .accessibilityIdentifier("btn-nudge")
                    Button("Reset") { model.reset() }
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("btn-reset")
                }
                .buttonStyle(HairlineButtonStyle())
                Button(model.hopping ? "Stop hopping" : "Hop around") { model.hopping.toggle() }
                    .buttonStyle(HairlineButtonStyle())
                    .padding(.top, 2)
                    .disabled(model.paused || model.isUnavailable)
                    .accessibilityIdentifier("btn-hop")
                    .accessibilityAddTraits(model.hopping ? .isSelected : [])
                HStack(spacing: 22) {
                    Toggle("¼ speed", isOn: $model.slow).accessibilityIdentifier("toggle-slow")
                    Toggle("Show mesh", isOn: $model.showMesh).accessibilityIdentifier("toggle-mesh")
                    Spacer(minLength: 0)
                }
                .toggleStyle(SquareCheckStyle())
                .padding(.top, 6)
                Button(model.paused ? "Resume" : "Pause") { model.paused.toggle() }
                    .buttonStyle(HairlineButtonStyle())
                    .padding(.top, 2)
                    .accessibilityIdentifier("btn-pause")
                    .accessibilityAddTraits(model.paused ? .isSelected : [])
            }
        }
        .padding(.top, 20).padding(.horizontal, 20).padding(.bottom, 18)
        .background(translucent ? MelonTheme.bg.opacity(0.78) : Color.clear)
        .overlay(Rectangle().stroke(MelonTheme.line, lineWidth: 1))
        .disabled(model.isUnavailable)
        .tint(accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Specimen controls")
    }

    @ViewBuilder
    private func group<C: View>(last: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(MelonTheme.line).frame(height: 1) }
            }
    }
}

private struct Swatch: View {
    let key: PaletteKey
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let p = key.palette
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                VStack(spacing: 0) {
                    Color(linear: p.stripe).frame(height: 5)
                    Color(linear: p.pale).frame(height: 5)
                    Color(linear: p.uiFlesh).frame(maxHeight: .infinity)
                }
                .frame(height: 30)
                .overlay(Rectangle().stroke(MelonTheme.line, lineWidth: 1))
                Text(p.name)
                    .font(MelonTheme.serifItalic(13))
                    .foregroundStyle(selected ? MelonTheme.ink : MelonTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(selected ? MelonTheme.lineStrong : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(p.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("swatch-\(key.rawValue)")
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let lo: String
    let hi: String
    let id: String
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).melonLabel()
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(MelonTheme.mono(12))
                    .foregroundStyle(MelonTheme.ink)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
            HairlineSlider(value: $value, label: title).padding(.top, 2)
                .accessibilityIdentifier(id)
            HStack {
                Text(lo); Spacer(); Text(hi)
            }
            .font(MelonTheme.serifItalic(11.5))
            .foregroundStyle(MelonTheme.faint)
            .accessibilityHidden(true)
        }
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - Readouts

private struct Readouts: View {
    let model: MelonModel
    let fullWidth: Bool

    private var kineticText: String {
        let uj = model.kineticMicroJ
        return uj < 0.05 ? "0.00" : uj < 100 ? String(format: "%.2f", uj) : String(format: "%.0f", uj)
    }

    private var hint: AttributedString {
        var h = AttributedString("HANDLE")
        h.font = MelonTheme.sans(10.5)
        h.foregroundColor = MelonTheme.muted
        h.tracking = 1.7
        return h + AttributedString("  Drag to squish him. He will act like he didn't notice. A second finger twists him; drag empty space to walk around him, pinch to zoom.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hint)
                .font(MelonTheme.serifItalic(15))
                .foregroundStyle(MelonTheme.ink)
                .lineSpacing(3)
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 0) {
                stat("Mass", "≈" + String(format: "%.0f", model.mass), "g", id: "stat-mass", first: true)
                stat("Volume", String(format: "%.1f", model.volumePct), "% of rest", id: "stat-volume")
                stat("Kinetic", kineticText, "µJ", id: "stat-kinetic")
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .fixedSize(horizontal: !fullWidth, vertical: false)
            .overlay(alignment: .top) { Rectangle().fill(MelonTheme.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(MelonTheme.line).frame(height: 1) }

            Text("Illustrative scale: 1 sim unit ≈ 6 cm, gummy at 1.1 g/cm³. Volume and energy are summed live over every tetrahedron and particle.")
                .font(MelonTheme.sans(11))
                .foregroundStyle(MelonTheme.faint)
                .frame(maxWidth: 400, alignment: .leading)
                .padding(.top, 9)
        }
        .frame(maxWidth: fullWidth ? .infinity : 440, alignment: .leading)
        .opacity(model.isUnavailable ? 0.45 : 1)
    }

    private func stat(_ title: String, _ value: String, _ unit: String, id: String, first: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).melonLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(MelonTheme.mono(fullWidth ? 18 : 20))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .foregroundStyle(MelonTheme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(MelonTheme.sans(11)).foregroundStyle(MelonTheme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, first ? 0 : (fullWidth ? 12 : 18))
        .padding(.trailing, fullWidth ? 8 : 22)
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .overlay(alignment: .leading) {
            if !first { Rectangle().fill(MelonTheme.line).frame(width: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityIdentifier(id)
    }
}

// MARK: - Notes

private struct NotesDisclosure: View {
    let model: MelonModel
    let translucent: Bool
    @State private var open = false

    private func fmt(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(model.reduceMotion ? nil : .easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text("Inside the experiment").melonLabel()
                    Spacer()
                    Text(open ? "–" : "+").font(.system(size: 16, weight: .light)).foregroundStyle(MelonTheme.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("notes-toggle")

            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        h("A body made of tetrahedra")
                        p("Bob is a volumetric mesh of \(num(fmt(model.particles))) particles and \(num(fmt(model.tets))) tetrahedra: a dome mesh with a fan of tetrahedra around the apex, solved with XPBD on a fixed 60 Hz step split into 10 substeps. Each tetrahedron is pulled, with finite compliance, toward its best-fit rotated rest shape — a co-rotational elastic constraint that also flips inverted elements back out — and carries a volume constraint that keeps the jelly close to incompressible, so a stretched Bob necks in like the real thing.")
                        p("Tetrahedra in the skin are firmer than those inside. Damping acts only on relative velocity along the mesh edges, so he still falls and tumbles freely while his wobble dies away. Ground contact projects particles out of the floor with Coulomb-style friction; the grab is a soft attachment on a patch of particles, bounded in reach.")
                        h("A face that rides along")
                        p("The smooth surface, his two eyes and their glints are separate meshes, each vertex pinned to a tetrahedron by barycentric weights — so the eyes squash, turn and travel with the jelly around them.")
                        h("Light through jelly")
                        p("Metal shaders (MSL) render the floor and the eyes first, then Bob’s back faces to measure how much jelly each view ray crosses. The front faces refract the scene behind by that thickness, absorb it with thickness-based Beer–Lambert colour, add milky scattering, a back-lit glow at thin edges, Fresnel reflections of a procedural studio and GGX highlights. The floor gets a soft key shadow tinted by the jelly plus contact occlusion from a top-down height map.")
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
                .frame(maxHeight: translucent ? 380 : nil)
                .fixedSize(horizontal: false, vertical: !translucent)
                .overlay(alignment: .top) { Rectangle().fill(MelonTheme.line).frame(height: 1) }
            }
        }
        .background(translucent ? MelonTheme.bg.opacity(0.9) : Color.clear)
        .overlay(Rectangle().stroke(MelonTheme.line, lineWidth: 1))
    }

    private func num(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        a.font = MelonTheme.mono(11.5)
        return a
    }
    private func h(_ s: String) -> some View {
        Text(s).font(MelonTheme.serifItalic(16)).foregroundStyle(MelonTheme.ink).padding(.top, 14).padding(.bottom, 6)
    }
    private func p(_ s: AttributedString) -> some View {
        Text(s).font(MelonTheme.sans(12.5)).foregroundStyle(MelonTheme.noteText).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }
    private func p(_ s: String) -> some View { p(AttributedString(s)) }
}

// MARK: - Fallback

private struct FallbackCard: View {
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Renderer offline").melonLabel()
            Text("Bob needs Metal.")
                .font(MelonTheme.serifItalic(30))
                .foregroundStyle(MelonTheme.ink)
                .padding(.top, 10).padding(.bottom, 12)
            Text("The interactive jelly is rendered on the GPU with Metal, and no usable Metal device could be started on this device. \(detail)")
                .font(MelonTheme.sans(13))
                .foregroundStyle(MelonTheme.muted)
        }
        .padding(.top, 28).padding(.horizontal, 28).padding(.bottom, 24)
        .frame(maxWidth: 420, alignment: .leading)
        .background(MelonTheme.bg)
        .overlay(Rectangle().stroke(MelonTheme.lineStrong, lineWidth: 1))
        .padding(20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fallback-card")
    }
}

// MARK: - Previews

private struct MelonPlaceholderStage: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(MelonTheme.ink.opacity(0.06))
            .overlay(Text("STAGE").melonLabel())
            .padding(12)
    }
}

private func previewModel(_ unavailable: Bool = false) -> MelonModel {
    let m = MelonModel()
    m.status = .live; m.mass = 74; m.volumePct = 99.8; m.kineticMicroJ = 1.23
    m.particles = 2184; m.tets = 7920; m.seeds = 2
    if unavailable { m.metalUnavailableReason = "No Metal device." }
    return m
}

#Preview("Compact") {
    MelonScreen(model: previewModel()) { MelonPlaceholderStage() }
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("Regular", traits: .landscapeLeft) {
    MelonScreen(model: previewModel()) { MelonPlaceholderStage() }
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Unavailable") {
    MelonScreen(model: previewModel(true)) { MelonPlaceholderStage() }
}
