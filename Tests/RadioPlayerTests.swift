import AVFoundation
import XCTest
@testable import SomaFM_miniplayer

@MainActor
final class RadioPlayerTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.lastPlayedChannel)
        super.tearDown()
    }

    func testPauseDiscardsLivePlayerItem() throws {
        let radioPlayer = RadioPlayer(player: AVPlayer())

        radioPlayer.play(channel: try makeChannel())
        XCTAssertTrue(radioPlayer.hasActivePlayerItem)

        radioPlayer.pause()

        XCTAssertEqual(radioPlayer.state, .stopped)
        XCTAssertFalse(radioPlayer.hasActivePlayerItem)
    }

    func testNetworkWaitDiscardsItemAndResumesLive() throws {
        let channel = try makeChannel()
        let radioPlayer = RadioPlayer(player: AVPlayer())

        radioPlayer.play(channel: channel)
        radioPlayer.waitForNetwork()

        XCTAssertEqual(radioPlayer.state, .waitingForNetwork)
        XCTAssertFalse(radioPlayer.hasActivePlayerItem)

        radioPlayer.resumeAfterNetworkRecovery(channel: channel)

        XCTAssertEqual(radioPlayer.state, .buffering)
        XCTAssertTrue(radioPlayer.hasActivePlayerItem)
    }

    func testManualPausePreventsNetworkRecoveryFromRestartingPlayback() throws {
        let channel = try makeChannel()
        let radioPlayer = RadioPlayer(player: AVPlayer())

        radioPlayer.play(channel: channel)
        radioPlayer.pause()
        radioPlayer.resumeAfterNetworkRecovery(channel: channel)

        XCTAssertEqual(radioPlayer.state, .stopped)
        XCTAssertFalse(radioPlayer.hasActivePlayerItem)
    }

    private func makeChannel() throws -> Channel {
        let data = Data(
            """
            {
              "id": "test-channel",
              "title": "Test Channel",
              "updated": "2026-07-16T00:00:00Z",
              "listeners": "1",
              "playlists": [
                {
                  "url": "file:///private/tmp/somafm-radio-player-tests.aac",
                  "format": "aac",
                  "quality": "highest"
                }
              ]
            }
            """.utf8
        )
        return try JSONDecoder().decode(Channel.self, from: data)
    }
}
