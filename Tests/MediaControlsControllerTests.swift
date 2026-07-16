import XCTest
@testable import SomaFM_miniplayer

@MainActor
final class MediaControlsControllerTests: XCTestCase {
    func testRegistersAndRoutesSupportedCommands() {
        let handler = MediaCommandHandlerStub()
        let commandCenter = RemoteCommandCenterClientStub()
        let controller = MediaControlsController(
            handler: handler,
            commandCenter: commandCenter,
            infoCenter: NowPlayingInfoCenterClientStub()
        )

        XCTAssertFalse(commandCenter.invoke(.play))

        controller.activate(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: nil,
            playbackState: .playing
        )

        withExtendedLifetime(controller) {
            for command in MediaRemoteCommand.allCases {
                XCTAssertTrue(commandCenter.invoke(command))
            }
        }

        XCTAssertEqual(handler.playCount, 1)
        XCTAssertEqual(handler.pauseCount, 1)
        XCTAssertEqual(handler.toggleCount, 1)
        XCTAssertEqual(handler.previousCount, 1)
        XCTAssertEqual(handler.nextCount, 1)
        XCTAssertTrue(commandCenter.didConfigureForLiveStream)
    }

    func testFailedCommandReturnsFailure() {
        let handler = MediaCommandHandlerStub()
        handler.result = false
        let commandCenter = RemoteCommandCenterClientStub()
        let controller = MediaControlsController(
            handler: handler,
            commandCenter: commandCenter,
            infoCenter: NowPlayingInfoCenterClientStub()
        )

        controller.activate(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: nil,
            playbackState: .playing
        )

        withExtendedLifetime(controller) {
            XCTAssertFalse(commandCenter.invoke(.play))
        }
    }

    func testDoesNotPublishBeforeActivation() {
        let infoCenter = NowPlayingInfoCenterClientStub()
        let controller = MediaControlsController(
            handler: MediaCommandHandlerStub(),
            commandCenter: RemoteCommandCenterClientStub(),
            infoCenter: infoCenter
        )

        controller.update(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: "Test Track",
            playbackState: .playing
        )

        XCTAssertTrue(infoCenter.snapshots.isEmpty)
    }

    func testPublishesLiveMetadataAndPlaybackChanges() {
        let infoCenter = NowPlayingInfoCenterClientStub()
        let controller = MediaControlsController(
            handler: MediaCommandHandlerStub(),
            commandCenter: RemoteCommandCenterClientStub(),
            infoCenter: infoCenter
        )

        controller.activate(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: "Test Track",
            playbackState: .playing
        )
        controller.update(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: nil,
            playbackState: .paused
        )

        XCTAssertEqual(
            infoCenter.snapshots,
            [
                NowPlayingSnapshot(
                    stationID: "groovesalad",
                    stationName: "Groove Salad",
                    trackName: "Test Track",
                    playbackState: .playing
                ),
                NowPlayingSnapshot(
                    stationID: "groovesalad",
                    stationName: "Groove Salad",
                    trackName: nil,
                    playbackState: .paused
                )
            ]
        )
    }

    func testUpdatesNavigationAvailability() {
        let commandCenter = RemoteCommandCenterClientStub()
        let controller = MediaControlsController(
            handler: MediaCommandHandlerStub(),
            commandCenter: commandCenter,
            infoCenter: NowPlayingInfoCenterClientStub()
        )

        controller.setNavigationEnabled(true)

        XCTAssertNil(commandCenter.navigationEnabled)

        controller.activate(
            stationID: "groovesalad",
            stationName: "Groove Salad",
            trackName: nil,
            playbackState: .playing
        )

        XCTAssertEqual(commandCenter.navigationEnabled, true)
    }

    func testRemovesCommandHandlersWhenReleased() {
        let commandCenter = RemoteCommandCenterClientStub()
        var controller: MediaControlsController? = MediaControlsController(
            handler: MediaCommandHandlerStub(),
            commandCenter: commandCenter,
            infoCenter: NowPlayingInfoCenterClientStub()
        )

        controller = nil

        XCTAssertNil(controller)
        XCTAssertTrue(commandCenter.didRemoveAllHandlers)
    }
}

@MainActor
private final class MediaCommandHandlerStub: MediaCommandHandling {
    var result = true
    var playCount = 0
    var pauseCount = 0
    var toggleCount = 0
    var previousCount = 0
    var nextCount = 0

    func handlePlayCommand() -> Bool {
        playCount += 1
        return result
    }

    func handlePauseCommand() -> Bool {
        pauseCount += 1
        return result
    }

    func handleTogglePlayPauseCommand() -> Bool {
        toggleCount += 1
        return result
    }

    func handlePreviousCommand() -> Bool {
        previousCount += 1
        return result
    }

    func handleNextCommand() -> Bool {
        nextCount += 1
        return result
    }
}

private final class RemoteCommandCenterClientStub: RemoteCommandCenterClient {
    var didConfigureForLiveStream = false
    var navigationEnabled: Bool?
    var didRemoveAllHandlers = false
    private var handlers: [MediaRemoteCommand: @MainActor () -> Bool] = [:]

    func configureForLiveStream() {
        didConfigureForLiveStream = true
    }

    func addHandler(for command: MediaRemoteCommand, handler: @escaping @MainActor () -> Bool) {
        handlers[command] = handler
    }

    func setNavigationEnabled(_ isEnabled: Bool) {
        navigationEnabled = isEnabled
    }

    func removeAllHandlers() {
        handlers.removeAll()
        didRemoveAllHandlers = true
    }

    @MainActor
    func invoke(_ command: MediaRemoteCommand) -> Bool {
        handlers[command]?() ?? false
    }
}

private final class NowPlayingInfoCenterClientStub: NowPlayingInfoCenterClient {
    var snapshots: [NowPlayingSnapshot] = []

    func publish(_ snapshot: NowPlayingSnapshot) {
        snapshots.append(snapshot)
    }
}
