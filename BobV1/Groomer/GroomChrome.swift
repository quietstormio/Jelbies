//
//  GroomChrome.swift
//  The Groomer's screen furniture: the picker card (who goes, three tiers), the tap-to-skip layer, the tier label and the white fade over the 3D street
//  (Groomer/GroomRoom.swift draws the shop), the "So fresh!" banner and the blocked-entry toast. Views only; GameCare+Groom.swift owns the rules.
//  Reduce Motion: no spring on the banner; the street itself is still and the swaps are plain fades.
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
            if groom.inScene {          // the street itself is 3D (GroomRoom.swift); this layer is the tap-to-skip, the tier label and the white fade
                Color.clear.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { groom.skip() }
                    .accessibilityElement(children: .ignore).accessibilityLabel("The Jelly Spa. \(groom.tier.name).")
                    .accessibilityHint("Double tap to skip").accessibilityAddTraits(.isButton).accessibilityIdentifier("groom-shop")
                if groom.phase == .arriveIn || groom.phase == .shop {
                    VStack {
                        Text(groom.tier.name).font(SK.font(15, .semibold)).foregroundStyle(SK.ink)
                            .padding(.horizontal, 14).padding(.vertical, 6).background(Capsule().fill(DT.card))
                            .accessibilityIdentifier("groom-tier-name")
                        Spacer()
                        Text("Tap to skip").font(SK.font(12, .semibold)).foregroundStyle(SK.ink.opacity(0.55)).padding(.bottom, 26)
                    }
                    .padding(.top, vsc == .compact ? 10 : 64).allowsHitTesting(false).transition(.opacity)
                }
            }
            if groom.wipe > 0.001 {
                Color.white.opacity(Double(groom.wipe)).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            }
            if groom.celebrating {
                let late = groom.cheerT > GroomTuning.cheerSeconds - 0.8
                VStack {
                    Text(groom.tier.banner).font(SK.font(26, .semibold)).foregroundStyle(SK.ink)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Capsule().fill(DT.card))
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
                        Text(t).font(SK.font(15, .semibold)).foregroundStyle(SK.ink).multilineTextAlignment(.leading)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(DT.card))
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
        .allowsHitTesting(groom.picking || groom.inScene || groom.toast != nil)
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
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(DT.card))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain).accessibilityIdentifier("groom-picker")
        }
        .transition(.opacity)
    }

    private var pickerContent: some View {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "bubbles.and.sparkles.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(SK.ink)
                        Text("Jelly Spa").font(SK.font(22, .semibold)).foregroundStyle(SK.ink)
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
                                    Text(j.name).font(SK.font(14, .semibold)).foregroundStyle(SK.ink).lineLimit(1).minimumScaleFactor(0.7)
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 15, weight: .bold)).foregroundStyle(SK.ink)
                                }
                                .padding(.horizontal, 9).frame(minHeight: 44)
                                .dtChip(selected: on)
                            }
                            .buttonStyle(.plain).accessibilityLabel(j.name).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("groom-pick-\(j.id)")
                        }
                        Spacer(minLength: 0)
                    }
                    ForEach(GroomTier.allCases) { tier in
                        let total = tier.total(count: groom.picked.count)
                        Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); care.startGroom(tier) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tier.symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(SK.ink)
                                    .frame(width: 50, height: 50).background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tier == .royal ? SK.honey : tier == .spa ? SK.pink : SK.sky))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tier.name).font(SK.font(18, .semibold)).foregroundStyle(SK.ink)
                                    Text(tier.blurb).font(SK.font(12, .bold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                VStack(spacing: 0) {
                                    Text("\(total)").font(SK.font(20, .semibold)).foregroundStyle(SK.ink)
                                    Text("Drops").font(SK.font(11, .semibold)).foregroundStyle(SK.muted)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 66)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DT.card))
                            .opacity(total <= care.bath.wallet.count ? 1 : 0.65)
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(tier.name), \(total) Drops. \(tier.blurb)").accessibilityIdentifier("groom-tier-\(tier.rawValue)")
                    }
                    if let r = groom.refusal {
                        Text(r).font(SK.font(14, .semibold)).foregroundStyle(SK.pinkStrong).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("groom-refusal")
                    }
                    Button { AudioHub.shared.uiTap(); groom.cancelPicker() } label: {
                        Text("Not now").font(SK.font(16, .semibold)).foregroundStyle(SK.muted).padding(.horizontal, 22).frame(minHeight: 44)
                            .background(Capsule().fill(DT.card))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("groom-cancel")
                }
                .padding(16)
    }
}
