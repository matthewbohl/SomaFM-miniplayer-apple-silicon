//
//  MusicSearchAPI.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Foundation

struct MusicSearchResponse {
    let result: SearchResult?
    let destinationURL: URL?
}

public struct MusicSearchAPI {
    @discardableResult
    static func searchTrack(named trackName: String,
                            completion: @escaping (MusicSearchResponse) -> Void) -> URLSessionDataTask? {
        searchItunes(trackName: trackName, completion: completion)
    }
}

extension MusicSearchAPI {
    // MARK: - Networking

    struct SearchResultsList: Codable {
        let results: [SearchResult]
    }

    static func decodeFirstResult(from data: Data) -> SearchResult? {
        try? JSONDecoder().decode(SearchResultsList.self, from: data).results.first
    }

    static func fallbackSearchURL(trackName: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trackName)]
        return components?.url
    }

    private static func searchItunes(trackName: String,
                                     completion: @escaping (MusicSearchResponse) -> Void) -> URLSessionDataTask? {
        var iTunesSearchURL = URLComponents(string: "https://itunes.apple.com/search")!
        iTunesSearchURL.queryItems = [URLQueryItem(name: "term", value: trackName),
                                      URLQueryItem(name: "entity", value: "song"),
                                      URLQueryItem(name: "limit", value: "1"),
                                      URLQueryItem(name: "at", value: "1000lHGx")]

        guard let finalURL = iTunesSearchURL.url else {
            completion(MusicSearchResponse(result: nil, destinationURL: fallbackSearchURL(trackName: trackName)))
            return nil
        }

        let session = URLSession(configuration: URLSessionConfiguration.default)
        let request = URLRequest(url: finalURL)

        let task = session.dataTask(with: request) { data, response, _ in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let result = data.flatMap(decodeFirstResult)

            if result == nil || !(200..<300).contains(statusCode ?? 0) {
                Log.error("iTunesSearch: error")
            }

            completion(
                MusicSearchResponse(
                    result: result,
                    destinationURL: result?.trackViewUrl ?? fallbackSearchURL(trackName: trackName)
                )
            )
        }
        task.resume()
        return task
    }
}
