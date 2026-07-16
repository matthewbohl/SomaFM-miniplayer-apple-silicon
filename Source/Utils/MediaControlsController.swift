//
//  MediaControlsController.swift
//
//  Copyright © 2026 Matthew Bohl. All rights reserved.

import MediaPlayer

enum MediaRemoteCommand: CaseIterable, Hashable {
    case play
    case pause
    case togglePlayPause
    case previous
    case next
}

enum MediaPlaybackState: Equatable {
    case playing
    case paused
    case interrupted
}

struct NowPlayingSnapshot: Equatable {
    let stationID: String
    let stationName: String
    let trackName: String?
    let playbackState: MediaPlaybackState
}

@MainActor
protocol MediaCommandHandling: AnyObject {
    func handlePlayCommand() -> Bool
    func handlePauseCommand() -> Bool
    func handleTogglePlayPauseCommand() -> Bool
    func handlePreviousCommand() -> Bool
    func handleNextCommand() -> Bool
}

protocol RemoteCommandCenterClient: AnyObject {
    func configureForLiveStream()
    func addHandler(for command: MediaRemoteCommand, handler: @escaping @MainActor () -> Bool)
    func setNavigationEnabled(_ isEnabled: Bool)
    func removeAllHandlers()
}

protocol NowPlayingInfoCenterClient: AnyObject {
    func publish(_ snapshot: NowPlayingSnapshot)
}

final class SystemRemoteCommandCenterClient: RemoteCommandCenterClient {
    private let commandCenter: MPRemoteCommandCenter
    private var targets: [MediaRemoteCommand: (command: MPRemoteCommand, target: Any)] = [:]

    init(commandCenter: MPRemoteCommandCenter = .shared()) {
        self.commandCenter = commandCenter
    }

    func configureForLiveStream() {
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.ratingCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
    }

    func addHandler(for command: MediaRemoteCommand, handler: @escaping @MainActor () -> Bool) {
        let remoteCommand = commandCenterCommand(for: command)
        remoteCommand.isEnabled = true

        if let existingTarget = targets[command] {
            existingTarget.command.removeTarget(existingTarget.target)
        }

        let target = remoteCommand.addTarget { _ in
            let wasHandled: Bool
            if Thread.isMainThread {
                wasHandled = MainActor.assumeIsolated { handler() }
            } else {
                wasHandled = DispatchQueue.main.sync {
                    MainActor.assumeIsolated { handler() }
                }
            }
            return wasHandled ? .success : .commandFailed
        }
        targets[command] = (remoteCommand, target)
    }

    func setNavigationEnabled(_ isEnabled: Bool) {
        commandCenter.previousTrackCommand.isEnabled = isEnabled
        commandCenter.nextTrackCommand.isEnabled = isEnabled
    }

    func removeAllHandlers() {
        for (_, registration) in targets {
            registration.command.removeTarget(registration.target)
        }
        targets.removeAll()
    }

    private func commandCenterCommand(for command: MediaRemoteCommand) -> MPRemoteCommand {
        switch command {
        case .play:
            return commandCenter.playCommand
        case .pause:
            return commandCenter.pauseCommand
        case .togglePlayPause:
            return commandCenter.togglePlayPauseCommand
        case .previous:
            return commandCenter.previousTrackCommand
        case .next:
            return commandCenter.nextTrackCommand
        }
    }
}

final class SystemNowPlayingInfoCenterClient: NowPlayingInfoCenterClient {
    private let infoCenter: MPNowPlayingInfoCenter

    init(infoCenter: MPNowPlayingInfoCenter = .default()) {
        self.infoCenter = infoCenter
    }

    func publish(_ snapshot: NowPlayingSnapshot) {
        let isPlaying = snapshot.playbackState == .playing
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: snapshot.trackName ?? snapshot.stationName,
            MPMediaItemPropertyArtist: snapshot.stationName,
            MPMediaItemPropertyAlbumTitle: "SomaFM",
            MPNowPlayingInfoPropertyExternalContentIdentifier: snapshot.stationID,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        switch snapshot.playbackState {
        case .playing:
            infoCenter.playbackState = .playing
        case .paused:
            infoCenter.playbackState = .paused
        case .interrupted:
            infoCenter.playbackState = .interrupted
        }
    }
}

@MainActor
final class MediaControlsController {
    private weak var handler: MediaCommandHandling?
    private let commandCenter: RemoteCommandCenterClient
    private let infoCenter: NowPlayingInfoCenterClient
    private var isActive = false
    private var isNavigationEnabled = false

    init(handler: MediaCommandHandling,
         commandCenter: RemoteCommandCenterClient = SystemRemoteCommandCenterClient(),
         infoCenter: NowPlayingInfoCenterClient = SystemNowPlayingInfoCenterClient()) {
        self.handler = handler
        self.commandCenter = commandCenter
        self.infoCenter = infoCenter

        commandCenter.configureForLiveStream()
    }

    deinit {
        commandCenter.removeAllHandlers()
    }

    func setNavigationEnabled(_ isEnabled: Bool) {
        isNavigationEnabled = isEnabled
        if isActive {
            commandCenter.setNavigationEnabled(isEnabled)
        }
    }

    func activate(stationID: String,
                  stationName: String,
                  trackName: String?,
                  playbackState: MediaPlaybackState) {
        if !isActive {
            registerCommandHandlers()
            commandCenter.setNavigationEnabled(isNavigationEnabled)
        }
        isActive = true
        publish(
            stationID: stationID,
            stationName: stationName,
            trackName: trackName,
            playbackState: playbackState
        )
    }

    func update(stationID: String,
                stationName: String,
                trackName: String?,
                playbackState: MediaPlaybackState) {
        guard isActive else { return }
        publish(
            stationID: stationID,
            stationName: stationName,
            trackName: trackName,
            playbackState: playbackState
        )
    }

    private func registerCommandHandlers() {
        commandCenter.addHandler(for: .play) { [weak self] in
            self?.handler?.handlePlayCommand() ?? false
        }
        commandCenter.addHandler(for: .pause) { [weak self] in
            self?.handler?.handlePauseCommand() ?? false
        }
        commandCenter.addHandler(for: .togglePlayPause) { [weak self] in
            self?.handler?.handleTogglePlayPauseCommand() ?? false
        }
        commandCenter.addHandler(for: .previous) { [weak self] in
            self?.handler?.handlePreviousCommand() ?? false
        }
        commandCenter.addHandler(for: .next) { [weak self] in
            self?.handler?.handleNextCommand() ?? false
        }
    }

    private func publish(stationID: String,
                         stationName: String,
                         trackName: String?,
                         playbackState: MediaPlaybackState) {
        infoCenter.publish(
            NowPlayingSnapshot(
                stationID: stationID,
                stationName: stationName,
                trackName: trackName,
                playbackState: playbackState
            )
        )
    }
}
