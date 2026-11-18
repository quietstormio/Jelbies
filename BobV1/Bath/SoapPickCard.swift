//
//  SoapPickCard.swift
//  "Pick a soap": the small card that shows EVERY time the player taps Clean (unless a soap was armed from the Bag). Always six tiles, three across, never scrolling: the free
//  Jelly soap first, then Lavender, Mint, Berry, Honey and Chamomile, each with its Blender bar, name and power-up chip. An owned soap shows its count ("x2"); a soap the player
//  does not own shows a price pill ("Buy 25"): tapping it buys one bar through the Shop's own path and starts the bath with it; with too few coins the tile is dimmed and
//  does nothing. The last soap used is ringed. X = not now. A cancelled bath uses nothing.
//

import SwiftUI

struct SoapPickCard: View {
    let care: GameCare
    let ps: CGFloat
    let landscape: Bool
    let width: CGFloat

    var body: some View {
        let choices = care.soapChoices
        let pre = care.preselectedSoap
        let tile: CGFloat = max(88, min((landscape ? 108 : 112) * ps, (width - 32 - 28 - 16 * ps) / 3))
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { care.dismissSoapCard() }
            VStack(spacing: landscape ? 4 : 10) {
                HStack {
                    Text("Pick a soap").playFont(landscape ? 17 : 21, .bold).foregroundStyle(CareMenu.brown)
                    Spacer()
                    Button { care.dismissSoapCard() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CareMenu.brown).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Not now").accessibilityIdentifier("soap-card-close")
                }
                .frame(height: landscape ? 26 : 30)
                let rows = stride(from: 0, to: choices.count, by: 3).map { Array(choices[$0..<min($0 + 3, choices.count)]) }
                VStack(spacing: landscape ? 4 : 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 6 * ps) { ForEach(row, id: \.rawValue) { soapTile($0, width: tile, picked: $0 == pre) } }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, landscape ? 8 : 14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CareMenu.cream).shadow(color: .black.opacity(0.25), radius: 14, y: 4))
            .fixedSize()
            .accessibilityElement(children: .contain).accessibilityIdentifier("soap-card")
        }
    }

    private func soapTile(_ soap: Soap, width: CGFloat, picked: Bool) -> some View {
        let owned = (care.soapCount(soap) ?? 1) > 0
        let affordable = owned || care.canBuySoap(soap)
        return Button { care.chooseSoap(soap) } label: {
            VStack(spacing: landscape ? 2 : 4) {
                SoapBarArt(soap: soap, size: width * (landscape ? 0.44 : 0.5))
                Text(soap.name).playFont(12 * ps, .bold).foregroundStyle(CareMenu.brown).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                chip(soap)
                status(soap, owned: owned)
            }
            .frame(width: width).padding(.vertical, landscape ? 5 : 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked ? Color(red: 0.36, green: 0.62, blue: 0.95) : Color.black.opacity(0.06), lineWidth: picked ? 3 : 1))
            .opacity(affordable ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(soap.name)
        .accessibilityValue(owned ? (soap.storeID == nil ? "Free" : "You have \(care.soapCount(soap) ?? 0)") : (affordable ? "Costs \(care.soapPrice(soap) ?? 0) coins. Tap to buy" : "Costs \(care.soapPrice(soap) ?? 0) coins. Not enough coins"))
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

    /// The bottom line of a tile: "Free" (Jelly soap), "x2" (owned) or a coin price pill ("Buy 25").
    @ViewBuilder
    private func status(_ soap: Soap, owned: Bool) -> some View {
        if soap.storeID == nil {
            Text("Free").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
        } else if owned {
            Text("x\(care.soapCount(soap) ?? 0)").font(SK.font(13, .black)).foregroundStyle(SK.ink)
        } else {
            HStack(spacing: 4) {
                JellyCoinIcon(size: 15)
                Text("Buy \(care.soapPrice(soap) ?? 0)").font(SK.font(12, .black)).foregroundStyle(SK.ink)
            }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(SK.honey))
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
