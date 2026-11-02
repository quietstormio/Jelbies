//
//  IntroFlow.swift
//  The launch intro's state machine and its player (IntroView is only the skin). One run, no interaction needed:
//    loading -> playing (the whole clip, with its sting) -> holding (paused exactly on the last frame) -> fading (the menu is mounted underneath and
//    the intro view fades out over `IntroClip.fadeSeconds`) -> gone (player torn down: layer removed, AVPlayer released, observers dropped).
//  A tap jumps to the end state (the last frame is shown, never a replay). Nothing can play after `holding` begins: every play() is gated on the
//  stage, the end observer is removed when it fires, and after `gone` there is no player at all, so backgrounding / foregrounding cannot bring the clip back.
//  Rotating while it plays swaps in the other variant (portrait / landscape clip) at the same timestamp.
//

import SwiftUI
import AVFoundation
import QuartzCore

@MainActor @Observable
final class IntroFlow {
    enum Stage: String { case loading, playing, holding, fading, gone }

    private(set) var stage: Stage = .loading
    /// nil before start and after teardown.
    private(set) var player: AVPlayer?
    /// The clip is visible (playback really advanced, or the last frame is up).
    private(set) var shown = false
    /// The small "Skip" pill (fades in ~1 s after the clip starts, gone once the end state begins).
    private(set) var skipVisible = false
    private(set) var landscape = false
    /// Test seams: how often the clip was started from the top / restarted after the end (must stay 1 / 0).
    private(set) var playCalls = 0
    private(set) var variantSwaps = 0
    private(set) var stageLog: [Stage] = [.loading]
    var timeScale: Double = 1          // tests / captures stretch or squeeze the hold and fade
    @ObservationIgnored var holdSeconds = IntroClip.holdSeconds
    @ObservationIgnored var fadeSeconds = IntroClip.fadeSeconds
    @ObservationIgnored var onFadeBegins: () -> Void
    @ObservationIgnored var reduceMotion: Bool

    @ObservationIgnored private var ready = false
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var lagProbe: Any?
    @ObservationIgnored private var lagWorst = 0.0
    @ObservationIgnored private var volume: Float = 0
    @ObservationIgnored private var generation = 0          // bumped by a variant swap / teardown so stale callbacks do nothing

    init(reduceMotion: Bool = false, onFadeBegins: @escaping () -> Void = {}) {
        self.reduceMotion = reduceMotion
        self.onFadeBegins = onFadeBegins
    }

    // MARK: start

    func start(landscape: Bool) {
        guard player == nil, stage == .loading else { return }
        self.landscape = landscape
        guard let item = Self.item(landscape: landscape) else { enterHold(); return }
        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        volume = AudioHub.shared.introVideoVolume()
        p.volume = volume
        p.isMuted = volume <= 0
        player = p
        observe(item)
        let g = generation
        Task { @MainActor in          // never ready within 3 s: don't leave a blank screen
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if g == self.generation, !self.ready, self.stage == .loading { self.enterHold() }
        }
    }

    private static func item(landscape: Bool) -> AVPlayerItem? {
        guard let url = Bundle.main.url(forResource: IntroClip.resource(landscape: landscape), withExtension: IntroClip.fileExtension) else { return nil }
        #if targetEnvironment(simulator)
        // the headless simulator has no audio device and never readies an item that has an audio track: play the picture only (captures / tests)
        let asset = AVURLAsset(url: url), comp = AVMutableComposition()
        if let v = asset.tracks(withMediaType: .video).first, let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? t.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: v, at: .zero)
            t.preferredTransform = v.preferredTransform
            return AVPlayerItem(asset: comp)
        }
        #endif
        return AVPlayerItem(url: url)
    }

    private func observe(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        let g = generation
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, g == self.generation else { return }; self.reachedEnd() }
        }
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] it, _ in
            guard it.status != .unknown else { return }
            Task { @MainActor in
                guard let self, g == self.generation else { return }
                if it.status == .failed { NSLog("[melon] launch: intro clip failed: %@", String(describing: it.error)); self.enterHold() } else { self.itemReady() }
            }
        }
    }

    /// The first frame is decoded: play the whole clip (Reduce Motion: jump to its last frame instead).
    private func itemReady() {
        guard let p = player, !ready, stage == .loading || stage == .playing else { return }
        ready = true
        LaunchTiming.mark("intro: clip ready")
        let gs = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(IntroClip.skipAppearsAfter * 1e9))
            if gs == self.generation, self.stage == .loading || self.stage == .playing { self.skipVisible = true }
        }
        if reduceMotion { skipToEnd(); return }
        setStage(.playing)
        playCalls += 1
        p.play()
        let g = generation
        Task { @MainActor in          // playback never advanced: fade in anyway
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if g == self.generation { self.reveal() }
        }
        var base: Double?          // wall minus clip time at the first tick; growth beyond it is playback falling behind
        lagProbe = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.stage == .playing, p.rate > 0 else { return }
                if t.seconds >= 1.0 / 30 { self.reveal() }
                let off = CACurrentMediaTime() - t.seconds
                if base == nil { base = off }
                self.lagWorst = max(self.lagWorst, off - (base ?? off))
            }
        }
    }

    private func reveal() {
        guard !shown else { return }
        shown = true
        LaunchTiming.mark("intro: clip shown")
    }

    // MARK: end, hold, fade

    /// The last frame has been decoded and the player has stopped on it.
    private func reachedEnd() {
        guard stage == .loading || stage == .playing else { return }
        player?.pause()
        enterHold()
    }

    /// Pauses on the last frame (nothing moves from here on), then the fade begins after `holdSeconds`.
    private func enterHold() {
        guard stage == .loading || stage == .playing else { return }
        player?.pause()
        shown = true
        skipVisible = false
        setStage(.holding)
        LaunchTiming.mark("intro: clip end")
        let g = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.holdSeconds * self.timeScale * 1e9))
            // loads still running (a skip, or a slow phone): keep holding the last frame until they finish, at most `loadWaitCap` more
            let capEnd = CACurrentMediaTime() + IntroClip.loadWaitCap
            while g == self.generation, !IntroWarmup.isFinished, CACurrentMediaTime() < capEnd { try? await Task.sleep(nanoseconds: 50_000_000) }
            if g == self.generation { self.beginFade() }
        }
    }

    private func beginFade() {
        guard stage == .holding else { return }
        player?.pause()
        setStage(.fading)
        IntroGate.markSeen()
        LaunchTiming.mark("intro: fade begins")
        onFadeBegins()
        let g = generation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((self.fadeSeconds * self.timeScale + 0.05) * 1e9))
            if g == self.generation { self.teardown() }
        }
    }

    /// Fully release the player. Idempotent; the intro view calls it again from onDisappear.
    func teardown() {
        generation += 1
        if let o = lagProbe, let p = player {
            p.removeTimeObserver(o)
            NSLog("%@", String(format: "[melon] launch: intro playback: worst lag behind the wall clock %.0f ms", lagWorst * 1000))
        }
        lagProbe = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        statusObserver?.invalidate(); statusObserver = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        player = nil
        if stage != .gone { setStage(.gone); LaunchTiming.mark("intro: torn down") }
    }

    private func setStage(_ s: Stage) { guard s != stage else { return }; stage = s; stageLog.append(s) }

    // MARK: interaction

    /// A tap jumps to the end state: the last frame, held, then the fade (never a replay).
    func tap() {
        guard stage == .loading || stage == .playing else { return }
        skipToEnd()
    }

    private func skipToEnd() {
        guard let p = player, let item = p.currentItem, ready else { enterHold(); return }
        if volume > 0 && !reduceMotion { fadeOutAudio(p) }
        let dur = item.duration.seconds
        guard dur.isFinite, dur > 0 else { enterHold(); return }
        let g = generation
        p.pause()
        p.seek(to: CMTime(seconds: max(0, dur - 1.0 / 60), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in guard let self, g == self.generation else { return }; self.enterHold() }
        }
    }

    private func fadeOutAudio(_ p: AVPlayer) {
        let start = p.volume, steps = 5
        for i in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(i) / Double(steps)) { p.volume = start * Float(steps - i) / Float(steps) }
        }
    }

    /// The scene became active again: a clip that is playing carries on if the system paused it; one that has ended never restarts.
    func sceneActive() {
        guard let p = player else { return }
        switch stage {
        case .playing: if p.rate == 0 { p.play() }
        case .holding, .fading, .gone, .loading: p.pause()
        }
    }

    /// The screen turned: swap in the other variant at the same timestamp while the clip is still playing.
    func rotated(landscape now: Bool) {
        guard now != landscape else { return }
        landscape = now
        guard stage == .playing, let p = player, let new = Self.item(landscape: now) else { return }
        let t = p.currentTime()
        generation += 1
        variantSwaps += 1
        p.pause()
        p.replaceCurrentItem(with: new)
        observe(new)
        let g = generation
        p.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, g == self.generation, self.stage == .playing else { return }
                self.player?.play()
            }
        }
    }
}
