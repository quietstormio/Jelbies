//
//  TrainCard.swift
//  The close-up's Train card (r1023-train): trick chips -> "Watch Pip sit" -> "Say 'Sit' now" with the mic listening by itself -> progress pips ->
//  "Pip learned Sit!" -> Try it. The Jelbie stays visible: portrait puts the card along the bottom, landscape on the right (about 44% of the width).
//  Text uses Dynamic Type styles, every control is 44 pt or more, the pips and the step are spoken, and nothing depends on colour or motion alone.
//

import SwiftUI

struct TrainCard: View {
    let voice: VoiceCoordinator
    let landscape: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let tr = voice.train {
            let bk = voice.book(for: tr.subject)
            let name = bk.names.displayName(tr.subject)
            let step = tr.step
            let headline = TrainSession.headline(step, name: name, word: { bk.word(for: $0) ?? $0.suggestion }, reps: { bk.progress($0) })
            VStack(alignment: .leading, spacing: 10) {
                Text(headline)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(FocusStyle.brown)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("train-headline")
                    .accessibilityAddTraits(.isHeader)
                content(tr, step: step, bk: bk, name: name)
                if step != .pick, !step.isListening || tr.noMic {
                    link("Choose another trick", id: "train-another") { voice.trainPickAgain() }
                }
            }
            .padding(14)
            .frame(maxWidth: landscape ? 360 : 520, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FocusStyle.cream.opacity(0.97))
                .shadow(color: FocusStyle.shadow.opacity(0.25), radius: 10, y: 4))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("train-card")
            .accessibilityValue(step.name)
        }
    }

    @ViewBuilder private func content(_ tr: TrainSession, step: TrainStep, bk: VoiceTraining, name: String) -> some View {
        switch step {
        case .pick:
            let tricks = VoiceTrick.allCases.filter { bk.unlocked($0) && $0 != .come }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(tricks, id: \.rawValue) { t in chip(t, bk: bk, name: name) }
            }
            Text("Come here: \(name) knows it already.").font(.footnote).foregroundStyle(FocusStyle.brown.opacity(0.75))
        case .demo(let t):
            pips(t, bk)
        case .listen(let t):
            pips(t, bk)
            if tr.noMic {
                Text("The microphone is off. Turn it on in Settings to teach by voice, or use the trick book to make \(name) do tricks he knows.")
                    .font(.footnote).foregroundStyle(FocusStyle.brown).accessibilityIdentifier("train-nomic")
            } else {
                listeningRow(tr)
            }
        case .heard(let t, _):
            pips(t, bk)
        case .missed(let t, let why):
            pips(t, bk)
            if !tr.heardText.isEmpty { Text("Heard: \u{201C}\(tr.heardText)\u{201D}").font(.footnote).foregroundStyle(FocusStyle.brown.opacity(0.8)).accessibilityIdentifier("train-heard") }
            HStack(spacing: 8) {
                button("Try again", id: "train-retry", primary: true) { voice.trainRetry() }
                if case .otherWord(_, let heard) = why { button("Use \u{201C}\(heard)\u{201D} instead", id: "train-instead", primary: false) { voice.trainUseInstead() } }
            }
        case .learned(let t):
            pips(t, bk)
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(FocusStyle.pink)
                Image(systemName: "heart.fill").foregroundStyle(FocusStyle.pink)
                Image(systemName: "sparkles").foregroundStyle(FocusStyle.pink)
            }
            .accessibilityHidden(true)
            .scaleEffect(reduceMotion ? 1 : 1.1)
            Color.clear.frame(height: 0).accessibilityIdentifier("train-learned").accessibilityLabel("\(name) learned \(t.title)")
            button("Try it", id: "train-tryit", primary: true) { voice.trainPick(t) }
        case .tryIt:
            if tr.noMic {
                Text("The microphone is off. Turn it on in Settings.").font(.footnote).foregroundStyle(FocusStyle.brown)
            } else {
                listeningRow(tr)
            }
        case .tried(let t, let ok, _):
            if ok {
                Color.clear.frame(height: 0).accessibilityIdentifier("train-tryit-ok").accessibilityLabel("\(name) did \(t.title)")
                HStack(spacing: 8) {
                    button("Teach another", id: "train-another-trick", primary: true) { voice.trainPickAgain() }
                    button("Done", id: "train-done", primary: false) { voice.trainDone() }
                }
            } else {
                HStack(spacing: 8) {
                    button("Try again", id: "train-retry", primary: true) { voice.trainRetry() }
                    button("Done", id: "train-done", primary: false) { voice.trainDone() }
                }
            }
        }
    }

    private func chip(_ t: VoiceTrick, bk: VoiceTraining, name: String) -> some View {
        let n = bk.progress(t), learned = bk.isLearned(t)
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            voice.trainPick(t)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: VoiceTrickBook.symbol(t)).font(.system(.subheadline).weight(.semibold))
                    Text(t.title).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    if learned { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.25, green: 0.55, blue: 0.35)) }
                }
                pipRow(n)
            }
            .foregroundStyle(FocusStyle.brown)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(FocusStyle.brown.opacity(learned ? 0.35 : 0.12), lineWidth: learned ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("train-chip-\(t.rawValue)")
        .accessibilityLabel(t.title)
        .accessibilityValue(learned ? "learned" : "\(n) of \(VoiceTuning.repsToLearn) lessons")
        .accessibilityHint(learned ? "\(name) does it, then you try saying it." : "\(name) does it and you say a word for it, \(VoiceTuning.repsToLearn) times.")
    }

    private func pipRow(_ n: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<VoiceTuning.repsToLearn, id: \.self) { i in
                // filled = done; an open ring with a number-free shape difference (not colour alone)
                Image(systemName: i < n ? "circle.fill" : "circle").font(.system(size: 11))
                    .foregroundStyle(i < n ? FocusStyle.pink : FocusStyle.brown.opacity(0.35))
            }
        }
        .accessibilityHidden(true)
    }

    private func pips(_ t: VoiceTrick, _ bk: VoiceTraining) -> some View {
        let n = bk.progress(t)
        return HStack(spacing: 8) {
            pipRow(n).scaleEffect(1.4, anchor: .leading).padding(.trailing, 14)
            Text("\(n)/\(VoiceTuning.repsToLearn)").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(FocusStyle.brown)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("train-pips")
        .accessibilityLabel("Lessons for \(t.title)")
        .accessibilityValue("\(n)/\(VoiceTuning.repsToLearn)")
    }

    private func listeningRow(_ tr: TrainSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill").font(.title3).foregroundStyle(voice.isListening ? FocusStyle.pink : FocusStyle.brown.opacity(0.5))
            VoiceBars(level: voice.level, id: "train-bars")
            Text(voice.isListening ? "Listening\u{2026}" : "Getting ready\u{2026}").font(.footnote.weight(.semibold)).foregroundStyle(FocusStyle.brown)
            Spacer(minLength: 0)
            if voice.isListening {
                Button { voice.release() } label: {
                    Text("Done").font(.footnote.weight(.bold)).foregroundStyle(FocusStyle.brown)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).accessibilityIdentifier("train-stop-listening").accessibilityLabel("Stop listening")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("train-listening")
        .accessibilityValue(voice.isListening ? "listening" : "waiting")
    }

    private func button(_ title: String, id: String, primary: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap(); action()
        } label: {
            Text(title).font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(primary ? Color.white : FocusStyle.brown)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(Capsule().fill(primary ? FocusStyle.pink : FocusStyle.brown.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func link(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.semibold)).underline().foregroundStyle(FocusStyle.brown)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
