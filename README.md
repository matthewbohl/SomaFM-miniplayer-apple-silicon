# SomaFM Mini Player for Apple Silicon

[![License](https://img.shields.io/github/license/matthewbohl/SomaFM-miniplayer-apple-silicon.svg)](LICENSE.md)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)
![Architecture](https://img.shields.io/badge/architecture-arm64-blue.svg)

![SomaFM Mini Player](01.jpg)

SomaFM Mini Player is an unofficial macOS menu-bar player that provides minimal, background playback of [SomaFM](https://somafm.com/) channels.

This fork modernizes the original [ealeksandrov/SomaFM-miniplayer](https://github.com/ealeksandrov/SomaFM-miniplayer) project for current Apple silicon Macs while preserving the original app's focused behavior and interface.

## Project Status

Version 1.3.0 currently builds and runs natively on arm64 with Xcode 27 beta and targets macOS 13.0 or later. This repository does not yet publish a signed or notarized binary release; build the application from source using the instructions below.

Current modernization work includes:

- Native arm64 Debug builds.
- Swift 5 project settings.
- Removal of the old Carthage dependency path.
- Network monitoring through `Network.framework`.
- An instance-based, main-actor playback controller.
- Explicit playback lifecycle states for stopped, buffering, playing, and network recovery.
- Disposal of live `AVPlayerItem` streams while paused, addressing upstream memory-growth issue #11.
- Timed stream metadata through `AVPlayerItemMetadataOutput`.
- Launch at login through the modern `SMAppService` main-application API.
- Local track and network alerts through the `UserNotifications` framework with explicit opt-in authorization.
- Global media controls and Now Playing metadata through the macOS `MediaPlayer` framework once station playback begins.
- Automatic Light and Dark appearance support through AppKit semantic colors and template images.
- A repository safety check that blocks tracked personal signing values, private signing material, local home paths, and common credential formats.
- XCTest coverage for playback stream disposal, recovery, launch-at-login, notifications, and media controls.
- Local signing configuration that keeps personal Apple Developer values out of git.

## Requirements

- An Apple silicon Mac.
- macOS 13.0 or later.
- Xcode 27 beta for the currently verified toolchain. Later compatible Xcode versions may also work.

## Build And Test

The application does not currently expose command-line options. The following commands build and test the project itself.

Build an unsigned arm64 Debug application:

```sh
xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Run the build smoke test:

```sh
Scripts/verify-arm64-debug-build.sh
```

Run the public-repository safety check independently:

```sh
Scripts/check-public-repo-safety.sh
```

Run the arm64 unit tests without code signing:

```sh
xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

Open the project in Xcode:

```sh
open SomaFM.xcodeproj
```

Select the `SomaFM` scheme and use Xcode's Run command to launch the application.

## Local Signing

Copy the tracked signing example to the ignored local configuration:

```sh
cp Config/Signing.local.example.xcconfig Config/Signing.local.xcconfig
```

Set your Apple Developer team ID and a unique app bundle ID in `Config/Signing.local.xcconfig`. Do not commit that file.

Build with local signing enabled:

```sh
xcodebuild -project SomaFM.xcodeproj -scheme SomaFM -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

## Development Workflow

Development practices and the required proposal, documentation, testing, commit, and push loop are defined in [AGENTS.md](AGENTS.md). Begin each task by checking repository status and reading the relevant local project context.

Useful repository commands:

```sh
git status --short --branch
git remote -v
rg --files
```

## Known Limitations And Next Steps

- Playback lifecycle coverage exists, but model decoding, settings, URL construction, and channel sorting need tests.
- Long-duration paused memory use still needs an Instruments soak test against upstream issue #11.
- Signing, notarization, packaging, and release documentation remain to be completed.

## Author And Upstream

This Apple silicon modernization fork is maintained by Matthew Bohl (matthewbohl@gmail.com). It is based on the original application created by Evgeny Aleksandrov ([@ealeksandrov](https://twitter.com/ealeksandrov)).

Upstream repository: [ealeksandrov/SomaFM-miniplayer](https://github.com/ealeksandrov/SomaFM-miniplayer)

Working repository: [matthewbohl/SomaFM-miniplayer-apple-silicon](https://github.com/matthewbohl/SomaFM-miniplayer-apple-silicon)

## License

SomaFM Mini Player is available under the MIT license. See [LICENSE.md](LICENSE.md).
