//
//  ShowcaseStage.swift
//  A real 3D room with the given characters in it (the same MelonStage the game uses), for the main menu and the Adoption Center.
//  `empty` shows the room alone (the main menu). `focusFirst` brings the first one to the camera close-up ("come here"), so the Adoption Center shows one Jelbie large.
//

import SwiftUI

struct ShowcaseStage: View {
    let roster: [Int]
    var focusFirst = false
    /// The room with nobody in it (the main menu): the one Jelly the stage needs is drawn hidden.
    var empty = false
    /// False inside a framed window (the species picker); the main menu and the old full-screen use fill the screen.
    var fullScreen = true
    /// Transparent, no room: only the Jelbie (the species picker draws its own stage and backdrop).
    var cutout = false
    /// Called once the focused Jelbie stands at the close-up spot (`focusFirst`), with the model (so the picker can ask for moves).
    /// A showcase Jelbie is BORN on that spot, so this is about a second after the stage goes live (never later than ~2.5 s), and exactly once while the stage stays on screen.
    var onReady: ((MelonModel) -> Void)?
    /// The opening story's Jelbies stay quiet (no arrival chirp) until their drop pops.
    var silent = false
    @State private var model: MelonModel?
    @State private var readyTask: Task<Void, Never>?
    @State private var readyFired = false

    /// Seconds after `.live` by which `onReady` fires even if the arrival never registers.
    static let readyDeadline: TimeInterval = 2.5
    /// The same for a group (three bodies on a row build and line up a little slower).
    static let readyDeadlineGroup: TimeInterval = 3.5

    var body: some View {
        ZStack {
            if !cutout { Color.black }
            if let model { MelonStage(model: model) }
        }
        .modifier(SafeAreaIf(on: fullScreen))
        .allowsHitTesting(false)
        .onAppear { appear() }
        .onDisappear { readyTask?.cancel(); readyTask = nil; model?.paused = true }
        .accessibilityHidden(true)
    }

    private func appear() {
        if let m = model {
            // back on screen after onDisappear paused it (a TabView page, a covering screen): run again, and redo the ready sequence if it never finished
            if m.paused { m.paused = false }
            if focusFirst, !readyFired, readyTask == nil { startReady(m) }
            return
        }
        JellyRoster.current = roster                       // the stage reads its characters from the process-wide roster
        // a PREVIEW model: awake, noon, no weather, fresh in-memory needs / stats / perks / words, no saved wear, nothing read from or written to the real save, no time away;
        // so it can never refuse to come, nor alter an owned Jelbie (and it does not touch the process-wide DayClock any more)
        let m = GameScreen.makeGameModel(jellyCount: roster.count, preview: true)
        m.care.touchPlay = m.touch
        m.care.silentArrival = silent
        m.hideJellies = empty
        m.cutout = cutout
        model = m
        if focusFirst { startReady(m) }
    }

    private func startReady(_ m: MelonModel) {
        readyTask = Task { @MainActor in
            for _ in 0..<80 where m.status != .live && !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }          // (a stage that never goes live still gets its ready after the deadline)
            let group = roster.count > 1          // the pick page: three bodies born on a row
            let all = Array(0..<max(roster.count, 1))
            let deadline = Date().addingTimeInterval(group ? Self.readyDeadlineGroup : Self.readyDeadline)
            while !Task.isCancelled, Date() < deadline, !all.allSatisfy({ m.care.brainFor($0) != nil }) { try? await Task.sleep(nanoseconds: 50_000_000) }          // the first fixed step has run (for everybody)
            guard !Task.isCancelled else { return }
            if group { m.care.comeHere(jellies: all) }          // born on the row's slots: they register as arrived within ~0.3 s and the close-up snaps (`focus.arrive(snap:)`)
            else { m.care.comeHere(jelly: 0) }          // already standing on the spot: it registers as arrived within ~0.3 s and the camera is simply in close-up (`BlobFocus.arrive(snap:)`)
            while !Task.isCancelled, Date() < deadline, !(group ? m.care.focusGroup.arrived.count == roster.count : m.care.focusGroup.arrived.contains(0)) { try? await Task.sleep(nanoseconds: 50_000_000) }
            if m.care.focusGroup.arrived.contains(0) { try? await Task.sleep(nanoseconds: 250_000_000) }          // (the drop from his birth height has settled)
            if group, !Task.isCancelled {          // never show the wide room: at the deadline the row is accepted where it stands and the camera snapped in
                if m.care.focus.phase == .approaching { for id in all { _ = m.care.focusGroup.markArrived(id) }; m.care.focus.arrive(snap: true) }
                for _ in 0..<20 where m.care.focus.blend < 0.97 && !Task.isCancelled { try? await Task.sleep(nanoseconds: 50_000_000) }
            }
            guard !Task.isCancelled, !readyFired else { return }
            readyFired = true
            onReady?(m)
        }
    }
}

private struct SafeAreaIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.ignoresSafeArea() } else { content } }
}
