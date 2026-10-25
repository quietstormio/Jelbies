//
//  VoiceFeedback.swift
//  Voice v1 feedback: the player sees that Bob heard, understood and is learning. Pure models (the coordinator emits them) plus the overlay
//  view: a "heard" pill above the mic with the player's own words in quotes, a small thought bubble beside Bob's head (icons and dots only,
//  never text from Bob), a "Learned ..." toast and the "Now hold the mic and say a word" prompt after a trick-book row.
//  The bubble is anchored with `ThoughtBubbleView.project` like the touch hearts, so it follows him and survives the focus zoom.
//

import SwiftUI
import simd

nonisolated struct VoiceHeard: Equatable, Sendable { let id: Int; let text: String; let born: Double }
nonisolated struct VoiceToast: Equatable, Sendable { let id: Int; let text: String; let born: Double }
nonisolated struct TeachPrompt: Equatable, Sendable { let trick: VoiceTrick; let until: Double }
/// The understood natural command ("Pip: go to sleep"), or why it could not be done (`ok` false: "No beanbag to go to yet").
nonisolated struct VoiceUnderstood: Equatable, Sendable { let id: Int; let text: String; let ok: Bool; let born: Double }

nonisolated struct VoiceFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A rep was counted toward a word (dots, the new one pops).
        case rep(VoiceTrick, reps: Int)
        /// That rep completed the lesson (sparkles, check, toast).
        case learned(VoiceTrick, word: String)
        /// A learned word was obeyed (a small check as he starts).
        case obeyed(VoiceTrick)
        /// He knew the word but the reliability roll failed ("?" plus the trick and its reliability).
        case missed(VoiceTrick, pct: Int)
        /// A word he does not know and nothing to bind it to ("?").
        case unknown
        /// Nothing was recognised ("...").
        case nothing
        /// Too grumpy: the existing refusal (no bubble of ours).
        case grumpy
        case nameRep(Int)
        case nameLearned
        /// A built-in social command was understood (stop, praise ...).
        case social(VoiceSocial)
        /// Internal: a demonstration (trick-book row, debug teach): no feedback at all.
        case silent
        /// A natural command was understood (feed, drink, sleep, clean): a check with the action's glyph.
        case command(JellyAction)
        /// "Who's hungry?": the need's glyph, with a check when somebody is (`Int` = who) or a thumbs-up when nobody.
        case answer(NeedKind, Int?)

        /// Accessibility value / log name.
        var name: String {
            switch self {
            case .rep(let t, let n): return "rep \(t.rawValue) \(n)"
            case .learned(let t, _): return "learned \(t.rawValue)"
            case .obeyed(let t): return "obeyed \(t.rawValue)"
            case .missed(let t, _): return "missed \(t.rawValue)"
            case .unknown: return "unknown"
            case .nothing: return "nothing"
            case .grumpy: return "grumpy"
            case .nameRep(let n): return "name \(n)"
            case .nameLearned: return "name learned"
            case .social(let s): return "social \(s.rawValue)"
            case .silent: return "silent"
            case .command(let a): return "command \(a.key)"
            case .answer(let k, let who): return "answer \(k.rawValue) \(who.map(String.init) ?? "nobody")"
            }
        }
        /// Seconds the bubble stays.
        var life: Double {
            switch self {
            case .learned: return 2.6
            case .rep, .missed, .nameRep, .nameLearned, .command, .answer: return 2.2
            default: return 1.6
            }
        }
    }
    let id: Int
    let kind: Kind
    let born: Double
}

/// The overlay: heard pill + prompt / toast above the mic, the bubble beside his head.
struct VoiceFeedbackView: View {
    let voice: VoiceCoordinator
    let care: GameCare
    static let heardLife = 2.2
    static let understoodLife = 2.6

    var body: some View {
        // 20 Hz only while something is on screen; otherwise a slow poll (nothing to animate, so the full-screen overlay stays cheap)
        let busy = voice.feedback != nil || voice.toast != nil || voice.teachPrompt != nil || voice.nickLesson != nil || voice.heard != nil
        return TimelineView(.periodic(from: .now, by: busy ? 0.05 : 0.25)) { _ in
            let now = voice.now()
            ZStack {
                GeometryReader { geo in
                    if let f = voice.feedback, now - f.born < f.kind.life, f.kind != .grumpy, let p = anchor(geo.size) {
                        VoiceBubble(kind: f.kind, age: now - f.born, training: voice.training)
                            .position(x: min(max(p.x, 70), geo.size.width - 70), y: max(p.y, 110))
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("voice-bubble")
                            .accessibilityLabel("\(voice.subjectName) understood")
                            .accessibilityValue(f.kind.name)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()
                    if let t = voice.toast, now - t.born < 2.8 {
                        pill(t.text, id: "voice-toast", fade: now - t.born, life: 2.8, accent: true)
                    }
                    if voice.train == nil, let p = voice.teachPrompt, now < p.until, !voice.isListening {
                        pill("Now hold the mic and say a word for \(p.trick.title)", id: "voice-prompt", fade: 0, life: 99, accent: false)
                    }
                    if let l = voice.nickLesson, !voice.isListening {
                        pill("Hold the mic and say the nickname (\(l.reps) of \(VoiceTuning.nicknameReps))", id: "voice-nick-prompt", fade: 0, life: 99, accent: false)
                    }
                    if let u = voice.understood, now - u.born < Self.understoodLife {
                        understoodPill(u, fade: now - u.born)
                    }
                    if voice.train == nil, let h = voice.heard, now - h.born < Self.heardLife {
                        pill(h.text, id: "voice-heard", fade: now - h.born, life: Self.heardLife, accent: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16).padding(.bottom, 74)
            }
        }
        .allowsHitTesting(false)
    }

    private func anchor(_ size: CGSize) -> CGPoint? {
        let H = Float(BlobShape.H)
        let mid = care.headWorld - SIMD3(0, H * 0.5, 0)
        let w = SIMD3<Float>(mid.x + 1.0, mid.y - 0.64 + 0.8 * H, mid.z)           // beside the crown, like the touch hearts
        return ThoughtBubbleView.project(w, size: size, focus: care.focus.blend)
    }

    /// The understood command: a small check (or a question mark) and the line, in the cream pill.
    private func understoodPill(_ u: VoiceUnderstood, fade: Double) -> some View {
        let out = max(0, min(1, (Self.understoodLife - fade) / 0.4))
        return HStack(spacing: 7) {
            Image(systemName: u.ok ? "checkmark.circle.fill" : "questionmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(u.ok ? Color(red: 0.36, green: 0.68, blue: 0.45) : FocusStyle.pink)
            Text(u.text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(FocusStyle.brown)
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        .opacity(out)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("voice-understood")
        .accessibilityLabel(u.text)
        .accessibilityValue(u.ok ? "understood" : "cannot")
    }

    private func pill(_ text: String, id: String, fade: Double, life: Double, accent: Bool) -> some View {
        let out = max(0, min(1, (life - fade) / 0.4))
        return Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(accent ? Color.white : FocusStyle.brown)
            .lineLimit(2).multilineTextAlignment(.leading)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(accent ? FocusStyle.pink : FocusStyle.cream).shadow(color: FocusStyle.shadow.opacity(0.2), radius: 5, y: 2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            .opacity(out)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(id)
            .accessibilityLabel(text)
            .accessibilityValue(text)
    }
}

/// The thought bubble: cream circle/capsule, SF Symbols only.
struct VoiceBubble: View {
    let kind: VoiceFeedback.Kind
    let age: Double
    let training: VoiceTraining

    private func icon(_ t: VoiceTrick, size: CGFloat = 26) -> some View {
        Image(systemName: VoiceTrickBook.symbol(t)).font(.system(size: size, weight: .bold)).foregroundStyle(FocusStyle.brown)
    }
    private func dots(_ n: Int, popping: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<VoiceTuning.repsToLearn, id: \.self) { i in
                let isNew = popping && i == n - 1
                let pop = isNew ? CGFloat(min(1.6, 0.4 + age / 0.12 * 1.2)) : 1
                Circle().fill(i < n ? FocusStyle.pink : FocusStyle.brown.opacity(0.18))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isNew && age > 0.2 ? 1 : pop)
            }
        }
    }
    private func sym(_ n: String, _ c: Color, _ s: CGFloat = 26) -> some View {
        Image(systemName: n).font(.system(size: s, weight: .bold)).foregroundStyle(c)
    }

    var body: some View {
        let enter = CGFloat(min(1, 0.6 + age / 0.15 * 0.4))
        let leave = max(0, min(1, (kind.life - age) / 0.3))
        content
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FocusStyle.cream.opacity(0.97))
                .shadow(color: FocusStyle.shadow.opacity(0.22), radius: 6, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .overlay { if case .learned = kind { sparkles } }
            .scaleEffect(enter * 0.78)
            .opacity(leave)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .rep(let t, let n):
            VStack(spacing: 6) { icon(t); dots(n, popping: true) }
        case .learned(let t, _):
            VStack(spacing: 6) {
                HStack(spacing: 6) { icon(t); sym("checkmark.circle.fill", Color(red: 0.36, green: 0.68, blue: 0.45)) }
                dots(VoiceTuning.repsToLearn, popping: false)
            }
        case .obeyed:
            sym("checkmark", Color(red: 0.36, green: 0.68, blue: 0.45), 30)
        case .missed(let t, let pct):
            VStack(spacing: 4) {
                HStack(spacing: 6) { sym("questionmark", FocusStyle.pink); icon(t, size: 22) }
                Text("\(pct)%").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(FocusStyle.brown.opacity(0.85))
            }
        case .unknown:
            sym("questionmark", FocusStyle.pink, 30)
        case .nothing:
            sym("ellipsis", FocusStyle.brown.opacity(0.6), 28)
        case .nameRep(let n):
            VStack(spacing: 6) { sym("heart.fill", FocusStyle.pink); dots(n, popping: true) }
        case .nameLearned:
            HStack(spacing: 6) { sym("heart.fill", FocusStyle.pink); sym("checkmark.circle.fill", Color(red: 0.36, green: 0.68, blue: 0.45)) }
        case .social(let s):
            switch s {
            case .praise: sym("heart.fill", FocusStyle.pink, 30)
            case .scold: sym("exclamationmark", FocusStyle.brown, 30)
            case .play: sym("tennisball.fill", Color(red: 0.36, green: 0.68, blue: 0.45), 28)
            case .stop, .stopFighting: sym("hand.raised.fill", FocusStyle.brown, 28)
            case .goodnight: sym("moon.zzz.fill", Color(red: 0.45, green: 0.50, blue: 0.85), 30)
            case .wakeUp: sym("sun.max.fill", Color(red: 0.98, green: 0.78, blue: 0.30), 30)
            }
        case .command(let a):
            HStack(spacing: 6) { sym("checkmark", Color(red: 0.36, green: 0.68, blue: 0.45), 24); sym(Self.commandSymbol(a), FocusStyle.brown, 24) }
        case .answer(let k, let who):
            HStack(spacing: 6) {
                NeedGlyph(kind: k, size: 26)
                if who != nil { sym("checkmark", Color(red: 0.36, green: 0.68, blue: 0.45), 24) } else { sym("hand.thumbsup.fill", FocusStyle.brown, 22) }
            }
        case .grumpy, .silent:
            EmptyView()
        }
    }

    /// SF Symbol for a natural command's bubble.
    static func commandSymbol(_ a: JellyAction) -> String {
        let s: String
        switch a {
        case .feed: s = "fork.knife"; case .drink: s = CareMenu.waterSymbol; case .sleep: s = "moon.zzz.fill"; case .clean: s = CareMenu.cleanSymbol
        case .come: s = "arrow.down.circle.fill"; case .goTo: s = "figure.walk"; case .wear: s = "tshirt.fill"
        case .playWith: s = "soccerball"; case .race: s = "flag.checkered"; case .train: s = "dumbbell.fill"
        default: s = "star.fill"
        }
        return UIImage(systemName: s) != nil ? s : "star.fill"
    }

    private var sparkles: some View {
        let a = CGFloat(min(1, age / 0.6))
        return ZStack {
            ForEach(0..<6, id: \.self) { i in
                let ang = Double(i) / 6 * 2 * .pi + 0.3
                Image(systemName: "sparkle").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.30))
                    .offset(x: CGFloat(cos(ang)) * (34 + 22 * a), y: CGFloat(sin(ang)) * (30 + 20 * a))
                    .opacity(Double(1 - a * 0.7))
            }
        }
    }
}
