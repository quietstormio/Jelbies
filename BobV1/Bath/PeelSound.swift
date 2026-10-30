//
//  PeelSound.swift
//  The app had no sound playback. A tiny procedurally generated "thwip" (a short falling-pitch chirp with a noisy sticky rip at the start),
//  played with AVAudioPlayer. It NEVER touches the AVAudioSession (no category, no activation): the default session is solo-ambient, which
//  follows the silent switch, and the voice mic session keeps whatever it set. Playback is skipped while he is listening.
//

import Foundation
import AVFoundation

@MainActor
protocol BathSound: AnyObject {
    func peel(kind: LintKind)
}

@MainActor
final class PeelSound: BathSound {
    static let shared = PeelSound()
    private var players: [AVAudioPlayer] = []
    private var next = 0
    /// True while the voice mic owns the session: stay silent.
    var muted: () -> Bool = { false }

    /// 16-bit mono WAV of the thwip.
    static func makeWAV(rate: Int = 22050, seconds: Double = 0.16, seed: UInt32 = 7) -> Data {
        let n = Int(Double(rate) * seconds)
        var pcm = [Int16](repeating: 0, count: n)
        var r = seed, phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            r ^= r << 13; r ^= r >> 17; r ^= r << 5
            let noise = Double(Int32(bitPattern: r)) / Double(Int32.max)
            let f = 1800 - 1300 * t                                    // falling chirp
            phase += 2 * .pi * f / Double(rate)
            let env = pow(1 - t, 2.2) * min(1, t * 60)                 // instant attack, quick decay
            let rip = noise * pow(max(0, 1 - t * 5), 2) * 0.6          // the sticky rip in the first fifth
            pcm[i] = Int16(max(-1, min(1, (sin(phase) * 0.55 + rip) * env)) * 20000)
        }
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    func peel(kind: LintKind) {
        guard !muted() else { return }
        if players.isEmpty {
            let wav = Self.makeWAV()
            players = (0..<4).compactMap { _ in try? AVAudioPlayer(data: wav) }
            players.forEach { $0.enableRate = true; $0.volume = 0.6; $0.prepareToPlay() }
        }
        guard !players.isEmpty else { return }
        let p = players[next % players.count]; next += 1
        p.rate = kind == .drop ? 1.35 : 0.9 + 0.2 * Float(next % 3) / 2
        p.currentTime = 0
        p.play()
    }
}
