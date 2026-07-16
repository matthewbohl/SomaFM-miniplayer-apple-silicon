//
//  RadioPlayer.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import AVFoundation
import Foundation

extension Notification.Name {
    static let radioPlayerTrackNameUpdated = Notification.Name("RadioPlayer.TrackName.Updated")
    static let radioPlayerStateUpdated = Notification.Name("RadioPlayer.State.Updated")
}

@MainActor
final class RadioPlayer: NSObject {
    enum State: Equatable {
        case stopped
        case buffering
        case playing
        case waitingForNetwork
    }

    private let player: AVPlayer
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var timeControlStatusToken: NSKeyValueObservation?

    private(set) var state: State = .stopped {
        didSet {
            guard state != oldValue else { return }
            NotificationCenter.default.post(name: .radioPlayerStateUpdated, object: self)
        }
    }

    private(set) var currentTrack: String? {
        didSet {
            guard currentTrack != oldValue else { return }
            NotificationCenter.default.post(name: .radioPlayerTrackNameUpdated, object: self)
        }
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var isPlaybackActive: Bool {
        state != .stopped
    }

    var hasActivePlayerItem: Bool {
        player.currentItem != nil
    }

    init(player: AVPlayer = AVPlayer()) {
        self.player = player
        super.init()

        player.volume = Settings.volume
        timeControlStatusToken = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateStateFromPlayer()
            }
        }
    }

    func play(channel: Channel) {
        Settings.lastPlayedChannelId = channel.id
        startLiveStream(channel: channel)
    }

    func pause() {
        discardCurrentStream()
        state = .stopped
    }

    func waitForNetwork() {
        guard isPlaybackActive else { return }

        discardCurrentStream()
        state = .waitingForNetwork
    }

    func resumeAfterNetworkRecovery(channel: Channel?) {
        guard state == .waitingForNetwork, let channel = channel else { return }
        startLiveStream(channel: channel)
    }

    // MARK: - Private

    private func startLiveStream(channel: Channel) {
        guard let playlist = channel.bestQualityPlaylist else {
            pause()
            return
        }

        discardCurrentStream()

        let playerItem = AVPlayerItem(url: playlist.url)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: .main)
        playerItem.add(metadataOutput)

        self.metadataOutput = metadataOutput
        state = .buffering
        player.replaceCurrentItem(with: playerItem)
        player.play()
    }

    private func discardCurrentStream() {
        player.pause()

        if let metadataOutput = metadataOutput, let currentItem = player.currentItem {
            metadataOutput.setDelegate(nil, queue: nil)
            currentItem.remove(metadataOutput)
        }

        metadataOutput = nil
        player.replaceCurrentItem(with: nil)
        currentTrack = nil
    }

    private func updateStateFromPlayer() {
        guard state != .stopped, state != .waitingForNetwork else { return }

        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        case .paused:
            if player.currentItem == nil {
                state = .stopped
            }
        @unknown default:
            state = .buffering
        }
    }
}

extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let trackName = groups.lazy
            .flatMap { $0.items }
            .compactMap { $0.stringValue }
            .first

        Task { @MainActor [weak self] in
            guard self?.metadataOutput === output else { return }
            self?.currentTrack = trackName
        }
    }
}
