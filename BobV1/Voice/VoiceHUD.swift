//
//  VoiceHUD.swift
//  Voice v1 UI: the hold-to-talk mic button (bottom-left) with its one-time tip, the trick book button + sheet, and the screen-edge glow that
//  shows while he listens. The glow is a flat UI effect in Bob's tint (like the thought bubble); Bob himself stays 3D. Nothing here shows what
//  was heard: the trick book lists only the player's own bound words.
//

import SwiftUI

/// Press-and-hold mic. A plain view with a zero-distance drag (a Button cannot hold). Slashed when the mic is unusable (a tap opens the book
/// instead); a progress ring while the speech assets download.
struct VoiceMicButton: View {
    let voice: VoiceCoordinator
    var openBook: () -> Void
    /// The tutorial asks for a word: a gentle ring breathes around the button (static under Reduce Motion).
    var pulse = false
    @State private var down = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let slashed = voice.micUnusable
        let listening = voice.isListening || (down && !slashed)       // pressed state on the very frame of touch-down
        let lvl = CGFloat(voice.level)
        var progress: Double?
        if case .needsDownload(let p) = voice.availability { progress = p }
        return Image(systemName: slashed ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(listening ? Color.white : Color(red: 0.42, green: 0.34, blue: 0.30))
            .frame(width: 44, height: 44)
            .background(Circle().fill(listening ? FocusStyle.pink : Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.94))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            .overlay {
                if let p = progress {
                    Circle().trim(from: 0, to: max(0.05, p)).stroke(FocusStyle.pink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(1.5)
                }
            }
            .background {
                // live-level halo: 1.0x ... 1.25x with the voice
                if listening {
                    Circle().fill(FocusStyle.pink.opacity(0.18 + 0.22 * lvl))
                        .scaleEffect(1.0 + 0.25 * lvl)
                        .animation(.easeOut(duration: 0.08), value: voice.level)
                }
            }
            .overlay {
                if pulse, !listening {
                    Circle().strokeBorder(FocusStyle.pink.opacity(breathe ? 0.15 : 0.7), lineWidth: 3)
                        .scaleEffect(breathe && !reduceMotion ? 1.45 : 1.08)
                        .allowsHitTesting(false)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { breathe = true }
                        }
                        .onDisappear { breathe = false }
                }
            }
            .overlay(alignment: .top) {
                if listening { VoiceBars(level: voice.level).offset(y: -26).allowsHitTesting(false) }
            }
            .scaleEffect(listening ? 1.12 : 1)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true
                    if !slashed { voice.begin() }   // begin() warms the mic first thing
                }
                .onEnded { _ in
                    down = false
                    if slashed { openBook() } else { voice.release() }
                })
            .accessibilityElement()
            .accessibilityIdentifier("voice-mic")
            .accessibilityLabel(slashed ? "Microphone unavailable. Open tricks" : "Hold to talk to Bob")
            .accessibilityValue(listening ? "listening" : "ready, \(voice.openCount) talks, \(voice.glowShown) glows, glow \(voice.glowLatencyMs ?? -1) ms")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openBook() }                   // VoiceOver double-tap cannot hold: it opens the trick book
    }
}

/// Five small bars that bounce with the live level (they keep moving under Reduce Motion: they are the listening confirmation).
struct VoiceBars: View {
    let level: Float
    var id = "voice-bars"
    private static let weights: [CGFloat] = [0.55, 0.85, 1.0, 0.8, 0.6]
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(FocusStyle.pink)
                    .frame(width: 4, height: 4 + 14 * CGFloat(level) * Self.weights[i])
            }
        }
        .frame(height: 18, alignment: .bottom)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityElement()
        .accessibilityIdentifier(id)
        .accessibilityValue("\(Int(level * 100))")
    }
}

/// "Hold to talk": a one-time tip beside the mic (UI chrome). `-VoiceReset 1` shows it again.
struct VoiceTip: View {
    static let key = "VoiceTipSeen"
    let voice: VoiceCoordinator
    @State private var shown = UserDefaults.standard.integer(forKey: VoiceTip.key) == 0 || UserDefaults.standard.bool(forKey: "VoiceReset")
    @State private var visible = true

    var body: some View {
        if shown, voice.openCount == 0 {
            Text("Hold to talk")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(FocusStyle.brown)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 6, y: 3))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .accessibilityIdentifier("voice-tip")
                .task {
                    try? await Task.sleep(nanoseconds: 9_000_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { visible = false }
                    UserDefaults.standard.set(1, forKey: VoiceTip.key)
                }
        }
    }
}

/// Edge glow in Bob's tint, pulsing with the (smoothed) mic level; static under Reduce Motion. Never takes touches.
/// Four edge gradients, no blur: a full-screen Gaussian blur is an offscreen pass (plus a first-use shader compile) that cost the first glow
/// frames on a phone. It exists exactly while `isListening`, with no transition or animation either way (a fade reads as lag).
struct VoiceGlow: View {
    let voice: VoiceCoordinator
    let care: GameCare
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if voice.isListening {
                let t = care.select.blobs.first?.tint ?? SIMD3(0.70, 0.83, 0.945)
                let c = Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z))
                let k = reduceMotion ? 0.35 : 0.15 + 0.85 * Double(voice.mode.glowLevel)     // calm at silence, clearly moving with speech
                let w = CGFloat(46 + 50 * k)
                let strong = c.opacity(0.62 + 0.36 * k)
                ZStack {
                    VStack { LinearGradient(colors: [strong, c.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: w); Spacer() }
                    VStack { Spacer(); LinearGradient(colors: [strong, c.opacity(0)], startPoint: .bottom, endPoint: .top).frame(height: w) }
                    HStack { LinearGradient(colors: [strong, c.opacity(0)], startPoint: .leading, endPoint: .trailing).frame(width: w); Spacer() }
                    HStack { Spacer(); LinearGradient(colors: [strong, c.opacity(0)], startPoint: .trailing, endPoint: .leading).frame(width: w) }
                    VStack { Spacer(); VoiceBars(level: voice.level, id: "voice-glow-bars").padding(.bottom, 56) }       // the level bars, for the gesture path too
                }
                .ignoresSafeArea()
                .onAppear { voice.glowAppeared() }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("voice-glow")
                .accessibilityLabel("Bob is listening")
            }
        }
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }                                  // appears and disappears on the frame of the state change
    }
}

/// Small round button that opens the trick book (next to the mic).
struct VoiceBookButton: View {
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
            action()
        } label: {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.34, blue: 0.30))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(red: 0.97, green: 0.94, blue: 0.88)).opacity(0.92))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("voice-tricks")
        .accessibilityLabel("Tricks")
    }
}

// MARK: - Trick book

/// The notebook: Bob's name lesson and one row per trick (our name, the player's bound word or a dash, 3 progress dots, reliability).
/// Tapping a row has him do the trick now, so the next word said binds to it. "Forget" clears a word.
struct VoiceTrickBook: View {
    let voice: VoiceCoordinator
    var close: () -> Void
    @State private var drafts: [Int: String] = [:]

    static func symbol(_ t: VoiceTrick) -> String {
        let s: String
        switch t {
        case .sit: s = "arrow.down.to.line"; case .jacks: s = "figure.jumprope"; case .run: s = "figure.run"
        case .flip: s = "figure.gymnastics"; case .look: s = "eye.fill"; case .come: s = "arrow.down.circle.fill"
        case .spin: s = "arrow.triangle.2.circlepath"; case .hop: s = "arrow.up.circle.fill"; case .roll: s = "arrow.left.arrow.right.circle.fill"
        }
        return UIImage(systemName: s) != nil ? s : "star.fill"
    }

    var body: some View {
        let tr = voice.book          // (W2: the book of the Jelly the teaching is about: the close-up's Jelly)
        let subject = voice.subjectID
        let who = tr.names.displayName(subject)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(who)'s tricks")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(FocusStyle.brown)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-book-close").accessibilityLabel("Close tricks")
            }
            .padding(.leading, 6)
            ScrollView {
                VStack(spacing: 10) {
                    smartVoiceRow
                    ForEach(voice.care?.isTrainingCloseUp == true ? [subject] : voice.presentIDs, id: \.self) { nameRow(tr, id: $0) }
                    ForEach(VoiceTrick.allCases.filter { tr.unlocked($0) }, id: \.rawValue) { t in trickRow(t, tr) }
                }
                .padding(.bottom, 6)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .background(FocusStyle.cream.ignoresSafeArea())
        .accessibilityIdentifier("voice-trickbook")
        .accessibilityValue("\(subject)")
    }

    /// Settings: "Smart voice: On (Apple Intelligence)" when the phone understands free phrasing on device, else "Basic" (the rule parser), with why.
    private var smartVoiceRow: some View {
        let state = voice.ai.router.state
        let on = voice.ai.router.smartVoiceOn
        return HStack(spacing: 10) {
            Image(systemName: on ? "sparkles" : "waveform").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(on ? FocusStyle.pink : FocusStyle.brown).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart voice: \(on ? "On (Apple Intelligence)" : "Basic")")
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                Text(on ? state.detail : state.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(FocusStyle.brown.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.75)))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("smart-voice")
        .accessibilityLabel("Smart voice: \(on ? "On, Apple Intelligence" : "Basic")")
        .accessibilityValue(state.detail)
    }

    private func dots(_ n: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<VoiceTuning.repsToLearn, id: \.self) { i in
                Circle().fill(i < n ? FocusStyle.pink : FocusStyle.brown.opacity(0.15)).frame(width: 9, height: 9)
            }
        }
    }

    private func nameRow(_ tr: VoiceTraining, id: Int) -> some View {
        let name = tr.names.displayName(id)
        let nicks = tr.names.nicknames(for: id)
        let lesson = voice.nickLesson?.id == id ? voice.nickLesson : nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(FocusStyle.pink)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name: \(name)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                    Text("He knows it")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(FocusStyle.brown.opacity(0.7))
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(Color(red: 0.36, green: 0.68, blue: 0.45))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("voice-name")
            .accessibilityLabel("Name: \(name). He knows it")
            if !nicks.isEmpty {
                HStack(spacing: 6) {
                    ForEach(nicks, id: \.self) { n in
                        Button { tr.names.removeNickname(n, for: id) } label: {
                            HStack(spacing: 4) {
                                Text(n).font(.system(size: 13, weight: .semibold, design: .rounded))
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                            }
                            .foregroundStyle(FocusStyle.brown)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(FocusStyle.cream))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("voice-nickname-\(n)").accessibilityLabel("Nickname \(n). Remove")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Add nickname", text: Binding(get: { drafts[id] ?? "" }, set: { drafts[id] = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(FocusStyle.cream))
                    .submitLabel(.done).onSubmit { addDraft(tr, id) }
                    .accessibilityIdentifier("voice-nickname-field")
                Button { addDraft(tr, id) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(FocusStyle.pink)
                }
                .buttonStyle(.plain).disabled(VoiceMatcher.normalise(drafts[id] ?? "").isEmpty)
                .accessibilityIdentifier("voice-nickname-add").accessibilityLabel("Add nickname")
                Button { voice.startNicknameLesson(for: id); close() } label: {
                    Image(systemName: "mic.circle.fill").font(.system(size: 24)).foregroundStyle(FocusStyle.brown)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-nickname-say").accessibilityLabel("Teach a nickname by saying it \(VoiceTuning.nicknameReps) times")
            }
            if let l = lesson {
                Text("Hold the mic and say the nickname (\(l.reps) of \(VoiceTuning.nicknameReps))")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(FocusStyle.brown.opacity(0.7))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.75)))
    }

    private func addDraft(_ tr: VoiceTraining, _ id: Int) {
        if tr.names.addNickname(drafts[id] ?? "", for: id) { drafts[id] = "" }
    }

    private func trickRow(_ t: VoiceTrick, _ tr: VoiceTraining) -> some View {
        let word = tr.word(for: t)
        let n = tr.progress(t)
        let rel = Int((tr.reliability(t) * 100).rounded())
        return HStack(spacing: 8) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(); AudioHub.shared.uiTap()
                voice.show(t)
                close()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: Self.symbol(t)).font(.system(size: 18, weight: .semibold)).foregroundStyle(FocusStyle.brown)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                        HStack(spacing: 8) {
                            Text(word ?? "\u{2014}")
                                .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                                .padding(.horizontal, 9).padding(.vertical, 2)
                                .background(Capsule().fill(FocusStyle.brown.opacity(word == nil ? 0.06 : 0.12)))
                            dots(n)
                        }
                    }
                    Spacer()
                    Text(tr.isLearned(t) ? "\(rel)%" : "")
                        .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.pink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("voice-trick-\(t.rawValue)")
            .accessibilityLabel("\(t.title). \(word.map { "Word: \($0)." } ?? "No word yet.") \(n) of \(VoiceTuning.repsToLearn) lessons.\(tr.isLearned(t) ? " Reliability \(rel) percent." : "")")
            .accessibilityHint("\(tr.names.displayName(voice.subjectID)) does it now. The next word you say teaches it.")
            if word != nil {
                Button { withAnimation(CareMenu.spring) { tr.forget(t) } } label: {
                    Text("Forget").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(FocusStyle.brown.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("voice-forget-\(t.rawValue)")
                .accessibilityLabel("Forget the word for \(t.title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.75)))
    }
}
