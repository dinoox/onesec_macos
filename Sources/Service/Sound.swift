//
//  Sound.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import AVFoundation
import Combine

enum SoundType: String {
    case open
    case close
    case notification
}

class SoundService: @unchecked Sendable {
    static let shared = SoundService()
    
    private var cancellables = Set<AnyCancellable>()
    
    private var audioPlayers: [SoundType: AVAudioPlayer] = [:]
    
    private init() {}
    
    func initialize() {
        preloadSounds()
        EventBus.shared.events
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .recordingStarted: playSound(.open)
                case .recordingStopped: playSound(.close)
                case .notificationReceived: playSound(.notification)
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    private func preloadSounds() {
        let soundFiles: [SoundType: String] = [
            .open: "open",
            .close: "close",
            .notification: "notification"
        ]
        
        for (soundType, fileName) in soundFiles {
            guard let url = Bundle.module.url(
                forResource: fileName,
                withExtension: "wav"
            ) else {
                log.error("Sound file not found: \(fileName)")
                continue
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                audioPlayers[soundType] = player
            } catch {
                log.error("Preload sound \(soundType) error: \(error)")
            }
        }
    }
    
    func playSound(_ soundType: SoundType, volume: Float = 0.4) {
        guard let player = audioPlayers[soundType] else {
            log.error("Sound \(soundType) not loaded, skipping playback")
            return
        }
        
        player.volume = max(0, min(1, volume))
        player.currentTime = 0
        player.play()
    }
    
    func destroy() {
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
    }
}
