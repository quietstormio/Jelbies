//
//  GardenOverlay.swift
//  The Garden's few bits of UI, over the game: the seed picker that opens when an empty plot is tapped, and the short line after planting, watering and
//  picking. Both scale for landscape (a compact height) and are labelled for VoiceOver.
//

import SwiftUI

struct GardenOverlay: View {
    let care: GameCare
    @Environment(\.verticalSizeClass) private var vsc
    private var wide: Bool { vsc == .compact }
    private var garden: GardenBook { care.garden }

    var body: some View {
        ZStack {
            if care.roomID == .garden {
                if let note = garden.note {
                    VStack {
                        Text(note).font(SK.font(15, .heavy)).foregroundStyle(SK.ink).multilineTextAlignment(.center)
                            .padding(.horizontal, 16).padding(.vertical, 9).background(Capsule().fill(SK.honey.opacity(0.95)))
                            .shadow(color: SK.shadow.opacity(0.15), radius: 4, y: 2)
                            .accessibilityIdentifier("garden-note")
                        Spacer()
                    }
                    .padding(.top, wide ? 12 : 64)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
                if let plot = garden.pickerPlot { picker(plot) }
                if assistive, garden.pickerPlot == nil { plotRow }
            }
        }
        .animation(.easeOut(duration: 0.2), value: garden.note)
        .onChange(of: garden.note) { _, n in if let n { A11yAnnounce.say(n) } }
        .animation(.easeOut(duration: 0.2), value: garden.pickerPlot)
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in assistive = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in assistive = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning }
    }

    // MARK: plots without touching the scene (VoiceOver, Switch Control, Voice Control)

    @State private var assistive = UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning

    /// One button per plot: plant, water or harvest, the same call a tap on the 3D plot makes. Only shown while an assistive technology runs.
    private var plotRow: some View {
        TimelineView(.periodic(from: .now, by: 4)) { _ in
            let now = Date().timeIntervalSince1970
            VStack {
                Spacer().frame(height: wide ? 60 : 118)
                HStack(spacing: 8) {
                    ForEach(0..<GardenTuning.plotCount, id: \.self) { i in plotButton(i, now: now) }
                }
                .padding(.horizontal, 12)
                Spacer()
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(10)
        }
        .accessibilityIdentifier("garden-plots")
    }

    private func plotButton(_ i: Int, now: Double) -> some View {
        let stage = garden.stage(i)
        let plant = garden.plots[i].plant
        let wet = garden.isWet(i, now: now)
        let action = stage == 0 ? "plant" : stage == 3 ? "harvest" : "water"
        let state: String = {
            guard let k = plant else { return "empty" }
            let pct = Int(garden.fraction(i) * 100)
            return stage == 3 ? "\(k.title), ripe" : "\(k.title), \(pct) percent grown, soil \(wet ? "wet" : "dry")"
        }()
        return Button { care.gardenTapped(plot: i) } label: {
            VStack(spacing: 2) {
                Image(systemName: stage == 0 ? "plus" : stage == 3 ? "basket.fill" : "drop.fill").font(.system(size: 16, weight: .black))
                Text("Plot \(i + 1)").font(SK.font(13, .black))
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SK.cream.opacity(0.96)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plot \(i + 1)")
        .accessibilityValue(state)
        .accessibilityHint("Double tap to \(action)")
        .accessibilityIdentifier("garden-plot-\(i)")
    }

    private func picker(_ plot: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Plant something").font(SK.font(wide ? 17 : 20, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { AudioHub.shared.uiTap(); garden.pickerPlot = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.9)))
                }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("garden-picker-close")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(GardenPlant.allCases, id: \.self) { seed($0, plot: plot) } }.padding(.horizontal, 2).padding(.vertical, 2)
            }
            Text("Seeds are in the Shop. Water a plant to make it grow.").font(SK.font(12, .semibold)).foregroundStyle(SK.muted)
        }
        .padding(14)
        .frame(maxWidth: wide ? 560 : 420)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.cream).shadow(color: SK.shadow.opacity(0.2), radius: 10, y: 4))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("garden-picker")
    }

    private func seed(_ k: GardenPlant, plot: Int) -> some View {
        let have = care.store.count(k.seedID)
        return Button {
            AudioHub.shared.uiTap()
            if have > 0 { care.plantGarden(k, at: plot) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: k.symbol).font(.system(size: 26, weight: .heavy)).foregroundStyle(have > 0 ? SK.ink : SK.muted)
                Text(k.title).font(SK.font(13, .black)).foregroundStyle(SK.ink)
                Text(have > 0 ? "x\(have)" : "none").font(SK.font(12, .heavy)).foregroundStyle(have > 0 ? SK.ink : SK.muted)
            }
            .frame(width: 92, height: 92)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(have > 0 ? SK.mint.opacity(0.6) : Color.white.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .disabled(have == 0)
        .accessibilityLabel(have > 0 ? "Plant \(k.title). You have \(have) packets." : "\(k.title) seeds. You have none. They are sold in the Shop.")
        .accessibilityIdentifier("garden-seed-\(k.rawValue)")
    }
}
