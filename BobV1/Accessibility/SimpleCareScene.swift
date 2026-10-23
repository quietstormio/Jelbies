//
//  SimpleCareScene.swift
//  The Assistive Access scene: the room on top, a big list of the Jelbies, and four huge buttons (Feed, Water, Pet, Bedtime).
//  Nothing is timed. No store, races, voice or settings. Registered in BobV1App as `AssistiveAccess { SimpleCareScene() }`.
//

import SwiftUI

struct SimpleCareScene: View {
    @State private var model = GameScreen.makeGameModel()
    @State private var selected: Int?
    @State private var petting = false
    private var care: GameCare { model.care }

    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                MelonStage(model: model)
                    .frame(height: g.size.height * 0.5)
                    .clipped()
                    .accessibilityHidden(true)          // the list below carries the same information, one big control each
                Group {
                    if let id = selected, let j = care.jelly(id) { actions(j) } else { list }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SK.cream)
            }
            .background(Color.black)
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            DayClock.shared.snapToNow()
            care.launched()
            care.store.grantStarterIfNeeded()
            AudioHub.shared.start()
        }
        .accessibilityIdentifier("simple-care-scene")
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Who do you want to look after?").font(SK.font(22, .black)).foregroundStyle(SK.ink)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader).padding(.top, 14)
                ForEach(care.jellies, id: \.id) { j in
                    Button { selected = j.id } label: {
                        HStack {
                            Text(j.name).font(SK.font(30, .black))
                            Spacer()
                            Text(care.needs(for: j.id).mood.word).font(SK.font(22, .bold))
                        }
                        .foregroundStyle(SK.ink).padding(18).frame(maxWidth: .infinity, minHeight: 72)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SK.honey))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(j.name), \(care.needs(for: j.id).mood.word)")
                    .accessibilityIdentifier("simple-jelbie-\(j.id)")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private func actions(_ j: JellyProfile) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { if petting { care.release(); petting = false }; selected = nil } label: {
                    Label("Back", systemImage: "chevron.left").font(SK.font(20, .black)).foregroundStyle(SK.ink)
                        .frame(minWidth: 88, minHeight: 56)
                }.accessibilityIdentifier("simple-back")
                Spacer()
                Text(j.name).font(SK.font(26, .black)).foregroundStyle(SK.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Color.clear.frame(width: 88, height: 1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                big("Feed", "fork.knife", id: "simple-feed") { care.feed(jelly: j.id) }
                big("Water", CareMenu.waterSymbol, id: "simple-water") { care.drink(jelly: j.id) }
                big(petting ? "Done" : "Pet", petting ? "checkmark" : "hand.raised.fill", id: "simple-pet") {
                    if petting { care.release(); petting = false } else { care.comeHere(jelly: j.id); petting = true }
                }
                big("Bedtime", "moon.zzz.fill", id: "simple-bedtime") { care.bedtimeAll() }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private func big(_ title: String, _ symbol: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button { AudioHub.shared.uiTap(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 34, weight: .bold))
                Text(title).font(SK.font(22, .black))
            }
            .foregroundStyle(SK.ink).frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(SK.honey))
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier(id)
    }
}
