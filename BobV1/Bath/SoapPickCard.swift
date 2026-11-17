//
//  SoapPickCard.swift
//  "Pick a soap": the small card that shows when the player opens a bath and owns any bought soap. Jelly soap (free) first, then the owned soaps (up to six tiles, three
//  across, never scrolling), each with its Blender bar, name and power-up chip. Tapping one starts the bath with it; the last soap used is ringed. No bought soaps: no card.
//

import SwiftUI

struct SoapPickCard: View {
    let care: GameCare
    let ps: CGFloat
    let landscape: Bool

    var body: some View {
        let choices = care.soapChoices
        let pre = care.preselectedSoap
        let tile: CGFloat = (landscape ? 108 : 112) * ps
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { care.dismissSoapCard() }
            VStack(spacing: landscape ? 6 : 10) {
                HStack {
                    Text("Pick a soap").playFont(landscape ? 18 : 21, .bold).foregroundStyle(CareMenu.brown)
                    Spacer()
                    Button { care.dismissSoapCard() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CareMenu.brown).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Not now").accessibilityIdentifier("soap-card-close")
                }
                .frame(height: 30)
                let rows = stride(from: 0, to: choices.count, by: 3).map { Array(choices[$0..<min($0 + 3, choices.count)]) }
                VStack(spacing: landscape ? 6 : 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8 * ps) { ForEach(row, id: \.rawValue) { soapTile($0, width: tile, picked: $0 == pre) } }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CareMenu.cream).shadow(color: .black.opacity(0.25), radius: 14, y: 4))
            .fixedSize()
            .accessibilityElement(children: .contain).accessibilityIdentifier("soap-card")
        }
    }

    private func soapTile(_ soap: Soap, width: CGFloat, picked: Bool) -> some View {
        Button { care.chooseSoap(soap) } label: {
            VStack(spacing: 4) {
                SoapBarArt(soap: soap, size: width * 0.52)
                Text(soap.name).playFont(12 * ps, .bold).foregroundStyle(CareMenu.brown).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                chip(soap)
            }
            .frame(width: width).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked ? Color(red: 0.36, green: 0.62, blue: 0.95) : Color.black.opacity(0.06), lineWidth: picked ? 3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(soap.name)
        .accessibilityValue(picked ? "Last used" : "")
        .accessibilityHint(soap.blurb)
        .accessibilityIdentifier("soap-\(soap.storeID ?? "jelly")")
    }

    @ViewBuilder
    private func chip(_ soap: Soap) -> some View {
        if let k = soap.chip { PerkChip(kind: k) }
        else {
            HStack(spacing: 4) { Image(systemName: "drop.fill").font(.system(size: 11, weight: .heavy)); Text("Plain wash").font(SK.font(11, .heavy)).lineLimit(1) }
                .foregroundStyle(SK.ink).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(SK.sky.opacity(0.5)))
        }
    }
}

/// A soap bar's picture (the Blender model, one render per soap).
struct SoapBarArt: View {
    let soap: Soap
    var size: CGFloat = 60
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(SK.sky.opacity(0.35))
            if let img = StoreThumb.soapImage(soap) { Image(uiImage: img).resizable().scaledToFit().padding(size * 0.06) }
        }
        .frame(width: size * 1.3, height: size).accessibilityHidden(true)
    }
}
