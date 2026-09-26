//
//  MenubarController.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Cocoa
import Network

enum AlbumArtworkLayout {
    static let maximumWidth: CGFloat = 500

    static func width(forStationTitles titles: [String], font: NSFont = .menuFont(ofSize: 0)) -> CGFloat? {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let widestTitle = titles
            .map { ceil(($0 as NSString).size(withAttributes: attributes).width) }
            .max() ?? 0

        guard widestTitle > 0 else { return nil }
        return min(widestTitle, maximumWidth)
    }
}

@MainActor
class MenubarController {
    let radioPlayer = RadioPlayer()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let notificationService: UserNotificationService
    private var mediaControlsController: MediaControlsController?

    let rightClickMenu = NSMenu()
    let stationsMenu = NSMenu()

    private let artworkItem = NSMenuItem()
    private let artworkContainerView = NSView()
    private let artworkImageView = NSImageView()
    let trackItem = NSMenuItem(title: "...", action: #selector(MenubarController.searchTrack), keyEquivalent: "")

    private let artworkCache = NSCache<NSURL, NSImage>()
    private var trackSearchTask: URLSessionDataTask?
    private var artworkTask: URLSessionDataTask?
    private var artworkRequestID = UUID()
    private var prefetchedArtwork: NSImage?
    private var displayedTrackName: String?
    private var trackSearchURL: URL?

    var sortedChannels: [Channel]? {
        guard let channels = SomaAPI.channels, channels.count > 0 else { return nil }

        if Settings.channelsSortOrder == .listeners {
            return channels.sorted { $0.listeners > $1.listeners }
        } else if Settings.channelsSortOrder == .alphabetically {
            return channels.sorted { $0.title < $1.title }
        } else {
            return channels
        }
    }

    init(notificationService: UserNotificationService) {
        self.notificationService = notificationService
        artworkCache.countLimit = 20

        SomaAPI.loadChannels()

        setupStatusItem()
        setupMenu()
        setupReachability()

        mediaControlsController = MediaControlsController(handler: self)
        updateMediaNavigationAvailability()

        if Settings.shouldPlayOnLaunch {
            togglePlay()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(MenubarController.updateStationsMenu), name: .somaApiChannelsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenubarController.updateTrackName), name: .radioPlayerTrackNameUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MenubarController.updatePlaybackState), name: .radioPlayerStateUpdated, object: nil)
    }

    func setupStatusItem() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(MenubarController.toggleStatus(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        setStatusItem(playing: false)
    }

    func setupMenu() {
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkContainerView.addSubview(artworkImageView)
        artworkItem.view = artworkContainerView
        artworkItem.isHidden = true
        rightClickMenu.addItem(artworkItem)

        trackItem.toolTip = "Click to search for this track"
        rightClickMenu.addItem(trackItem)

        let volumeItem = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeItem.view = setupVolumeSlider()
        rightClickMenu.addItem(volumeItem)

        let stationsItem = NSMenuItem(title: "Stations", action: nil, keyEquivalent: "")
        stationsItem.submenu = stationsMenu
        rightClickMenu.addItem(stationsItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(MenubarController.openPreferences(_:)), keyEquivalent: "")
        preferencesItem.target = self
        rightClickMenu.addItem(preferencesItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        rightClickMenu.addItem(NSMenuItem(title: "Quit SomaFM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        updateStationsMenu()
    }

    func setupVolumeSlider() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        container.autoresizingMask = [.width]
        let slider = NSSlider(frame: NSRect(x: 10, y: 0, width: 80, height: 30))
        slider.autoresizingMask = [.width, .height]
        slider.target = self
        slider.action = #selector(MenubarController.updateVolume(_:))
        slider.floatValue = Settings.volume

        container.addSubview(slider)

        return container
    }

    // MARK: - Actions

    @objc func toggleStatus(_ sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }

        if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) || event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePlay()
        }
    }

    @objc func updateStationsMenu() {
        stationsMenu.removeAllItems()

        guard let channels = SomaAPI.channels, let sortedChannels = sortedChannels else {
            stationsMenu.addItem(NSMenuItem(title: "No channels available", action: nil, keyEquivalent: ""))
            updateArtworkPresentation()
            updateMediaNavigationAvailability()
            return
        }

        let lastPlayedChannel = SomaAPI.lastPlayedChannel

        for channel in sortedChannels {
            let channelItem = NSMenuItem(title: channel.title, action: #selector(MenubarController.selectStation(_:)), keyEquivalent: "")
            channelItem.tag = channels.firstIndex(where: { $0.id == channel.id }) ?? 0
            channelItem.target = self

            if channel.id == lastPlayedChannel?.id {
                channelItem.state = .on
            }

            stationsMenu.addItem(channelItem)
        }

        updateArtworkPresentation()
        updateMediaNavigationAvailability()
    }

    @objc func updateTrackName() {
        updateMediaControls()

        if radioPlayer.state == .waitingForNetwork {
            resetTrackPresentation()
            trackItem.title = "Network unavailable"
            trackItem.target = nil
            return
        }

        guard let trackName = radioPlayer.currentTrack, !trackName.isEmpty else {
            resetTrackPresentation()
            trackItem.title = "..."
            trackItem.target = nil
            return
        }

        let truncatedTrackName = trackName.trunc(length: 35)
        trackItem.title = truncatedTrackName
        trackItem.target = self

        guard trackName != displayedTrackName else { return }
        displayedTrackName = trackName

        if Settings.notificationsEnabled {
            showTrackNotification()
        }

        prefetchArtwork(for: trackName)
    }

    @objc func updatePlaybackState() {
        setupRecoveringTimerIfNeeded()
        setStatusItem(playing: radioPlayer.isPlaybackActive)
        updateMediaControls()
        updateTrackName()
    }

    @objc func selectStation(_ sender: NSMenuItem) {
        guard let channels = SomaAPI.channels, channels.count > sender.tag else { return }

        selectChannel(channels[sender.tag])
    }

    @objc func updateVolume(_ sender: NSSlider) {
        radioPlayer.volume = sender.floatValue

        if sender.window?.currentEvent?.type == .leftMouseUp {
            Settings.volume = sender.floatValue
        }
    }

    @objc func openPreferences(_ sender: NSMenuItem) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        if let preferencesWindowController = appDelegate.preferencesWindowController {
            NSApp.activate(ignoringOtherApps: true)
            preferencesWindowController.showWindow(sender)
            preferencesWindowController.window?.delegate = appDelegate
        }
    }

    @objc func togglePlay() {
        _ = handleTogglePlayPauseCommand()
    }

    @objc func previousTap() {
        _ = handlePreviousCommand()
    }

    @objc func nextTap() {
        _ = handleNextCommand()
    }

    @objc func searchTrack() {
        guard let trackURL = trackSearchURL else { return }

        NSWorkspace.shared.open(trackURL)
    }

    // MARK: - Private

    @discardableResult
    private func selectChannel(_ channel: Channel) -> Bool {
        guard let channels = SomaAPI.channels,
            let selectedChannelIdx = channels.firstIndex(where: { $0.id == channel.id }) else { return false }
        guard isNetworkAvailable else {
            showConnectionError()
            return false
        }

        stationsMenu.items.forEach { $0.state = $0.tag == selectedChannelIdx ? .on : .off }

        radioPlayer.play(channel: channel)
        mediaControlsController?.activate(
            stationID: channel.id,
            stationName: channel.title,
            trackName: radioPlayer.currentTrack,
            playbackState: mediaPlaybackState
        )
        Log.info("Selected station \"\(channel.title)\"")
        return true
    }

    private var mediaPlaybackState: MediaPlaybackState {
        switch radioPlayer.state {
        case .playing, .buffering:
            return .playing
        case .stopped:
            return .paused
        case .waitingForNetwork:
            return .interrupted
        }
    }

    private func updateMediaControls() {
        guard let channel = SomaAPI.lastPlayedChannel else { return }

        mediaControlsController?.update(
            stationID: channel.id,
            stationName: channel.title,
            trackName: radioPlayer.currentTrack,
            playbackState: mediaPlaybackState
        )
    }

    private func updateMediaNavigationAvailability() {
        mediaControlsController?.setNavigationEnabled((sortedChannels?.count ?? 0) > 1)
    }

    private func showMenu() {
        statusItem.menu = rightClickMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func prefetchArtwork(for trackName: String) {
        trackSearchTask?.cancel()
        artworkTask?.cancel()

        let requestID = UUID()
        artworkRequestID = requestID
        prefetchedArtwork = nil
        trackSearchURL = MusicSearchAPI.fallbackSearchURL(trackName: trackName)
        updateArtworkPresentation()

        trackSearchTask = MusicSearchAPI.searchTrack(named: trackName) { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.artworkRequestID == requestID else { return }

                self.trackSearchTask = nil
                self.trackSearchURL = response.destinationURL

                guard let artworkURL = response.result?.artworkUrl100 else {
                    self.updateArtworkPresentation()
                    return
                }

                self.loadArtwork(from: artworkURL, requestID: requestID)
            }
        }
    }

    private func loadArtwork(from url: URL, requestID: UUID) {
        if let cachedArtwork = artworkCache.object(forKey: url as NSURL) {
            prefetchedArtwork = cachedArtwork
            updateArtworkPresentation()
            return
        }

        artworkTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            DispatchQueue.main.async {
                guard let self = self,
                      self.artworkRequestID == requestID,
                      (200..<300).contains(statusCode ?? 0),
                      let data = data,
                      let artwork = NSImage(data: data) else { return }

                self.artworkTask = nil
                self.artworkCache.setObject(artwork, forKey: url as NSURL)
                self.prefetchedArtwork = artwork
                self.updateArtworkPresentation()
            }
        }
        artworkTask?.resume()
    }

    private func updateArtworkPresentation() {
        guard let artwork = prefetchedArtwork,
              let channels = SomaAPI.channels,
              let artworkWidth = AlbumArtworkLayout.width(forStationTitles: channels.map(\.title)) else {
            artworkItem.isHidden = true
            artworkImageView.image = nil
            return
        }

        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 4
        artworkContainerView.frame = NSRect(
            x: 0,
            y: 0,
            width: artworkWidth + horizontalPadding * 2,
            height: artworkWidth + verticalPadding * 2
        )
        artworkImageView.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: artworkWidth,
            height: artworkWidth
        )
        artworkImageView.image = artwork
        artworkItem.isHidden = false
    }

    private func resetTrackPresentation() {
        guard displayedTrackName != nil || prefetchedArtwork != nil || trackSearchURL != nil else { return }

        trackSearchTask?.cancel()
        artworkTask?.cancel()
        trackSearchTask = nil
        artworkTask = nil
        artworkRequestID = UUID()
        prefetchedArtwork = nil
        displayedTrackName = nil
        trackSearchURL = nil
        updateArtworkPresentation()
    }

    private func setStatusItem(playing: Bool) {
        if playing {
            statusItem.button?.image = NSImage(named: "media_pause")
            statusItem.button?.toolTip = "Click to pause\nRight click to show menu"
        } else {
            statusItem.button?.image = NSImage(named: "media_play")
            statusItem.button?.toolTip = "Click to play\nRight click to show menu"
        }
    }

    private func showTrackNotification() {
        guard let trackName = radioPlayer.currentTrack else { return }
        let stationName = SomaAPI.lastPlayedChannel?.title ?? "SomaFM"

        Task {
            do {
                try await notificationService.sendTrackNotification(station: stationName, track: trackName)
            } catch {
                Log.error("Unable to deliver track notification: \(error)")
            }
        }
    }

    // MARK: - Reachability

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "SomaFM.NetworkMonitor")
    private var isNetworkAvailable = true
    private var resumePlaybackTimer: Timer?

    private func setupReachability() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let wasNetworkAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = path.status == .satisfied
                self.updateTrackName()

                if !wasNetworkAvailable && self.isNetworkAvailable {
                    self.recoverFromConnectionErrorIfNeeded()
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private func setupRecoveringTimerIfNeeded() {
        guard !isNetworkAvailable, radioPlayer.state == .buffering else { return }

        resumePlaybackTimer?.invalidate()
        resumePlaybackTimer = Timer.scheduledTimer(timeInterval: 5,
                                                   target: self,
                                                   selector: #selector(MenubarController.showConnectionError),
                                                   userInfo: nil,
                                                   repeats: false)
    }

    private func recoverFromConnectionErrorIfNeeded() {
        resumePlaybackTimer?.invalidate()
        radioPlayer.resumeAfterNetworkRecovery(channel: SomaAPI.lastPlayedChannel)
    }

    @objc func showConnectionError() {
        resumePlaybackTimer?.invalidate()
        updateTrackName()

        if radioPlayer.isPlaybackActive {
            radioPlayer.waitForNetwork()
        } else {
            radioPlayer.pause()
        }
        setStatusItem(playing: true)

        Task {
            do {
                try await notificationService.sendNetworkErrorNotification()
            } catch {
                Log.error("Unable to deliver network error notification: \(error)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.setStatusItem(playing: false)
        }
    }
}

extension MenubarController: MediaCommandHandling {
    func handlePlayCommand() -> Bool {
        if radioPlayer.isPlaybackActive {
            return true
        }

        guard isNetworkAvailable else {
            showConnectionError()
            return false
        }
        guard let savedChannel = SomaAPI.lastPlayedChannel else { return false }
        return selectChannel(savedChannel)
    }

    func handlePauseCommand() -> Bool {
        if radioPlayer.isPlaybackActive {
            radioPlayer.pause()
        }
        return true
    }

    func handleTogglePlayPauseCommand() -> Bool {
        radioPlayer.isPlaybackActive ? handlePauseCommand() : handlePlayCommand()
    }

    func handlePreviousCommand() -> Bool {
        guard let sortedChannels = sortedChannels,
            let lastPlayedChannel = SomaAPI.lastPlayedChannel,
            let lastPlayedIndex = sortedChannels.firstIndex(where: { $0.id == lastPlayedChannel.id })
            else { return false }

        let newIndex = lastPlayedIndex == 0 ? sortedChannels.count - 1 : lastPlayedIndex - 1
        return selectChannel(sortedChannels[newIndex])
    }

    func handleNextCommand() -> Bool {
        guard let sortedChannels = sortedChannels,
            let lastPlayedChannel = SomaAPI.lastPlayedChannel,
            let lastPlayedIndex = sortedChannels.firstIndex(where: { $0.id == lastPlayedChannel.id })
            else { return false }

        let newIndex = lastPlayedIndex == sortedChannels.count - 1 ? 0 : lastPlayedIndex + 1
        return selectChannel(sortedChannels[newIndex])
    }
}
