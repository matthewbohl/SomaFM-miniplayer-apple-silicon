import AppKit
import XCTest
@testable import SomaFM_miniplayer

final class MusicSearchAPITests: XCTestCase {
    func testDecodesArtworkAndTrackDestination() throws {
        let data = Data(
            """
            {
              "results": [
                {
                  "artistName": "Test Artist",
                  "collectionName": "Test Album",
                  "trackName": "Test Song",
                  "trackViewUrl": "https://music.apple.com/test-song",
                  "artworkUrl100": "https://example.com/artwork.jpg"
                }
              ]
            }
            """.utf8
        )

        let result = try XCTUnwrap(MusicSearchAPI.decodeFirstResult(from: data))

        XCTAssertEqual(result.artistName, "Test Artist")
        XCTAssertEqual(result.trackName, "Test Song")
        XCTAssertEqual(result.trackViewUrl.absoluteString, "https://music.apple.com/test-song")
        XCTAssertEqual(result.artworkUrl100?.absoluteString, "https://example.com/artwork.jpg")
    }

    func testArtworkIsOptional() throws {
        let data = Data(
            """
            {
              "results": [
                {
                  "artistName": "Test Artist",
                  "collectionName": "Test Album",
                  "trackName": "Test Song",
                  "trackViewUrl": "https://music.apple.com/test-song"
                }
              ]
            }
            """.utf8
        )

        XCTAssertNil(try XCTUnwrap(MusicSearchAPI.decodeFirstResult(from: data)).artworkUrl100)
    }

    func testArtworkWidthIsAlwaysFiveHundredPoints() {
        XCTAssertEqual(AlbumArtworkLayout.width, 500)
    }

    func testFallbackSearchURLUsesQueryItems() throws {
        let url = try XCTUnwrap(MusicSearchAPI.fallbackSearchURL(trackName: "Artist & Song"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first?.value, "Artist & Song")
    }
}
