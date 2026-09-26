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

    func testArtworkWidthDoesNotExceedWidestStationOrMaximum() throws {
        let font = NSFont.menuFont(ofSize: 0)
        let titles = ["Short", "A considerably longer SomaFM station name"]
        let expectedWidestWidth = titles
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max()

        let width = try XCTUnwrap(AlbumArtworkLayout.width(forStationTitles: titles, font: font))

        XCTAssertEqual(width, min(try XCTUnwrap(expectedWidestWidth), AlbumArtworkLayout.maximumWidth))
        XCTAssertLessThanOrEqual(width, try XCTUnwrap(expectedWidestWidth))
    }

    func testArtworkWidthIsUnavailableWithoutStations() {
        XCTAssertNil(AlbumArtworkLayout.width(forStationTitles: []))
    }

    func testArtworkWidthIsCappedAtFiveHundredPoints() throws {
        let veryLongStationTitle = String(repeating: "Wide station title ", count: 20)

        let width = try XCTUnwrap(AlbumArtworkLayout.width(forStationTitles: [veryLongStationTitle]))

        XCTAssertEqual(width, 500)
    }

    func testFallbackSearchURLUsesQueryItems() throws {
        let url = try XCTUnwrap(MusicSearchAPI.fallbackSearchURL(trackName: "Artist & Song"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "www.google.com")
        XCTAssertEqual(components.queryItems?.first?.value, "Artist & Song")
    }
}
