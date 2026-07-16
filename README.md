# SomaFM miniplayer

[![Latest Release](https://img.shields.io/github/release/ealeksandrov/SomaFM-miniplayer.svg)](https://github.com/ealeksandrov/SomaFM-miniplayer/releases/latest)
[![License](https://img.shields.io/github/license/ealeksandrov/SomaFM-miniplayer.svg)](LICENSE.md)
![Platform](https://img.shields.io/badge/platform-macos-lightgrey.svg)

![Screenshot](01.jpg)

This is unofficial player that gives you minimal, background playback of SomaFM channels.

## Apple silicon modernization

This fork is being updated for modern Apple silicon Macs. The current baseline builds the app with Xcode 27 for macOS 12.0+ and removes the old Carthage framework dependency path.

Current notes:

* Reachability is handled with `Network.framework`.
* Global media key support is temporarily disabled while the archived `MediaKeyTap` dependency is replaced or reconsidered.
* A no-sign arm64 Debug build can be verified with `Scripts/verify-arm64-debug-build.sh`.
* Personal Apple signing values are kept out of git; use `Config/Signing.local.xcconfig` for local signing.

## Local signing

Copy `Config/Signing.local.example.xcconfig` to `Config/Signing.local.xcconfig`, then set your Apple Developer team ID and bundle IDs in the local file. The local signing file is ignored by git.

After that, build normally from Xcode or run:

```sh
xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

## Installation

* Download latest version (sandboxed) from [Mac App Store](https://itunes.apple.com/us/app/somafm-miniplayer/id1303140142?mt=12&at=1000lHGx);
* Download dmg (non-sandboxed) from [releases page](https://github.com/ealeksandrov/SomaFM-miniplayer/releases/latest);
* Or clone this repo and build it from source.

### Difference between versions

In sandboxed (Mac App Store) version Mac Media Keys (⏪⏯⏩) are not supported.

## Author

Created and maintained by Evgeny Aleksandrov ([@ealeksandrov](https://twitter.com/ealeksandrov)).

## License

`SomaFM miniplayer` is available under the MIT license. See the [LICENSE.md](LICENSE.md) file for more info.
