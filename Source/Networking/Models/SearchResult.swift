//
//  SearchResult.swift
//
//  Copyright © 2017 Evgeny Aleksandrov. All rights reserved.

import Foundation

public struct SearchResult: Codable {
    let artistName: String
    let collectionName: String
    let trackName: String
    let trackViewUrl: URL
    let artworkUrl100: URL?
}
