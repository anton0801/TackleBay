import AVFoundation
import Foundation

enum SoundEffect: String, CaseIterable {
    case uiTap = "tb_ui_tap"
    case itemChecked = "tb_item_checked"
    case tripStarted = "tb_trip_started"
    case returnSaved = "tb_return_saved"
    case ticketClaim = "tb_ticket_claim"
    case reelSpin = "tb_reel_spin"
    case reelStop = "tb_reel_stop"
    case partsReceived = "tb_parts_received"
    case miniatureBuilt = "tb_miniature_built"
}

/// Plays short effects and the single Bay Bonus loop. Everything is off by default and never blocks a save.
/// Uses the ambient category: respects the silent switch, mixes with the user's music and stays silent in background.
final class AudioCoordinator {
    static let ambienceFile = "tb_underwater_ambience"
    private static let maxConcurrentEffects = 3
    private static let tapInterval: TimeInterval = 0.08
    private static let duckFactor: Float = 0.5 // −6 dB
    private static let ambienceVolume: Float = 0.8

    var effectsEnabled = false
    var ambienceEnabled = false {
        didSet { if !ambienceEnabled { stopAmbience() } else if wantsAmbience { startAmbience() } }
    }

    private var players: [AVAudioPlayer] = []
    private var ambience: AVAudioPlayer?
    private var wantsAmbience = false
    private var lastTap = Date.distantPast
    private var sessionReady = false
    private var duckRestore: DispatchWorkItem?

    private func prepareSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        sessionReady = true
    }

    private func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "wav") }

    @discardableResult
    func play(_ effect: SoundEffect) -> AVAudioPlayer? {
        guard effectsEnabled else { return nil }
        if effect == .uiTap {
            let now = Date()
            guard now.timeIntervalSince(lastTap) >= Self.tapInterval else { return nil }
            lastTap = now
        }
        players.removeAll { !$0.isPlaying }
        guard players.count < Self.maxConcurrentEffects, let url = url(effect.rawValue) else { return nil }
        prepareSession()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.play()
        players.append(player)
        duckAmbience(for: player.duration)
        return player
    }

    /// Shortened spin: fade the whirr out over 80 ms instead of cutting it.
    func fadeOut(_ player: AVAudioPlayer?, duration: TimeInterval = 0.08) {
        guard let player = player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { player.stop() }
    }

    // MARK: Ambience

    func bonusSceneAppeared() {
        wantsAmbience = true
        if ambienceEnabled { startAmbience() }
    }

    func bonusSceneDisappeared() {
        wantsAmbience = false
        stopAmbience()
    }

    func appBecameActive() {
        if wantsAmbience && ambienceEnabled { startAmbience() }
    }

    func appWillResignActive() { stopAmbience() }

    private var pendingStop: DispatchWorkItem?

    private func startAmbience() {
        if let player = ambience {
            // Reuse the same player (also when it is fading out): never two copies of the loop.
            pendingStop?.cancel()
            pendingStop = nil
            if !player.isPlaying { player.play() }
            player.setVolume(Self.ambienceVolume, fadeDuration: 0.3)
            return
        }
        guard let url = url(Self.ambienceFile) else { return }
        prepareSession()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.play()
        player.setVolume(Self.ambienceVolume, fadeDuration: 0.3)
        ambience = player
    }

    private func stopAmbience() {
        guard let player = ambience, player.isPlaying, pendingStop == nil else { return }
        player.setVolume(0, fadeDuration: 0.15)
        let work = DispatchWorkItem { [weak self] in
            player.stop()
            self?.ambience = nil
            self?.pendingStop = nil
        }
        pendingStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func duckAmbience(for duration: TimeInterval) {
        guard let player = ambience, player.isPlaying else { return }
        player.setVolume(Self.ambienceVolume * Self.duckFactor, fadeDuration: 0.05)
        duckRestore?.cancel()
        let work = DispatchWorkItem { [weak player] in player?.setVolume(Self.ambienceVolume, fadeDuration: 0.2) }
        duckRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
