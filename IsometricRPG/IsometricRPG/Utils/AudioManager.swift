import AVFoundation
import Foundation

/// Centralized audio management system for sound effects and background music
class AudioManager {

    // MARK: - Singleton

    static let shared = AudioManager()
    private init() {
        setupAudioSession()
    }

    // MARK: - Properties

    private var soundPlayers: [String: AVAudioPlayer] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?

    // Volume settings (0.0 to 1.0)
    var masterVolume: Float = 1.0 {
        didSet {
            updateAllVolumes()
        }
    }

    var sfxVolume: Float = 0.7 {
        didSet {
            updateAllVolumes()
        }
    }

    var musicVolume: Float = 0.5 {
        didSet {
            musicPlayer?.volume = musicVolume * masterVolume
        }
    }

    // Mute toggles
    var isSoundEnabled: Bool = true {
        didSet {
            if !isSoundEnabled {
                stopAllSounds()
            }
        }
    }

    var isMusicEnabled: Bool = true {
        didSet {
            if isMusicEnabled {
                // Resume music if there was a track playing
                musicPlayer?.play()
            } else {
                musicPlayer?.pause()
            }
        }
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default)
            try audioSession.setActive(true)

            // Handle interruptions (phone calls, etc.)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: audioSession
            )
        } catch {
            print("⚠️ Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Pause music on interruption
            musicPlayer?.pause()
        case .ended:
            // Resume music after interruption if enabled
            if isMusicEnabled {
                musicPlayer?.play()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Sound Effects

    /// Play a sound effect
    /// - Parameters:
    ///   - name: The name of the sound file (without extension)
    ///   - volume: Volume multiplier for this specific sound (0.0 to 1.0)
    func playSound(_ name: String, volume: Float = 1.0) {
        guard isSoundEnabled else { return }

        // Check if we have a cached player
        if let player = soundPlayers[name] {
            player.currentTime = 0
            player.volume = volume * sfxVolume * masterVolume
            player.play()
            return
        }

        // Try to load the sound
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") ??
                        Bundle.main.url(forResource: name, withExtension: "mp3") ??
                        Bundle.main.url(forResource: name, withExtension: "m4a") else {
            // No audio file found - silent fallback
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume * sfxVolume * masterVolume
            player.prepareToPlay()
            player.play()

            // Cache for reuse
            soundPlayers[name] = player
        } catch {
            print("⚠️ Failed to play sound '\(name)': \(error.localizedDescription)")
        }
    }

    /// Preload sound effects for faster playback
    func preloadSounds(_ soundNames: [String]) {
        for name in soundNames {
            guard soundPlayers[name] == nil else { continue }

            if let url = Bundle.main.url(forResource: name, withExtension: "wav") ??
                         Bundle.main.url(forResource: name, withExtension: "mp3") ??
                         Bundle.main.url(forResource: name, withExtension: "m4a") {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    soundPlayers[name] = player
                } catch {
                    print("⚠️ Failed to preload sound '\(name)': \(error.localizedDescription)")
                }
            }
        }
        print("✅ Preloaded \(soundPlayers.count) sounds")
    }

    /// Stop all currently playing sound effects
    func stopAllSounds() {
        for player in soundPlayers.values {
            player.stop()
        }
    }

    // MARK: - Background Music

    /// Play background music with optional fade-in
    /// - Parameters:
    ///   - trackName: The name of the music file (without extension)
    ///   - fadeIn: Duration of fade-in effect in seconds (0 for no fade)
    ///   - loop: Whether the music should loop indefinitely
    func playMusic(_ trackName: String, fadeIn: TimeInterval = 1.0, loop: Bool = true) {
        guard isMusicEnabled else { return }

        // Stop current music if playing
        if let currentMusic = musicPlayer, currentMusic.isPlaying {
            stopMusic(fadeOut: 0.5)
        }

        // Try to load the music file
        guard let url = Bundle.main.url(forResource: trackName, withExtension: "m4a") ??
                        Bundle.main.url(forResource: trackName, withExtension: "mp3") ??
                        Bundle.main.url(forResource: trackName, withExtension: "wav") else {
            print("⚠️ Music file '\(trackName)' not found")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loop ? -1 : 0  // -1 = infinite loop
            player.prepareToPlay()

            // Fade-in effect
            if fadeIn > 0 {
                player.volume = 0
                player.play()

                let targetVolume = musicVolume * masterVolume
                let steps = 20
                let stepDuration = fadeIn / Double(steps)
                let volumeIncrement = targetVolume / Float(steps)

                var currentStep = 0
                fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self, weak player] timer in
                    guard let self = self, let player = player else {
                        timer.invalidate()
                        return
                    }

                    currentStep += 1
                    player.volume = min(volumeIncrement * Float(currentStep), targetVolume)

                    if currentStep >= steps {
                        timer.invalidate()
                        self.fadeTimer = nil
                    }
                }
            } else {
                player.volume = musicVolume * masterVolume
                player.play()
            }

            musicPlayer = player
        } catch {
            print("⚠️ Failed to play music '\(trackName)': \(error.localizedDescription)")
        }
    }

    /// Stop background music with optional fade-out
    /// - Parameter fadeOut: Duration of fade-out effect in seconds (0 for immediate stop)
    func stopMusic(fadeOut: TimeInterval = 1.0) {
        guard let player = musicPlayer else { return }

        fadeTimer?.invalidate()
        fadeTimer = nil

        if fadeOut > 0 {
            let startVolume = player.volume
            let steps = 20
            let stepDuration = fadeOut / Double(steps)
            let volumeDecrement = startVolume / Float(steps)

            var currentStep = 0
            fadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak player] timer in
                guard let player = player else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                player.volume = max(startVolume - volumeDecrement * Float(currentStep), 0)

                if currentStep >= steps {
                    player.stop()
                    timer.invalidate()
                }
            }
        } else {
            player.stop()
        }
    }

    /// Pause music without stopping it (can be resumed)
    func pauseMusic() {
        musicPlayer?.pause()
    }

    /// Resume paused music
    func resumeMusic() {
        guard isMusicEnabled else { return }
        musicPlayer?.play()
    }

    /// Check if music is currently playing
    var isMusicPlaying: Bool {
        return musicPlayer?.isPlaying ?? false
    }

    // MARK: - Volume Control

    private func updateAllVolumes() {
        // Update all sound effect players
        for player in soundPlayers.values {
            player.volume = sfxVolume * masterVolume
        }

        // Update music player
        musicPlayer?.volume = musicVolume * masterVolume
    }

    func setMasterVolume(_ volume: Float) {
        masterVolume = max(0.0, min(1.0, volume))
    }

    func setSFXVolume(_ volume: Float) {
        sfxVolume = max(0.0, min(1.0, volume))
    }

    func setMusicVolume(_ volume: Float) {
        musicVolume = max(0.0, min(1.0, volume))
    }

    // MARK: - Cleanup

    deinit {
        NotificationCenter.default.removeObserver(self)
        fadeTimer?.invalidate()
    }
}

// MARK: - Sound Effect Names

extension AudioManager {
    /// Common sound effect names for easy reference
    enum SoundEffect {
        // UI Sounds
        static let buttonClick = "ui_button_click"
        static let menuOpen = "ui_menu_open"
        static let menuClose = "ui_menu_close"
        static let itemSelect = "ui_item_select"
        static let equip = "ui_equip"
        static let unequip = "ui_unequip"
        static let error = "ui_error"
        static let levelUp = "ui_level_up"

        // Gameplay Sounds
        static let shoot = "combat_shoot"
        static let hitEnemy = "combat_hit_enemy"
        static let hitPlayer = "combat_hit_player"
        static let enemyDeath = "combat_enemy_death"
        static let itemPickup = "item_pickup"
        static let healthPotion = "item_health_potion"
        static let xpGain = "xp_gain"
    }

    /// Common music track names for easy reference
    enum MusicTrack {
        static let mainMenu = "music_main_menu"
        static let gameplayForest = "music_gameplay_forest"
        static let gameplayDungeon = "music_gameplay_dungeon"
        static let combat = "music_combat"
        static let victory = "music_victory"
        static let gameOver = "music_game_over"
    }
}
