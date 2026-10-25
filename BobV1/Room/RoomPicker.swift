//
//  RoomPicker.swift
//  Where the Jelbies live: one card per room (the home room and the ones bought in the Shop), a Move in button, and the white veil of the move.
//  Views only: GameScreen adds a button that presents `RoomPickerSheet` and puts `RoomSwitchVeil` over the game.
//

import SwiftUI

struct RoomPickerSheet: View {
    let care: GameCare
    var close: () -> Void
    @Environment(\.verticalSizeClass) private var vsc
    @State private var refusal: String?
    private var wide: Bool { vsc == .compact }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rooms").font(SK.font(26, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { AudioHub.shared.uiTap(); close() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .black)).foregroundStyle(SK.ink)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.9)))
                }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("room-picker-close")
            }
            .padding(.horizontal, 20).padding(.top, 16)
            if let refusal {
                Text(refusal).font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(SK.honey.opacity(0.9)))
                    .accessibilityIdentifier("room-picker-refusal")
            }
            if wide {
                ScrollView {
                    HStack(alignment: .top, spacing: 12) { ForEach(RoomCatalog.all, id: \.id) { card($0) } }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                ScrollView {
                    VStack(spacing: 12) { ForEach(RoomCatalog.all, id: \.id) { card($0) } }
                        .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(SK.cream.ignoresSafeArea())
        .accessibilityIdentifier("room-picker")
    }

    private func thumb(_ d: RoomDef, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).fill(SK.honey.opacity(0.3))
            if let img = UIImage(named: "room_thumb_\(d.id.rawValue)") {
                Image(uiImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
            } else {
                Image(systemName: "house.fill").font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(SK.ink.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func card(_ d: RoomDef) -> some View {
        let owned = care.store.ownsRoom(d.id), here = care.roomID == d.id
        let content = VStack(alignment: .leading, spacing: 8) {
            if wide { thumb(d, size: 110).frame(maxWidth: .infinity) }
            HStack(spacing: 12) {
                if !wide { thumb(d, size: 96) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.title).font(SK.font(18, .black)).foregroundStyle(SK.ink)
                    Text(d.blurb).font(SK.font(12, .semibold)).foregroundStyle(SK.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            action(d, owned: owned, here: here)
        }
        content
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.card).shadow(color: SK.shadow.opacity(0.10), radius: 5, y: 2))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(d.title)
            .accessibilityHint(d.blurb)
            .accessibilityIdentifier("room-card-\(d.id.rawValue)")
    }

    @ViewBuilder
    private func action(_ d: RoomDef, owned: Bool, here: Bool) -> some View {
        if here {
            Text("Home now").font(SK.font(14, .heavy)).foregroundStyle(SK.ink)
                .padding(.horizontal, 14).frame(minHeight: 44).background(Capsule().fill(SK.mint.opacity(0.85)))
                .accessibilityLabel("\(d.title) is your home now")
                .accessibilityIdentifier("room-here-\(d.id.rawValue)")
        } else if owned {
            Button {
                AudioHub.shared.uiTap()
                if let why = care.switchRoom(d.id) { refusal = why.message } else { close() }
            } label: {
                Text("Move in").font(SK.font(15, .black)).foregroundStyle(SK.cream)
                    .padding(.horizontal, 18).frame(minHeight: 44).background(Capsule().fill(SK.ink))
            }
            .buttonStyle(.plain).accessibilityLabel("Move in to \(d.title)").accessibilityIdentifier("room-movein-\(d.id.rawValue)")
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill").font(.system(size: 12, weight: .black)).foregroundStyle(SK.skyDeep)
                    Text("\(StoreTuning.roomPrices[d.id] ?? 0)").font(SK.font(15, .black)).foregroundStyle(SK.ink)
                }
                .padding(.horizontal, 10).frame(minHeight: 44).background(Capsule().fill(Color.white.opacity(0.85)))
                Text("In the Shop").font(SK.font(12, .heavy)).foregroundStyle(SK.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(d.title) is locked, costs \(StoreTuning.roomPrices[d.id] ?? 0) Drops in the Shop")
            .accessibilityIdentifier("room-locked-\(d.id.rawValue)")
        }
    }
}

/// The white veil of a room move. GameScreen overlays it on the game.
struct RoomSwitchVeil: View {
    let care: GameCare
    var body: some View {
        Color.white.opacity(Double(care.roomSwitch.wipe))
            .ignoresSafeArea()
            .allowsHitTesting(care.roomSwitch.phase != .off)
            .accessibilityHidden(true)
    }
}
